#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$EmacsPath,

    [ValidateNotNullOrEmpty()]
    [string]$PackageUserDir,

    [switch]$SkipErt,

    [switch]$SkipCompile,

    [switch]$SkipStartup,

    [switch]$RequireAllModules,

    [switch]$RequireDependencies
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$passed = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$cleanedByteCode = 0
$validationRoot = $null

function Find-OrgSeqEmacs {
    [CmdletBinding()]
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            return $null
        }
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }

    $command = Get-Command emacs -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @(
        @($env:ProgramFiles, 'Emacs'),
        @(${env:ProgramFiles(x86)}, 'Emacs'),
        @($env:LOCALAPPDATA, 'Programs\Emacs')
    )) {
        if ($entry[0]) {
            $candidateRoot = Join-Path $entry[0] $entry[1]
            if (Test-Path -LiteralPath $candidateRoot -PathType Container) {
                $roots.Add($candidateRoot)
            }
        }
    }

    foreach ($root in $roots) {
        $directories = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        foreach ($directory in $directories) {
            $candidate = Join-Path $directory.FullName 'bin\emacs.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    return $null
}

function Invoke-OrgSeqNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($name in $Environment.Keys) {
        $startInfo.Environment[$name] = [string]$Environment[$name]
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start $FilePath"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Add-CheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [pscustomobject]$Result
    )

    if ($Result.ExitCode -eq 0) {
        $passed.Add($Name)
        return
    }

    $failed.Add($Name)
    $detail = @($Result.StdErr, $Result.StdOut) |
        ForEach-Object { $_ -split '\r?\n' } |
        Where-Object { $_.Trim() } |
        Select-Object -First 1
    if ($detail) {
        $warnings.Add("$Name`: $($detail.Trim())")
    }
}

function Remove-OrgSeqByteCode {
    [CmdletBinding()]
    param()

    $removed = 0
    $byteCode = Get-ChildItem -LiteralPath $RepoRoot -Filter '*.elc' -File -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $byteCode) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $file.FullName)) {
            $removed++
        }
    }
    return $removed
}

$emacs = Find-OrgSeqEmacs -ExplicitPath $EmacsPath
if (-not $emacs) {
    [pscustomobject]@{
        Passed = @()
        Failed = @('Locate Emacs 30+')
        Warnings = @('Pass -EmacsPath or install Emacs 30+ in a standard location.')
        CleanedByteCode = 0
        EmacsPath = $null
    }
    exit 1
}

$resolvedPackageUserDir = $null
$packageUserDirSetup = ''
if ($PackageUserDir) {
    if (-not (Test-Path -LiteralPath $PackageUserDir -PathType Container)) {
        [pscustomobject]@{
            Passed = @()
            Failed = @('Locate package user directory')
            Warnings = @("Package user directory not found: $PackageUserDir")
            CleanedByteCode = 0
            EmacsPath = $emacs
            PackageUserDir = $null
        }
        exit 1
    }

    $resolvedPackageUserDir = (Resolve-Path -LiteralPath $PackageUserDir -ErrorAction Stop).Path
    $packageUserDirForElisp = ($resolvedPackageUserDir -replace '\\', '/') + '/'
    $packageUserDirSetup = '(setq package-user-dir "{0}")' -f $packageUserDirForElisp
}

$repoForElisp = ($RepoRoot -replace '\\', '/') + '/'
$loadArguments = @('-L', $RepoRoot, '-L', (Join-Path $RepoRoot 'lisp'))
$packageDirectories = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'packages') -Directory -ErrorAction SilentlyContinue
foreach ($directory in $packageDirectories) {
    $loadArguments += @('-L', $directory.FullName)
}

try {
    $validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("org-seq-check-{0}" -f [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $validationRoot -Force
    $noteDirectories = @(
        '00_Roam',
        '00_Roam/daily',
        '00_Roam/capture',
        '00_Roam/dashboards',
        '10_Outputs',
        '20_Practice',
        '30_Library',
        '40_Archives'
    )
    foreach ($directory in $noteDirectories) {
        $null = New-Item -ItemType Directory -Path (Join-Path $validationRoot $directory) -Force
    }
    $childEnvironment = @{ ORG_SEQ_NOTE_HOME = $validationRoot }

    $version = Invoke-OrgSeqNative -FilePath $emacs -Arguments @(
        '--batch', '-Q', '--eval', '(princ emacs-major-version)'
    ) -Environment $childEnvironment
    $parsedVersion = 0
    if ($version.ExitCode -ne 0 -or
        -not [int]::TryParse($version.StdOut.Trim(), [ref]$parsedVersion) -or
        $parsedVersion -lt 30) {
        $failed.Add('Emacs 30+')
    }
    else {
        $passed.Add('Emacs 30+')
    }

    if (-not $SkipErt) {
        $ertFiles = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Filter 'test-*.el' -File |
            Sort-Object Name
        foreach ($testFile in $ertFiles) {
            $arguments = @('--batch', '-Q') + $loadArguments + @(
                '-l', $testFile.FullName,
                '-f', 'ert-run-tests-batch-and-exit'
            )
            $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments $arguments -Environment $childEnvironment
            Add-CheckResult -Name "ERT scripts/$($testFile.Name)" -Result $result
        }
    }

    if (-not $SkipCompile) {
        $files = @(
            (Join-Path $RepoRoot 'early-init.el'),
            (Join-Path $RepoRoot 'init.el')
        )
        $files += Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'lisp') -Filter '*.el' -File |
            ForEach-Object FullName
        $files += Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'packages') -Filter '*.el' -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object FullName

        $disableInstall = "(progn (require 'package) $packageUserDirSetup (package-initialize) (require 'use-package) (setq use-package-ensure-function #'ignore))"
        $arguments = @('--batch', '-Q') + $loadArguments + @(
            '--eval', $disableInstall,
            '-f', 'batch-byte-compile'
        ) + $files
        $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments $arguments -Environment $childEnvironment
        Add-CheckResult -Name 'Full byte compilation' -Result $result
        $cleanedByteCode += Remove-OrgSeqByteCode
    }

    if (-not $SkipStartup) {
        $startupAudit = @'
(progn
  (require 'json)
  (let* ((failed-modules
          (vconcat (mapcar #'symbol-name (my/init-failed-modules))))
         (doctor-issues
          (vconcat
           (mapcar
            (lambda (result)
              `((id . ,(symbol-name (plist-get result :id)))
                (status . ,(symbol-name (plist-get result :status)))
                (detail . ,(plist-get result :detail))))
            (seq-remove
             (lambda (result)
               (or (eq (plist-get result :status) 'pass)
                   (eq (plist-get result :id) 'module-loads)))
             (my/doctor-run)))))
         (keymap-issues
          (vconcat
           (mapcar
            (lambda (result)
              `((key . ,(plist-get result :key))
                (expected . ,(symbol-name (plist-get result :expected)))
                (actual . ,(format "%s" (plist-get result :actual)))
                (status . ,(symbol-name (plist-get result :status)))))
            (seq-remove
             (lambda (result)
               (eq (plist-get result :status) 'pass))
             (my/keymap-audit-results))))))
    (princ "\nORG_SEQ_AUDIT_BEGIN\n")
    (princ
     (json-encode
      `((modules . ,failed-modules)
        (doctor . ,doctor-issues)
        (keymap . ,keymap-issues)))))
    (princ "\nORG_SEQ_AUDIT_END\n")))
'@
        $arguments = @(
            '--batch', '-Q',
            '--eval', ('(setq user-emacs-directory "{0}")' -f $repoForElisp)
        )
        if ($packageUserDirSetup) {
            $arguments += @('--eval', $packageUserDirSetup)
        }
        $arguments += @(
            '-l', (Join-Path $RepoRoot 'init.el'),
            '--eval', $startupAudit
        )
        $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments $arguments -Environment $childEnvironment
        if ($result.ExitCode -eq 0) {
            $passed.Add('Batch startup')
            try {
                $auditMatch = [regex]::Match(
                    $result.StdOut,
                    '(?s)ORG_SEQ_AUDIT_BEGIN\r?\n(?<json>.*?)\r?\nORG_SEQ_AUDIT_END'
                )
                if (-not $auditMatch.Success) {
                    throw 'Startup audit markers were not found in Emacs stdout.'
                }
                $audit = $auditMatch.Groups['json'].Value | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                $failedModules = @($audit.modules | Where-Object { $_ })
                if ($failedModules.Count -eq 0) {
                    $passed.Add('Module load audit')
                }
                else {
                    $detail = "Failed modules: $($failedModules -join ', ')"
                    $warnings.Add("Module load audit: $detail")
                    if ($RequireAllModules) {
                        $failed.Add('Module load audit')
                    }
                }

                $doctorIssues = @($audit.doctor | Where-Object { $_ })
                if ($doctorIssues.Count -eq 0) {
                    $passed.Add('Dependency audit')
                }
                else {
                    $issueSummary = $doctorIssues |
                        ForEach-Object { '{0}:{1}' -f $_.status, $_.id }
                    $warnings.Add("Dependency audit: $($issueSummary -join ', ')")
                    $requiredFailures = @($doctorIssues | Where-Object { $_.status -eq 'fail' })
                    if ($RequireDependencies -and $requiredFailures.Count -gt 0) {
                        $failed.Add('Dependency audit')
                    }
                }

                $keymapIssues = @($audit.keymap | Where-Object { $_ })
                if ($keymapIssues.Count -eq 0) {
                    $passed.Add('Keymap audit')
                }
                else {
                    $keymapSummary = $keymapIssues |
                        ForEach-Object { '{0}:{1}' -f $_.key, $_.actual }
                    $warnings.Add("Keymap audit: $($keymapSummary -join ', ')")
                    if ($RequireAllModules) {
                        $failed.Add('Keymap audit')
                    }
                }
            }
            catch {
                $failed.Add('Startup audit serialization')
                $warnings.Add("Startup audit serialization: $($_.Exception.Message)")
            }
        }
        else {
            Add-CheckResult -Name 'Batch startup' -Result $result
        }
    }
}
catch {
    $failed.Add('Validation runner')
    $warnings.Add($_.Exception.Message)
}
finally {
    $cleanedByteCode += Remove-OrgSeqByteCode

    if ($validationRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedValidation = [System.IO.Path]::GetFullPath($validationRoot)
        if ($resolvedValidation.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedValidation -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            $warnings.Add("Refused to remove validation path outside the temp root: $resolvedValidation")
        }
    }
}

$remainingByteCode = Get-ChildItem -LiteralPath $RepoRoot -Filter '*.elc' -File -Recurse -ErrorAction SilentlyContinue
if ($remainingByteCode) {
    $failed.Add('Bytecode cleanup')
    $warnings.Add("Generated bytecode remains: $($remainingByteCode.Count) file(s)")
}

$summary = [pscustomobject]@{
    Passed = $passed.ToArray()
    Failed = $failed.ToArray()
    Warnings = $warnings.ToArray()
    CleanedByteCode = $cleanedByteCode
    EmacsPath = $emacs
    PackageUserDir = $resolvedPackageUserDir
}
$summary

if ($failed.Count -gt 0) {
    exit 1
}
exit 0
