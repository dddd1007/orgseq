#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — Deploy org-seq Emacs configuration to ~/.emacs.d/
#
# Usage:
#   ./deploy.sh                  # interactive deploy
#   ./deploy.sh --force          # skip backup prompt
#   ./deploy.sh --skip-checks    # skip prerequisite checks
#   ./deploy.sh --target DIR     # custom target directory

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${HOME}/.emacs.d"
FORCE=0
SKIP_CHECKS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)    TARGET="$2"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --skip-checks) SKIP_CHECKS=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--target DIR] [--force] [--skip-checks]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

pass()    { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn()    { printf "  \033[33m⚠\033[0m %s\n" "$1"; }
fail()    { printf "  \033[31m✗\033[0m %s\n" "$1"; }
section() { printf "\n\033[36m── %s ──\033[0m\n" "$1"; }

# ── Prerequisites ──

check_prerequisites() {
    section "Checking prerequisites"
    local all_ok=1

    if command -v emacs &>/dev/null; then
        local ver
        ver="$(emacs --version | head -1)"
        local major
        major="$(echo "$ver" | grep -oE '[0-9]+' | head -1)"
        if [[ "$major" -ge 29 ]]; then
            pass "Emacs $major ($ver)"
        else
            warn "Emacs $major found, 29+ required"
            all_ok=0
        fi

        local sqlite
        sqlite="$(emacs --batch --eval '(message "%s" (sqlite-available-p))' 2>&1 | tail -1)"
        if [[ "$sqlite" == "t" ]]; then pass "SQLite support available"
        else fail "SQLite not available. org-roam requires Emacs 29+ with SQLite."; all_ok=0; fi

        local nc
        nc="$(emacs --batch --eval '(message "%s" (native-comp-available-p))' 2>&1 | tail -1)"
        if [[ "$nc" == "t" ]]; then pass "Native-comp available"
        else warn "Native-comp not available"; fi
    else
        fail "Emacs not found"
        all_ok=0
    fi

    if command -v rg &>/dev/null; then pass "ripgrep (rg) found"
    else warn "ripgrep not found. Install via package manager."; fi

    if command -v fd &>/dev/null; then pass "fd found"
    else warn "fd not found. Install via package manager."; fi

    if command -v git &>/dev/null; then pass "git found"
    else warn "git not found. Magit requires git."; fi

    if command -v pandoc &>/dev/null; then pass "pandoc found (markdown export)"
    else warn "pandoc not found. Markdown export will use basic processor."; fi

    if [[ "$all_ok" -eq 0 ]]; then
        echo ""
        fail "Required dependencies missing."
        if [[ "$FORCE" -eq 0 ]]; then exit 1; fi
    fi
}

# ── Backup ──

backup_existing() {
    if [[ ! -d "$TARGET" ]]; then return; fi

    local file_count
    file_count="$(find "$TARGET" -maxdepth 1 -name '*.el' 2>/dev/null | wc -l)"
    if [[ "$file_count" -eq 0 ]]; then return; fi

    section "Existing config detected"
    echo "  Target: $TARGET"

    if [[ "$FORCE" -eq 0 ]]; then
        read -rp "  Back up existing config before overwriting? [Y/n] " answer
        if [[ "$answer" == "n" || "$answer" == "N" ]]; then
            read -rp "  Continue WITHOUT backup? This will overwrite files. [y/N] " skip
            if [[ "$skip" != "y" && "$skip" != "Y" ]]; then
                echo "  Aborted."
                exit 0
            fi
            return
        fi
    fi

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup_dir="${TARGET}.backup-${timestamp}"
    echo "  Backing up to: $backup_dir"
    cp -a "$TARGET" "$backup_dir"
    pass "Backup complete"
}

# ── Deploy ──

deploy_config() {
    section "Deploying org-seq to $TARGET"

    mkdir -p "$TARGET"

    for f in early-init.el init.el; do
        if [[ ! -f "$SCRIPT_DIR/$f" ]]; then fail "Missing source: $SCRIPT_DIR/$f"; exit 1; fi
        cp -f "$SCRIPT_DIR/$f" "$TARGET/"
        pass "$f"
    done

    if [[ -d "$TARGET/lisp" ]]; then rm -rf "$TARGET/lisp"; fi
    cp -r "$SCRIPT_DIR/lisp" "$TARGET/lisp"
    local module_count
    module_count="$(find "$TARGET/lisp" -name '*.el' | wc -l)"
    pass "lisp/ ($module_count modules)"

    # Bundled subprojects live under packages/ — currently just
    # org-focus-timer.  Copy the whole tree so init-focus.el can find it
    # via user-emacs-directory.
    if [[ -d "$SCRIPT_DIR/packages" ]]; then
        if [[ -d "$TARGET/packages" ]]; then rm -rf "$TARGET/packages"; fi
        cp -r "$SCRIPT_DIR/packages" "$TARGET/packages"
        local pkg_count
        pkg_count="$(find "$TARGET/packages" -name '*.el' | wc -l)"
        pass "packages/ ($pkg_count elisp files)"
    fi

    # Restore custom.el from latest backup if needed
    local latest_backup
    latest_backup="$(ls -dt "${TARGET}.backup-"* 2>/dev/null | head -1)"
    if [[ -n "$latest_backup" && -f "$latest_backup/custom.el" && ! -f "$TARGET/custom.el" ]]; then
        cp "$latest_backup/custom.el" "$TARGET/custom.el"
        pass "custom.el restored from backup"
    fi
}

# ── Verify ──

verify_deployment() {
    section "Verifying deployment"

    if ! command -v emacs &>/dev/null; then
        warn "Emacs not found, skipping byte-compile check"
        return
    fi

    local lisp_dir="$TARGET/lisp"
    local pkg_dir="$TARGET/packages"
    local files=("$TARGET/early-init.el" "$TARGET/init.el")
    while IFS= read -r f; do files+=("$f"); done < <(find "$lisp_dir" -name '*.el')
    if [[ -d "$pkg_dir" ]]; then
        while IFS= read -r f; do files+=("$f"); done < <(find "$pkg_dir" -name '*.el')
    fi

    local load_paths=("-L" "$TARGET" "-L" "$lisp_dir")
    if [[ -d "$pkg_dir" ]]; then
        while IFS= read -r d; do load_paths+=("-L" "$d"); done \
            < <(find "$pkg_dir" -mindepth 1 -maxdepth 1 -type d)
    fi

    local output
    local status
    set +e
    output="$(emacs --batch -Q "${load_paths[@]}" -f batch-byte-compile "${files[@]}" 2>&1)"
    status=$?
    set -e

    if [[ "$status" -ne 0 ]]; then
        warn "Byte-compile check failed (exit code $status)"
        [[ -n "$output" ]] && printf '%s\n' "$output"
    elif printf '%s\n' "$output" | grep -qi "warning"; then
        warn "Byte-compile produced warnings:"
        printf '%s\n' "$output"
    else
        pass "All files byte-compile cleanly"
    fi

    find "$TARGET" -name '*.elc' -delete 2>/dev/null || true
}

# ── Summary ──

print_summary() {
    section "Deployment complete"
    echo ""
    echo "  Next steps:"
    echo "    1. Run:  ./scripts/bootstrap-notes.sh  (creates ~/NoteHQ/ directory structure)"
    echo "    2. Launch Emacs — packages auto-install on first run (needs internet)"
    echo "    3. Run:  M-x nerd-icons-install-fonts"
    if [[ "$(uname -s)" == *"MINGW"* || "$(uname -s)" == *"MSYS"* ]]; then
        echo "       Then right-click downloaded .ttf files → Install (Windows)"
    fi
    echo "    4. Run:  M-x supertag-sync-full-initialize  (first-time supertag index)"
    echo "    5. Optional: Point Obsidian at ~/NoteHQ/ as reading client"
    echo ""
    echo "  Key bindings:"
    echo "    SPC         → leader menu         SPC a d  → GTD dashboard"
    echo "    SPC n c     → new note            SPC n m  → extend (templates/schema)"
    echo "    SPC P o/p/l → PARA navigation     SPC n v  → dashboards"
    echo ""
}

# ── Main ──

echo "org-seq deploy"
echo "Source: $SCRIPT_DIR"
echo "Target: $TARGET"

if [[ "$SKIP_CHECKS" -eq 0 ]]; then check_prerequisites; fi
backup_existing
deploy_config
verify_deployment
print_summary
