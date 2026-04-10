#!/usr/bin/env bash
# bootstrap-notes.sh --- Create NoteHQ directory structure and flatten legacy Roam subdirs
#
# Usage:
#   bootstrap-notes.sh           First-time setup. Existing files are skipped.
#   bootstrap-notes.sh --update  Overwrite Claude Code support files (CLAUDE.md,
#                                .claude/rules/*, .claude/skills/*) with the latest
#                                versions from the org-seq repo. Notes, schema,
#                                capture templates, and ai-config are never touched.
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
      echo "  --update, -u   Overwrite Claude Code scaffolding files (CLAUDE.md, rules, skills)"
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
  echo "    Mode: UPDATE — Claude Code scaffolding will be overwritten"
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

# --- Copy Claude Code support files (CLAUDE.md + skills + rules) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKELETON_DIR="$SCRIPT_DIR/../notehq"

if [ -d "$SKELETON_DIR" ]; then
  echo "  Installing Claude Code support files..."

  deploy_file "$SKELETON_DIR/CLAUDE.md" "$NOTE_HOME/CLAUDE.md" "CLAUDE.md"

  mkdir -p "$NOTE_HOME/.claude/skills"
  for skill in "$SKELETON_DIR/.claude/skills/"*.md; do
    base="$(basename "$skill")"
    deploy_file "$skill" "$NOTE_HOME/.claude/skills/$base" ".claude/skills/$base"
  done

  mkdir -p "$NOTE_HOME/.claude/rules"
  for rule in "$SKELETON_DIR/.claude/rules/"*.md; do
    base="$(basename "$rule")"
    deploy_file "$rule" "$NOTE_HOME/.claude/rules/$base" ".claude/rules/$base"
  done
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
  echo "  4. Use Claude Code inside ~/NoteHQ/ — it now has CLAUDE.md and skills"
  echo ""
  echo "  Refresh scaffolding later:  $0 --update"
fi
echo ""
echo "Done."
