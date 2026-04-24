#!/usr/bin/env bash
# bootstrap-notes.sh --- Create NoteHQ directory structure and flatten legacy Roam subdirs
#
# Usage:
#   bootstrap-notes.sh           First-time setup. Existing files are skipped.
#   bootstrap-notes.sh --update  Overwrite Codex support files (currently
#                                AGENTS.md) with the latest versions from the
#                                org-seq repo. Notes, schema, capture templates,
#                                and ai-config are never touched. Legacy Claude
#                                scaffolding is archived.
set -e
shopt -s nullglob

UPDATE_MODE=0
for arg in "$@"; do
  case "$arg" in
    --update|-u)
      UPDATE_MODE=1
      ;;
    --help|-h)
      echo "Usage: $0 [--update]"
      echo ""
      echo "  --update, -u   Overwrite Codex scaffolding files (currently AGENTS.md)"
      echo "                 with the latest versions from the org-seq repo. User content"
      echo "                 (notes, schema, capture templates, ai-config) is never touched."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
  esac
done

NOTE_HOME="$HOME/NoteHQ"

echo "=== org-seq: Bootstrap NoteHQ Directory Structure ==="
if [ "$UPDATE_MODE" = "1" ]; then
  echo "    Mode: UPDATE — Codex scaffolding will be overwritten"
fi
echo ""

# --- Helper: deploy a file with skip / update / create semantics ---
deploy_file() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ ! -f "$src" ]; then
    echo "  [missing] $label (source not found: $src)"
    return
  fi
  if [ -f "$dest" ]; then
    if [ "$UPDATE_MODE" = "1" ]; then
      if cmp -s "$src" "$dest"; then
        echo "  [unchanged] $label"
      else
        cp "$src" "$dest"
        echo "  [updated] $label"
      fi
    else
      echo "  [skip]    $label (already exists; use --update to overwrite)"
    fi
  else
    cp "$src" "$dest"
    echo "  [created] $label"
  fi
}

archive_legacy_claude_scaffold() {
  if [ "$UPDATE_MODE" != "1" ]; then
    return
  fi

  local legacy_file="$NOTE_HOME/CLAUDE.md"
  local legacy_dir="$NOTE_HOME/.claude"
  if [ ! -e "$legacy_file" ] && [ ! -e "$legacy_dir" ]; then
    return
  fi

  local archive_root="$NOTE_HOME/.orgseq"
  mkdir -p "$archive_root"

  local stamp archive_dir suffix
  stamp="$(date +%Y%m%d-%H%M%S)"
  archive_dir="$archive_root/legacy-claude-scaffold-$stamp"
  suffix=1
  while [ -e "$archive_dir" ]; do
    archive_dir="$archive_root/legacy-claude-scaffold-$stamp-$suffix"
    suffix=$((suffix + 1))
  done
  mkdir -p "$archive_dir"

  if [ -e "$legacy_file" ]; then
    mv "$legacy_file" "$archive_dir/"
  fi
  if [ -e "$legacy_dir" ]; then
    mv "$legacy_dir" "$archive_dir/"
  fi

  echo "  [archived] legacy Claude scaffolding -> $archive_dir"
}

# --- Migrate old layout to numeric-prefixed layout (idempotent) ---
# Old layout (pre-numbering): Roam / Outputs / Practice / Library / Archives
# New layout: 00_Roam / 10_Outputs / 20_Practice / 30_Library / 40_Archives
migrate_layer() {
  local old="$1" new="$2"
  if [ -d "$NOTE_HOME/$old" ] && [ ! -d "$NOTE_HOME/$new" ]; then
    mv "$NOTE_HOME/$old" "$NOTE_HOME/$new"
    echo "  [migrated] $old -> $new"
  fi
}
migrate_layer "Roam"     "00_Roam"
migrate_layer "Outputs"  "10_Outputs"
migrate_layer "Practice" "20_Practice"
migrate_layer "Library"  "30_Library"
migrate_layer "Archives" "40_Archives"

# --- Create directory tree (idempotent) ---
dirs=(
  "$NOTE_HOME/00_Roam/daily"
  "$NOTE_HOME/00_Roam/capture"
  "$NOTE_HOME/00_Roam/dashboards"
  "$NOTE_HOME/10_Outputs/_template"
  "$NOTE_HOME/20_Practice/_template"
  "$NOTE_HOME/30_Library/bibliography"
  "$NOTE_HOME/30_Library/datasets"
  "$NOTE_HOME/30_Library/snippets"
  "$NOTE_HOME/30_Library/references"
  "$NOTE_HOME/30_Library/pdfs"
  "$NOTE_HOME/40_Archives"
  "$NOTE_HOME/.orgseq"
)

for d in "${dirs[@]}"; do
  mkdir -p "$d"
  echo "  [ok] $d"
done

echo ""

# --- Flatten legacy Roam subdirectories (lit/, concepts/) ---
# (Works against the post-migration 00_Roam name; if the old Roam
# layout hasn't been migrated yet the migrate_layer block above has
# already renamed it.)
legacy_dirs=("lit" "concepts")

for sub in "${legacy_dirs[@]}"; do
  src="$NOTE_HOME/00_Roam/$sub"
  if [ -d "$src" ]; then
    files=("$src"/*.org)
    if [ ${#files[@]} -gt 0 ]; then
      echo "  Flattening $src/ -> 00_Roam/ ..."
      for f in "${files[@]}"; do
        base="$(basename "$f")"
        dest="$NOTE_HOME/00_Roam/$base"
        if [ -e "$dest" ]; then
          echo "    [skip] $base (already exists in 00_Roam/)"
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

# --- Copy Codex support files (currently AGENTS.md) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKELETON_DIR="$SCRIPT_DIR/../notehq"

if [ -d "$SKELETON_DIR" ]; then
  echo "  Installing Codex support files..."

  deploy_file "$SKELETON_DIR/AGENTS.md" "$NOTE_HOME/AGENTS.md" "AGENTS.md"
  archive_legacy_claude_scaffold
fi

echo ""
if [ "$UPDATE_MODE" = "1" ]; then
  echo "=== Update complete ==="
  echo "  Re-pull org-seq and run '$0 --update' anytime to refresh the scaffolding."
else
  echo "=== Next Steps ==="
  echo "  1. Deploy config:  cd org-seq && bash deploy.sh   (or deploy.ps1 on Windows)"
  echo "  2. Start Emacs and run:  M-x org-roam-db-sync"
  echo "  3. Run:  M-x supertag-sync-full-initialize"
  echo "  4. Use Codex inside ~/NoteHQ/ — it now has AGENTS.md guidance"
  echo ""
  echo "  Refresh scaffolding later:  $0 --update"
fi
echo ""
echo "Done."
