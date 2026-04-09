# bootstrap-notes.ps1 --- Create NoteHQ directory structure and flatten legacy Roam subdirs
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$NoteHome = Join-Path $HOME "NoteHQ"

Write-Host "=== org-seq: Bootstrap NoteHQ Directory Structure ===" -ForegroundColor Cyan
Write-Host ""

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

# --- Copy Claude Code support files (CLAUDE.md + skills) ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkeletonDir = Join-Path (Split-Path -Parent $ScriptDir) "notehq"

if (Test-Path $SkeletonDir) {
    Write-Host "  Installing Claude Code support files..."

    # CLAUDE.md
    $claudeMd = Join-Path $NoteHome "CLAUDE.md"
    if (-not (Test-Path $claudeMd)) {
        Copy-Item (Join-Path $SkeletonDir "CLAUDE.md") $claudeMd
        Write-Host "  [ok] CLAUDE.md"
    } else {
        Write-Host "  [skip] CLAUDE.md (already exists)"
    }

    # .claude/skills/
    $skillsDst = Join-Path $NoteHome ".claude\skills"
    New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
    $skillsSrc = Join-Path $SkeletonDir ".claude\skills"
    if (Test-Path $skillsSrc) {
        Get-ChildItem -Path $skillsSrc -Filter "*.md" | ForEach-Object {
            $dest = Join-Path $skillsDst $_.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $_.FullName $dest
                Write-Host "  [ok] .claude/skills/$($_.Name)"
            } else {
                Write-Host "  [skip] .claude/skills/$($_.Name) (already exists)"
            }
        }
    }
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "  1. Deploy config:  cd org-seq; .\deploy.ps1   (or deploy.sh on Linux/macOS)"
Write-Host "  2. Start Emacs and run:  M-x org-roam-db-sync"
Write-Host "  3. Run:  M-x supertag-sync-full-initialize"
Write-Host "  4. Use Claude Code inside ~/NoteHQ/ — it now has CLAUDE.md and skills"
Write-Host ""
Write-Host "Done."
