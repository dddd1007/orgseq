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

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "  1. Deploy config:  cd org-seq; .\deploy.ps1   (or deploy.sh on Linux/macOS)"
Write-Host "  2. Start Emacs and run:  M-x org-roam-db-sync"
Write-Host "  3. If using org-supertag:  M-x supertag-sync-full-initialize"
Write-Host "  4. Edit ~/NoteHQ/Roam/concepts/purpose.org and schema.org for AI context"
Write-Host ""
Write-Host "Done."
