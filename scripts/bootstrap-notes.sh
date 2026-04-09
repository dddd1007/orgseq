#!/usr/bin/env bash
# bootstrap-notes.sh --- Create NoteHQ directory structure and flatten legacy Roam subdirs
set -e
shopt -s nullglob

NOTE_HOME="$HOME/NoteHQ"

echo "=== org-seq: Bootstrap NoteHQ Directory Structure ==="
echo ""

# --- Create directory tree ---
dirs=(
  "$NOTE_HOME/Roam/daily"
  "$NOTE_HOME/Roam/capture"
  "$NOTE_HOME/Roam/dashboards"
  "$NOTE_HOME/Outputs/_template"
  "$NOTE_HOME/Practice/_template"
  "$NOTE_HOME/Library/bibliography"
  "$NOTE_HOME/Library/datasets"
  "$NOTE_HOME/Library/snippets"
  "$NOTE_HOME/Library/references"
  "$NOTE_HOME/Library/pdfs"
  "$NOTE_HOME/Archives"
  "$NOTE_HOME/.orgseq"
)

for d in "${dirs[@]}"; do
  mkdir -p "$d"
  echo "  [ok] $d"
done

echo ""

# --- Flatten legacy Roam subdirectories (lit/, concepts/) ---
legacy_dirs=("lit" "concepts")

for sub in "${legacy_dirs[@]}"; do
  src="$NOTE_HOME/Roam/$sub"
  if [ -d "$src" ]; then
    files=("$src"/*.org)
    if [ ${#files[@]} -gt 0 ]; then
      echo "  Flattening $src/ -> Roam/ ..."
      for f in "${files[@]}"; do
        base="$(basename "$f")"
        dest="$NOTE_HOME/Roam/$base"
        if [ -e "$dest" ]; then
          echo "    [skip] $base (already exists in Roam/)"
        else
          mv "$f" "$dest"
          echo "    [moved] $base"
        fi
      done
    fi
    # Remove subdirectory if now empty
    if [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
      rmdir "$src"
      echo "  [removed] empty directory $sub/"
    else
      echo "  [kept] $sub/ (still has non-org files)"
    fi
  fi
done

echo ""
echo "=== Next Steps ==="
echo "  1. Deploy config:  cd org-seq && bash deploy.sh   (or deploy.ps1 on Windows)"
echo "  2. Start Emacs and run:  M-x org-roam-db-sync"
echo "  3. If using org-supertag:  M-x supertag-sync-full-initialize"
echo "  4. Edit ~/NoteHQ/Roam/concepts/purpose.org and schema.org for AI context"
echo ""
echo "Done."
