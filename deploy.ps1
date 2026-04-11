#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy org-seq Emacs configuration to ~/.emacs.d/
.DESCRIPTION
    Checks prerequisites, backs up existing config, copies files,
    runs byte-compile verification, and prints post-install steps.
.PARAMETER Target
    Target Emacs directory. Defaults to $HOME/.emacs.d
.PARAMETER SkipChecks
    Skip prerequisite checks.
.PARAMETER Force
    Overwrite without backup prompt.
#>
param(
    [string]$Target = "$HOME/.emacs.d",
    [switch]$SkipChecks,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Pass($msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Section($msg) { Write-Host "`n── $msg ──" -ForegroundColor Cyan }

# ── Prerequisites ──

# Find Emacs executable: PATH first, then common Windows install locations.
function Find-Emacs {
    $cmd = Get-Command emacs -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Scan Program Files for official GNU Emacs installs
    $roots = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA\Programs")
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $candidates = Get-ChildItem "$root\Emacs" -Directory -ErrorAction SilentlyContinue |
                      Sort-Object Name -Descending
        foreach ($dir in $candidates) {
            $bin = Join-Path $dir.FullName "bin\emacs.exe"
            if (Test-Path $bin) { return $bin }
        }
    }
    return $null
}

function Test-Prerequisites {
    Write-Section "Checking prerequisites"
    $allOk = $true

    # Emacs
    $emacsPath = Find-Emacs
    if ($emacsPath) {
        $ver = & $emacsPath --version 2>&1 | Select-Object -First 1
        if ($ver -match "(\d+)\.") {
            $major = [int]$Matches[1]
            if ($major -ge 30) { Write-Pass "Emacs $major ($ver)" }
            else { Write-Warn "Emacs $major found, 30+ required"; $allOk = $false }
        }
        else { Write-Warn "Cannot parse Emacs version: $ver" }
        # Store for later use
        $script:EmacsExe = $emacsPath
    }
    else { Write-Fail "Emacs not found. Install from https://ftp.gnu.org/gnu/emacs/windows/"; $allOk = $false }

    # SQLite
    if ($emacsPath) {
        $sqliteExpr = '(princ (if (sqlite-available-p) "t" "nil"))'
        $sqlite = (& $emacsPath --batch --eval $sqliteExpr 2>&1 | Select-Object -Last 1).ToString().Trim()
        if ($sqlite -eq "t") { Write-Pass "SQLite support available" }
        else { Write-Fail "SQLite not available. org-roam requires Emacs 30+ with SQLite."; $allOk = $false }
    }

    # Native-comp (optional)
    if ($emacsPath) {
        $ncExpr = '(princ (if (native-comp-available-p) "t" "nil"))'
        $nc = (& $emacsPath --batch --eval $ncExpr 2>&1 | Select-Object -Last 1).ToString().Trim()
        if ($nc -eq "t") { Write-Pass "Native-comp available" }
        else { Write-Warn "Native-comp not available (optional -- official Windows build omits libgccjit)." }
    }

    # ripgrep
    if (Get-Command rg -ErrorAction SilentlyContinue) { Write-Pass "ripgrep (rg) found" }
    else { Write-Warn "ripgrep not found. Install: winget install BurntSushi.ripgrep.MSVC" }

    # fd
    if (Get-Command fd -ErrorAction SilentlyContinue) { Write-Pass "fd found" }
    else { Write-Warn "fd not found. Install: winget install sharkdp.fd" }

    # git
    if (Get-Command git -ErrorAction SilentlyContinue) { Write-Pass "git found" }
    else { Write-Warn "git not found. Magit requires git." }

    # pandoc (optional)
    if (Get-Command pandoc -ErrorAction SilentlyContinue) { Write-Pass "pandoc found (markdown export)" }
    else { Write-Warn "pandoc not found. Markdown export will use basic processor." }

    # HOME
    if ($env:HOME) { Write-Pass "HOME = $env:HOME" }
    else { Write-Warn "HOME not set. Emacs may resolve ~ incorrectly on Windows." }

    if (-not $allOk) {
        Write-Host ""
        Write-Fail "Required dependencies missing. Fix the issues above before deploying."
        if (-not $Force) { exit 1 }
    }
}

# ── Backup ──

function Backup-ExistingConfig {
    if (-not (Test-Path $Target)) { return }

    $hasContent = (Get-ChildItem $Target -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    if (-not $hasContent) { return }

    Write-Section "Existing config detected"
    Write-Host "  Target: $Target"

    if (-not $Force) {
        $answer = Read-Host "  Back up existing config before overwriting? [Y/n]"
        if ($answer -eq "n" -or $answer -eq "N") {
            $skip = Read-Host "  Continue WITHOUT backup? This will overwrite files. [y/N]"
            if ($skip -ne "y" -and $skip -ne "Y") {
                Write-Host "  Aborted." -ForegroundColor Yellow
                exit 0
            }
            return
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = "$Target.backup-$timestamp"
    Write-Host "  Backing up to: $backupDir"
    Copy-Item -Recurse -Force $Target $backupDir

    # Preserve custom.el in target (user's Customize settings)
    if (Test-Path "$backupDir/custom.el") {
        Write-Pass "custom.el preserved in backup"
    }
    Write-Pass "Backup complete"
}

# ── Deploy ──

function Deploy-Config {
    Write-Section "Deploying org-seq to $Target"

    New-Item -ItemType Directory -Force $Target | Out-Null

    $filesToCopy = @("early-init.el", "init.el")
    foreach ($f in $filesToCopy) {
        $src = Join-Path $ScriptDir $f
        if (-not (Test-Path $src)) { Write-Fail "Missing source: $src"; exit 1 }
        Copy-Item -Force $src $Target
        Write-Pass $f
    }

    $lispSrc = Join-Path $ScriptDir "lisp"
    $lispDst = Join-Path $Target "lisp"
    if (Test-Path $lispDst) { Remove-Item -Recurse -Force $lispDst }
    Copy-Item -Recurse -Force $lispSrc $lispDst
    $moduleCount = (Get-ChildItem "$lispDst/*.el" | Measure-Object).Count
    Write-Pass "lisp/ ($moduleCount modules)"

    # Bundled subprojects live under packages/ (currently just
    # org-focus-timer).  Copy the whole tree so init-focus.el can find
    # it via user-emacs-directory.
    $pkgSrc = Join-Path $ScriptDir "packages"
    $pkgDst = Join-Path $Target "packages"
    if (Test-Path $pkgSrc) {
        if (Test-Path $pkgDst) { Remove-Item -Recurse -Force $pkgDst }
        Copy-Item -Recurse -Force $pkgSrc $pkgDst
        $pkgCount = (Get-ChildItem "$pkgDst" -Recurse -Filter "*.el" | Measure-Object).Count
        Write-Pass "packages/ ($pkgCount elisp files)"
    }

    # Restore custom.el if it was in the target before
    $backups = Get-ChildItem "$Target.backup-*" -Directory -ErrorAction SilentlyContinue | Sort-Object -Descending | Select-Object -First 1
    if ($backups -and (Test-Path "$($backups.FullName)/custom.el") -and (-not (Test-Path "$Target/custom.el"))) {
        Copy-Item "$($backups.FullName)/custom.el" "$Target/custom.el"
        Write-Pass "custom.el restored from backup"
    }

    $version = "unknown"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $gitVersion = (& git -C $ScriptDir rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
            if ($gitVersion) { $version = $gitVersion }
        }
        catch {
            $version = "unknown"
        }
    }
    Set-Content -Path (Join-Path $Target ".org-seq-version") -Value $version -NoNewline
    Write-Pass ".org-seq-version ($version)"
}

# ── Verify ──

function Test-Deployment {
    Write-Section "Verifying deployment"

    $elFiles = Get-ChildItem "$Target/lisp/*.el" | ForEach-Object { $_.FullName }
    $pkgFiles = @()
    $extraLoadPaths = @()
    if (Test-Path "$Target/packages") {
        $extraLoadPaths += Get-ChildItem "$Target/packages" -Directory | ForEach-Object { $_.FullName }
        $pkgFiles = Get-ChildItem "$Target/packages" -Recurse -Filter "*.el" |
                    ForEach-Object { $_.FullName }
    }
    if (Test-Path "$Target/elpa") {
        $extraLoadPaths += Get-ChildItem "$Target/elpa" -Directory |
                           Where-Object { $_.Name -notmatch '^archives$' } |
                           ForEach-Object { $_.FullName }
    }
    $allFiles = @("$Target/early-init.el", "$Target/init.el") + $elFiles + $pkgFiles

    $emacs = if ($script:EmacsExe) { $script:EmacsExe } else { Find-Emacs }
    if (-not $emacs) {
        Write-Warn "Emacs not found, skipping byte-compile check"
        return
    }

    $lispDir = Join-Path $Target "lisp"
    $targetForElisp = $Target.Replace('\', '/')
    $packageInitFile = Join-Path $env:TEMP "org-seq-deploy-package-init.el"
    @"
(setq user-emacs-directory "$targetForElisp/")
(require 'package)
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory))
(package-initialize)
"@ | Set-Content -Path $packageInitFile -Encoding UTF8
    $emacsArgs = @("--batch", "-Q", "-L", $Target, "-L", $lispDir)
    foreach ($loadPath in $extraLoadPaths) {
        $emacsArgs += @("-L", $loadPath)
    }
    $emacsArgs += @("-l", $packageInitFile, "-f", "batch-byte-compile") + $allFiles

    try {
        $output = & $emacs @emacsArgs 2>&1
        $compileExitCode = $LASTEXITCODE
        $warnings = $output | Where-Object { $_ -match "Warning|warning" }
        if ($compileExitCode -ne 0) {
            Write-Warn "Byte-compile check failed (exit code $compileExitCode)"
            if ($output) {
                $output | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
            }
        }
        elseif ($warnings) {
            Write-Warn "Byte-compile warnings:"
            $warnings | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        }
        else {
            Write-Pass "All files byte-compile cleanly"
        }
    }
    catch {
        Write-Warn "Byte-compile check failed: $_"
    }
    finally {
        if (Test-Path $packageInitFile) {
            Remove-Item $packageInitFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Clean up .elc files from target (we only wanted the check)
    Get-ChildItem $Target -Recurse -Filter "*.elc" | Remove-Item -Force -ErrorAction SilentlyContinue
}

# ── Summary ──

function Write-PostInstall {
    Write-Section "Deployment complete"
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "    1. Run:  .\scripts\bootstrap-notes.ps1  (creates ~/NoteHQ/ directory structure)"
    Write-Host "    2. Launch Emacs — packages auto-install on first run (needs internet)"
    Write-Host "    3. Run:  M-x nerd-icons-install-fonts"
    Write-Host "       Then right-click downloaded .ttf files → Install (Windows)"
    Write-Host "    4. Run:  M-x supertag-sync-full-initialize  (first-time supertag index)"
    Write-Host "    5. Optional: Point Obsidian at ~/NoteHQ/ as reading client"
    Write-Host ""
    Write-Host "  Key bindings:" -ForegroundColor DarkGray
    Write-Host "    SPC         → leader menu         SPC a d  → GTD dashboard" -ForegroundColor DarkGray
    Write-Host "    SPC n c     → new note            SPC n m  → extend (templates/schema)" -ForegroundColor DarkGray
    Write-Host "    SPC P o/p/l → PARA navigation     SPC n v  → dashboards" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Main ──

Write-Host "org-seq deploy" -ForegroundColor White
Write-Host "Source: $ScriptDir"
Write-Host "Target: $Target"

if (-not $SkipChecks) { Test-Prerequisites }
Backup-ExistingConfig
Deploy-Config
Test-Deployment
Write-PostInstall
