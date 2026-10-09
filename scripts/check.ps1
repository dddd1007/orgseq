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

    [switch]$RequireDependencies,

    [switch]$RequireNoWarnings
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$passed = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$cleanedByteCode = 0
$compileWarningCount = 0
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

function Get-OrgSeqElispFiles {
    [CmdletBinding()]
    param()

    $files = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $RepoRoot -Filter '*.el' -File |
        ForEach-Object { $files.Add($_.FullName) }
    foreach ($directory in @('lisp', 'packages')) {
        $path = Join-Path $RepoRoot $directory
        if (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -Filter '*.el' -File -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object { $files.Add($_.FullName) }
        }
    }
    return $files.ToArray()
}

function Get-OrgSeqByteCode {
    [CmdletBinding()]
    param()

    foreach ($source in Get-OrgSeqElispFiles) {
        $compiled = "$source`c"
        if (Test-Path -LiteralPath $compiled -PathType Leaf) {
            Get-Item -LiteralPath $compiled
        }
    }
}

function Get-OrgSeqCompileWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Result
    )

    # Byte compilation succeeds (exit code 0) even when it emits warnings, so
    # the runner has to read the output itself.  Only warnings attributed to a
    # source file inside the repository are reported; warnings raised by
    # third-party packages on the load path are not org-seq's to fix.
    $comparison = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $prefix = $RepoRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $lines = @($Result.StdErr, $Result.StdOut) |
        Where-Object { $_ } |
        ForEach-Object { $_ -split '\r?\n' }

    foreach ($line in $lines) {
        $match = [regex]::Match(
            $line,
            '^(?<path>.+?\.el):(?<position>\d+:\d+:)?\s+Warning:\s+(?<message>.+)$')
        if (-not $match.Success) {
            continue
        }

        $full = $null
        try {
            $full = [System.IO.Path]::GetFullPath($match.Groups['path'].Value)
        }
        catch {
            continue
        }
        if (-not $full.StartsWith($prefix, $comparison)) {
            continue
        }

        $relative = $full.Substring($prefix.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) -replace '\\', '/'
        $position = $match.Groups['position'].Value.TrimEnd(':')
        if ($position) {
            '{0}:{1}: {2}' -f $relative, $position, $match.Groups['message'].Value
        }
        else {
            '{0}: {1}' -f $relative, $match.Groups['message'].Value
        }
    }
}

function Remove-OrgSeqByteCode {
    [CmdletBinding()]
    param()

    $removed = 0
    $byteCode = @(Get-OrgSeqByteCode)
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
        $pwsh = (Get-Process -Id $PID -ErrorAction Stop).Path
        $powerShellTests = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Filter 'test-*.ps1' -File |
            Sort-Object Name
        foreach ($testFile in $powerShellTests) {
            $result = Invoke-OrgSeqNative -FilePath $pwsh -Arguments @(
                '-NoLogo', '-NoProfile', '-File', $testFile.FullName
            ) -Environment $childEnvironment
            Add-CheckResult -Name "PowerShell scripts/$($testFile.Name)" -Result $result
        }

        $ertFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Filter 'test-*.el' -File
            Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'packages') -Filter 'test-*.el' -File -Recurse -ErrorAction SilentlyContinue
        ) | Sort-Object FullName
        foreach ($testFile in $ertFiles) {
            $arguments = @('--batch', '-Q') + $loadArguments + @(
                '-l', $testFile.FullName,
                '-f', 'ert-run-tests-batch-and-exit'
            )
            $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments $arguments -Environment $childEnvironment
            $relativeTest = [System.IO.Path]::GetRelativePath(
                $RepoRoot,
                $testFile.FullName
            ).Replace('\\', '/')
            Add-CheckResult -Name "ERT $relativeTest" -Result $result
        }
    }

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

    # An unbalanced form still byte-compiles into a truncated file, so check
    # delimiter balance explicitly before anything else reads the sources.
    $balanceProbe = @'
(let ((unbalanced 0))
  (dolist (file command-line-args-left)
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (condition-case err
          (check-parens)
        (error
         (setq unbalanced (1+ unbalanced))
         (princ (format "%s: %s\n" file (error-message-string err)))))))
  (setq command-line-args-left nil)
  (kill-emacs (if (> unbalanced 0) 1 0)))
'@
    $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments (
        @('--batch', '-Q', '--eval', $balanceProbe) + @(Get-OrgSeqElispFiles)
    ) -Environment $childEnvironment
    Add-CheckResult -Name 'Delimiter balance' -Result $result

    if (-not $SkipCompile) {
        $files = @(Get-OrgSeqElispFiles)

        # `batch-byte-compile' writes each .elc next to its source.  Redirecting
        # the output into the disposable validation root keeps a check run from
        # mutating the working tree and lets two runs (for example Emacs 30 and
        # Emacs 31) execute against the same checkout without racing.
        $compileOutput = Join-Path $validationRoot 'bytecode'
        $null = New-Item -ItemType Directory -Path $compileOutput -Force
        $compileOutputForElisp = ($compileOutput -replace '\\', '/') + '/'
        $redirectOutput =
            '(setq byte-compile-dest-file-function (lambda (source) (expand-file-name (concat (file-name-nondirectory source) "c") "{0}")))' -f
                $compileOutputForElisp

        $disableInstall = "(progn (require 'package) $packageUserDirSetup (package-initialize) (require 'use-package) (setq use-package-ensure-function #'ignore))"
        $arguments = @('--batch', '-Q') + $loadArguments + @(
            '--eval', $disableInstall,
            '--eval', $redirectOutput,
            '-f', 'batch-byte-compile'
        ) + $files
        $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments $arguments -Environment $childEnvironment
        Add-CheckResult -Name 'Full byte compilation' -Result $result

        $compileWarnings = @(Get-OrgSeqCompileWarning -Result $result)
        $compileWarningCount = $compileWarnings.Count
        if ($compileWarningCount -gt 0) {
            if ($RequireNoWarnings) {
                $failed.Add('Byte compilation warnings')
            }
            foreach ($compileWarning in $compileWarnings) {
                $warnings.Add("Byte compilation: $compileWarning")
            }
        }
        else {
            $passed.Add('Byte compilation warnings')
        }

        $cleanedByteCode += Remove-OrgSeqByteCode

        if (-not $SkipStartup) {
            # Deployment byte-compiles the target, so the compiled tree is what
            # users actually run.  Source-only auditing cannot see a module
            # whose behavior differs once compiled -- a macro defined at load
            # time, for example, compiles into a plain function call and takes
            # its whole `use-package' :config block down at startup.  Stage a
            # throwaway copy, compile it in place, and audit that.
            $staged = Join-Path $validationRoot 'staged'
            $null = New-Item -ItemType Directory -Path $staged -Force
            foreach ($entry in @('early-init.el', 'init.el')) {
                Copy-Item -LiteralPath (Join-Path $RepoRoot $entry) -Destination $staged -Force
            }
            foreach ($entry in @('lisp', 'packages')) {
                $source = Join-Path $RepoRoot $entry
                if (Test-Path -LiteralPath $source -PathType Container) {
                    Copy-Item -LiteralPath $source -Destination $staged -Recurse -Force
                }
            }
            Get-ChildItem -LiteralPath $staged -Filter '*.elc' -File -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue

            $stagedFiles = @(
                Get-ChildItem -LiteralPath $staged -Filter '*.el' -File |
                    ForEach-Object { $_.FullName }
                Get-ChildItem -LiteralPath (Join-Path $staged 'lisp') -Filter '*.el' -File -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.FullName }
                Get-ChildItem -LiteralPath (Join-Path $staged 'packages') -Filter '*.el' -File -Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.FullName }
            )
            $stagedLoad = @('-L', $staged, '-L', (Join-Path $staged 'lisp'))
            foreach ($directory in (Get-ChildItem -LiteralPath (Join-Path $staged 'packages') -Directory -ErrorAction SilentlyContinue)) {
                $stagedLoad += @('-L', $directory.FullName)
            }

            $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments (
                @('--batch', '-Q') + $stagedLoad + @(
                    '--eval', $disableInstall,
                    '-f', 'batch-byte-compile'
                ) + $stagedFiles
            ) -Environment $childEnvironment
            Add-CheckResult -Name 'Staged byte compilation' -Result $result

            $stagedForElisp = ($staged -replace '\\', '/') + '/'
            $arguments = @(
                '--batch', '-Q',
                '--eval', ('(setq user-emacs-directory "{0}")' -f $stagedForElisp)
            )
            if ($packageUserDirSetup) {
                $arguments += @('--eval', $packageUserDirSetup)
            }
            $arguments += @(
                '-l', (Join-Path $staged 'init.elc'),
                '--eval', $startupAudit
            )
            $result = Invoke-OrgSeqNative -FilePath $emacs -Arguments $arguments -Environment $childEnvironment
            if ($result.ExitCode -ne 0) {
                Add-CheckResult -Name 'Compiled startup' -Result $result
            }
            else {
                $passed.Add('Compiled startup')
                $auditMatch = [regex]::Match(
                    $result.StdOut,
                    '(?s)ORG_SEQ_AUDIT_BEGIN\r?\n(?<json>.*?)\r?\nORG_SEQ_AUDIT_END')
                if (-not $auditMatch.Success) {
                    $failed.Add('Compiled startup audit')
                    $warnings.Add('Compiled startup audit: markers were not found in Emacs stdout.')
                }
                else {
                    $compiledAudit = $auditMatch.Groups['json'].Value |
                        ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    $compiledModules = @($compiledAudit.modules | Where-Object { $_ })
                    if ($compiledModules.Count -eq 0) {
                        $passed.Add('Compiled module load audit')
                    }
                    else {
                        $warnings.Add("Compiled module load audit: $($compiledModules -join ', ')")
                        if ($RequireAllModules) {
                            $failed.Add('Compiled module load audit')
                        }
                    }

                    $compiledKeymap = @($compiledAudit.keymap | Where-Object { $_ })
                    if ($compiledKeymap.Count -eq 0) {
                        $passed.Add('Compiled keymap audit')
                    }
                    else {
                        $compiledSummary = $compiledKeymap |
                            ForEach-Object { '{0}:{1}' -f $_.key, $_.actual }
                        $warnings.Add("Compiled keymap audit: $($compiledSummary -join ', ')")
                        if ($RequireAllModules) {
                            $failed.Add('Compiled keymap audit')
                        }
                    }
                }
            }
        }
    }

    if (-not $SkipStartup) {
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

$remainingByteCode = @(Get-OrgSeqByteCode)
if ($remainingByteCode) {
    $failed.Add('Bytecode cleanup')
    $warnings.Add("Generated bytecode remains: $($remainingByteCode.Count) file(s)")
}

$summary = [pscustomobject]@{
    Passed = $passed.ToArray()
    Failed = $failed.ToArray()
    Warnings = $warnings.ToArray()
    CleanedByteCode = $cleanedByteCode
    CompileWarnings = $compileWarningCount
    EmacsPath = $emacs
    PackageUserDir = $resolvedPackageUserDir
}
$summary

if ($failed.Count -gt 0) {
    exit 1
}
exit 0
