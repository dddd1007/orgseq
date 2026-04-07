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

function Write-Status($icon, $msg) { Write-Host "  $icon $msg" }
function Write-Pass($msg) { Write-Status "✓" $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Status "⚠" $msg -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Status "✗" $msg -ForegroundColor Red }
function Write-Section($msg) { Write-Host "`n── $msg ──" -ForegroundColor Cyan }

# ── Prerequisites ──

function Test-Prerequisites {
    Write-Section "Checking prerequisites"
    $allOk = $true

    # Emacs
    $emacs = Get-Command emacs -ErrorAction SilentlyContinue
    if ($emacs) {
        $ver = & emacs --version 2>&1 | Select-Object -First 1
        if ($ver -match "(\d+)\.") {
            $major = [int]$Matches[1]
            if ($major -ge 29) { Write-Pass "Emacs $major ($ver)" }
            else { Write-Warn "Emacs $major found, 29+ required"; $allOk = $false }
        }
        else { Write-Warn "Cannot parse Emacs version: $ver" }
    }
    else { Write-Fail "Emacs not found. Install from https://ftp.gnu.org/gnu/emacs/windows/ or MSYS2"; $allOk = $false }

    # SQLite
    if ($emacs) {
        $sqlite = & emacs --batch --eval '(message "%s" (sqlite-available-p))' 2>&1 | Select-String -Pattern "^(t|nil)$"
        if ($sqlite -and $sqlite.ToString().Trim() -eq "t") { Write-Pass "SQLite support available" }
        else { Write-Fail "SQLite not available. org-roam requires Emacs 29+ with SQLite."; $allOk = $false }
    }

    # Native-comp (optional)
    if ($emacs) {
        $nc = & emacs --batch --eval '(message "%s" (native-comp-available-p))' 2>&1 | Select-String -Pattern "^(t|nil)$"
        if ($nc -and $nc.ToString().Trim() -eq "t") { Write-Pass "Native-comp available" }
        else { Write-Warn "Native-comp not available. Consider MSYS2 build for better performance." }
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

    # Restore custom.el if it was in the target before
    $backups = Get-ChildItem "$Target.backup-*" -Directory -ErrorAction SilentlyContinue | Sort-Object -Descending | Select-Object -First 1
    if ($backups -and (Test-Path "$($backups.FullName)/custom.el") -and (-not (Test-Path "$Target/custom.el"))) {
        Copy-Item "$($backups.FullName)/custom.el" "$Target/custom.el"
        Write-Pass "custom.el restored from backup"
    }
}

# ── Verify ──

function Test-Deployment {
    Write-Section "Verifying deployment"

    $elFiles = Get-ChildItem "$Target/lisp/*.el" | ForEach-Object { $_.FullName }
    $allFiles = @("$Target/early-init.el", "$Target/init.el") + $elFiles

    $emacs = Get-Command emacs -ErrorAction SilentlyContinue
    if (-not $emacs) {
        Write-Warn "Emacs not found, skipping byte-compile check"
        return
    }

    $lispDir = Join-Path $Target "lisp"
    $args = @("--batch", "-Q", "-L", $Target, "-L", $lispDir, "-f", "batch-byte-compile") + $allFiles

    try {
        $output = & emacs @args 2>&1
        $errors = $output | Where-Object { $_ -match "Error|error" }
        if ($errors) {
            Write-Warn "Byte-compile warnings:"
            $errors | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        }
        else {
            Write-Pass "All files byte-compile cleanly"
        }
    }
    catch {
        Write-Warn "Byte-compile check failed: $_"
    }

    # Clean up .elc files from target (we only wanted the check)
    Get-ChildItem $Target -Recurse -Filter "*.elc" | Remove-Item -Force -ErrorAction SilentlyContinue
}

# ── Summary ──

function Write-PostInstall {
    Write-Section "Deployment complete"
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "    1. Launch Emacs — packages auto-install on first run (needs internet)"
    Write-Host "    2. Run:  M-x nerd-icons-install-fonts"
    Write-Host "       Then right-click downloaded .ttf files → Install (Windows)"
    Write-Host "    3. org-roam vault at ~/org-roam/ is auto-created on first launch"
    Write-Host "    4. Point Obsidian at ~/org-roam/ to use it as reading client"
    Write-Host ""
    Write-Host "  Key bindings:  SPC → leader menu  |  SPC n a → task dashboard" -ForegroundColor DarkGray
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
