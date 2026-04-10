# bootstrap-notes.ps1 --- Create NoteHQ directory structure and flatten legacy Roam subdirs
#
# Usage:
#   .\bootstrap-notes.ps1            First-time setup. Existing files are skipped.
#   .\bootstrap-notes.ps1 -Update    Overwrite Claude Code support files (CLAUDE.md,
#                                    .claude/rules/*, .claude/skills/*) with the latest
#                                    versions from the org-seq repo. Notes, schema,
#                                    capture templates, and ai-config are never touched.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Update
)
$ErrorActionPreference = "Stop"

$NoteHome = Join-Path $HOME "NoteHQ"

Write-Host "=== org-seq: Bootstrap NoteHQ Directory Structure ===" -ForegroundColor Cyan
if ($Update) {
    Write-Host "    Mode: UPDATE - Claude Code scaffolding will be overwritten" -ForegroundColor Yellow
}
Write-Host ""

# --- Helper: deploy a file with skip / update / create semantics ---
function Deploy-File {
    param(
        [Parameter(Mandatory)] [string]$Src,
        [Parameter(Mandatory)] [string]$Dest,
        [Parameter(Mandatory)] [string]$Label
    )
    if (-not (Test-Path $Src)) {
        Write-Host "  [missing] $Label (source not found: $Src)"
        return
    }
    if (Test-Path $Dest) {
        if ($Update) {
            $srcHash = (Get-FileHash $Src -Algorithm SHA1).Hash
            $dstHash = (Get-FileHash $Dest -Algorithm SHA1).Hash
            if ($srcHash -eq $dstHash) {
                Write-Host "  [unchanged] $Label"
            } else {
                Copy-Item -Force $Src $Dest
                Write-Host "  [updated] $Label"
            }
        } else {
            Write-Host "  [skip]    $Label (already exists; use -Update to overwrite)"
        }
    } else {
        Copy-Item $Src $Dest
        Write-Host "  [created] $Label"
    }
}

# --- Create directory tree ---
$dirs = @(
    "$NoteHome\Roam\daily"
    "$NoteHome\Roam\capture"
    "$NoteHome\Roam\dashboards"
    "$NoteHome\Outputs\_template"
    "$NoteHome\Practice\_template"
    "$NoteHome\Library\bibliography"
    "$NoteHome\Library\datasets"
    "$NoteHome\Library\snippets"
    "$NoteHome\Library\references"
    "$NoteHome\Library\pdfs"
    "$NoteHome\Archives"
    "$NoteHome\.orgseq"
)

foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Write-Host "  [ok] $d"
}

Write-Host ""

# --- Flatten legacy Roam subdirectories (lit/, concepts/) ---
$legacyDirs = @("lit", "concepts")

foreach ($sub in $legacyDirs) {
    $src = Join-Path $NoteHome "Roam\$sub"
    if (Test-Path $src -PathType Container) {
        $orgFiles = Get-ChildItem -Path $src -Filter "*.org" -File
        if ($orgFiles.Count -gt 0) {
            Write-Host "  Flattening $src\ -> Roam\ ..."
            foreach ($f in $orgFiles) {
                $dest = Join-Path $NoteHome "Roam\$($f.Name)"
                if (Test-Path $dest) {
                    Write-Host "    [skip] $($f.Name) (already exists in Roam\)"
                } else {
                    Move-Item -Path $f.FullName -Destination $dest
                    Write-Host "    [moved] $($f.Name)"
                }
            }
        }
        # Remove subdirectory if now empty
        $remaining = Get-ChildItem -Path $src -Force
        if ($remaining.Count -eq 0) {
            Remove-Item -Path $src
            Write-Host "  [removed] empty directory $sub\"
        } else {
            Write-Host "  [kept] $sub\ (still has non-org files)"
        }
    }
}

# --- Copy Claude Code support files (CLAUDE.md + skills + rules) ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkeletonDir = Join-Path (Split-Path -Parent $ScriptDir) "notehq"

if (Test-Path $SkeletonDir) {
    Write-Host "  Installing Claude Code support files..."

    Deploy-File -Src (Join-Path $SkeletonDir "CLAUDE.md") `
                -Dest (Join-Path $NoteHome "CLAUDE.md") `
                -Label "CLAUDE.md"

    $skillsDst = Join-Path $NoteHome ".claude\skills"
    New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
    $skillsSrc = Join-Path $SkeletonDir ".claude\skills"
    if (Test-Path $skillsSrc) {
        Get-ChildItem -Path $skillsSrc -Filter "*.md" | ForEach-Object {
            Deploy-File -Src $_.FullName `
                        -Dest (Join-Path $skillsDst $_.Name) `
                        -Label ".claude/skills/$($_.Name)"
        }
    }

    $rulesDst = Join-Path $NoteHome ".claude\rules"
    New-Item -ItemType Directory -Force -Path $rulesDst | Out-Null
    $rulesSrc = Join-Path $SkeletonDir ".claude\rules"
    if (Test-Path $rulesSrc) {
        Get-ChildItem -Path $rulesSrc -Filter "*.md" | ForEach-Object {
            Deploy-File -Src $_.FullName `
                        -Dest (Join-Path $rulesDst $_.Name) `
                        -Label ".claude/rules/$($_.Name)"
        }
    }
}

Write-Host ""
if ($Update) {
    Write-Host "=== Update complete ===" -ForegroundColor Cyan
    Write-Host "  Re-pull org-seq and run '.\bootstrap-notes.ps1 -Update' anytime to refresh the scaffolding."
} else {
    Write-Host "=== Next Steps ===" -ForegroundColor Cyan
    Write-Host "  1. Deploy config:  cd org-seq; .\deploy.ps1   (or deploy.sh on Linux/macOS)"
    Write-Host "  2. Start Emacs and run:  M-x org-roam-db-sync"
    Write-Host "  3. Run:  M-x supertag-sync-full-initialize"
    Write-Host "  4. Use Claude Code inside ~/NoteHQ/ — it now has CLAUDE.md and skills"
    Write-Host ""
    Write-Host "  Refresh scaffolding later:  .\bootstrap-notes.ps1 -Update"
}
Write-Host ""
Write-Host "Done."
