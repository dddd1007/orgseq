#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — Deploy org-seq Emacs configuration to ~/.emacs.d/
#
# Usage:
#   ./deploy.sh                  # back up the files it replaces, then deploy
#   ./deploy.sh --full-backup    # back up the whole target directory instead
#   ./deploy.sh --no-backup      # deploy without creating a backup
#   ./deploy.sh --force          # continue despite failed required checks
#   ./deploy.sh --skip-checks    # skip prerequisite checks
#   ./deploy.sh --target DIR     # custom target directory
#   ./deploy.sh --skip-verify    # skip the byte-compile gate (tests only;
#                                # a real deployment should keep the gate)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${HOME}/.emacs.d"
FORCE=0
NO_BACKUP=0
FULL_BACKUP=0
SKIP_CHECKS=0
SKIP_VERIFY=0

# What a deployment replaces.  Everything else in the target belongs to the
# user (notes/, custom.el) or is rebuildable device state (elpa/, .cache/)
# and is never written.  custom.el is backed up but not replaced.
SOURCE_DIRS=(core kernel modules)
DEPLOYED_ITEMS=(early-init.el init.el ec "${SOURCE_DIRS[@]}" packages bin .org-seq-version .org-seq-source)
# Layout of earlier versions; removed from the target after a backup.
OBSOLETE_ITEMS=(lisp)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)    TARGET="$2"; shift 2 ;;
        --backup)    NO_BACKUP=0; shift ;;
        --no-backup) NO_BACKUP=1; shift ;;
        --full-backup) FULL_BACKUP=1; shift ;;
        --force)     FORCE=1; shift ;;
        --skip-checks) SKIP_CHECKS=1; shift ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--target DIR] [--no-backup] [--full-backup] [--force] [--skip-checks] [--skip-verify]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

resolve_safe_target() {
    local requested="$1"
    local resolved
    local parent
    local base

    if [[ -d "$requested" ]]; then
        resolved="$(cd "$requested" && pwd -P)"
    else
        parent="$(dirname "$requested")"
        base="$(basename "$requested")"
        if [[ ! -d "$parent" ]]; then
            printf 'Refusing deployment target with missing parent: %s\n' "$requested" >&2
            return 1
        fi
        resolved="$(cd "$parent" && pwd -P)/$base"
    fi

    local home_resolved
    home_resolved="$(cd "$HOME" && pwd -P)"
    if [[ "$resolved" == "/" ||
          "$resolved" == "$home_resolved" ||
          "$resolved" == "$SCRIPT_DIR" ||
          "$resolved" == "$SCRIPT_DIR/"* ||
          ( "$SCRIPT_DIR" == "$resolved/"* &&
            "$SCRIPT_DIR" != "$resolved/.cache/"* ) ]]; then
        printf 'Refusing unsafe deployment target: %s\n' "$resolved" >&2
        return 1
    fi

    printf '%s\n' "$resolved"
}

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
        if [[ "$major" -ge 30 ]]; then
            pass "Emacs $major ($ver)"
        else
            warn "Emacs $major found, 30+ required"
            all_ok=0
        fi

        local sqlite
        sqlite="$(emacs --batch --eval '(message "%s" (sqlite-available-p))' 2>&1 | tail -1)"
        if [[ "$sqlite" == "t" ]]; then pass "SQLite support available"
        else fail "SQLite not available. org-roam requires Emacs 30+ with SQLite."; all_ok=0; fi

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
    elif command -v fdfind &>/dev/null; then pass "fdfind found (Debian/Ubuntu fd)"
    else warn "fd/fdfind not found. Install via package manager."; fi

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

    local first_child
    first_child="$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)"
    if [[ -z "$first_child" ]]; then return; fi

    section "Existing config detected"
    echo "  Target: $TARGET"

    if [[ "$NO_BACKUP" -eq 1 ]]; then
        warn "Skipping backup because --no-backup was specified."
        return
    fi

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup_dir="${TARGET}.backup-${timestamp}"
    echo "  Backing up to: $backup_dir"
    if [[ "$FULL_BACKUP" -eq 1 ]]; then
        cp -a "$TARGET" "$backup_dir"
        pass "Backup complete (whole directory)"
        return
    fi

    # Copy only what this deployment replaces, plus custom.el.  The note
    # library and installed packages are not written by a deployment, so
    # copying them would only cost time and disk space.
    mkdir -p "$backup_dir"
    local item
    for item in "${DEPLOYED_ITEMS[@]}" "${OBSOLETE_ITEMS[@]}" custom.el user; do
        if [[ -e "$TARGET/$item" ]]; then
            cp -a "$TARGET/$item" "$backup_dir/"
        fi
    done
    pass "Backup complete (replaced files, custom.el and user/; notes/ and elpa/ are not touched by deployment)"
}

# ── Deploy ──

deploy_config() {
    section "Deploying org-seq to $TARGET"

    mkdir -p "$TARGET"

    for f in early-init.el init.el ec; do
        if [[ ! -f "$SCRIPT_DIR/$f" ]]; then fail "Missing source: $SCRIPT_DIR/$f"; exit 1; fi
        cp -f "$SCRIPT_DIR/$f" "$TARGET/"
        if [[ "$f" == "ec" ]]; then chmod +x "$TARGET/$f"; fi
        pass "$f"
    done

    local dir
    local module_count=0
    for dir in "${SOURCE_DIRS[@]}"; do
        if [[ ! -d "$SCRIPT_DIR/$dir" ]]; then fail "Missing source: $SCRIPT_DIR/$dir"; exit 1; fi
        if [[ -d "$TARGET/$dir" ]]; then rm -rf "$TARGET/$dir"; fi
        cp -r "$SCRIPT_DIR/$dir" "$TARGET/$dir"
        module_count=$((module_count + $(find "$TARGET/$dir" -name '*.el' | wc -l)))
    done
    pass "core/ kernel/ modules/ ($module_count Elisp files)"

    # Directories of the earlier flat layout would shadow nothing (they are
    # no longer on load-path) but would mislead; the backup above has them.
    local obsolete
    for obsolete in "${OBSOLETE_ITEMS[@]}"; do
        if [[ -d "$TARGET/$obsolete" ]]; then
            rm -rf "$TARGET/$obsolete"
            pass "removed obsolete $obsolete/"
        fi
    done

    # The user's layer: created once, never overwritten.  A custom.el from
    # an earlier version moves into it.
    mkdir -p "$TARGET/user"
    if [[ -f "$TARGET/custom.el" && ! -f "$TARGET/user/custom.el" ]]; then
        mv "$TARGET/custom.el" "$TARGET/user/custom.el"
        rm -f "$TARGET/custom.elc"
        pass "custom.el moved to user/custom.el"
    fi
    local example
    for example in modules.el config.el; do
        if [[ ! -f "$TARGET/user/$example" && -f "$SCRIPT_DIR/user.example/$example" ]]; then
            cp "$SCRIPT_DIR/user.example/$example" "$TARGET/user/$example"
            pass "user/$example created"
        fi
    done

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

    # Command line and MCP launcher (bin/orgseq); loads core/orgseq-cli.el.
    if [[ -d "$SCRIPT_DIR/bin" ]]; then
        mkdir -p "$TARGET/bin"
        # Copy then rename: `orgseq upgrade' runs this script while the
        # launcher is still executing, and bash reads a script as it runs.
        # A rename leaves the running file's old contents intact.
        local binfile
        for binfile in "$SCRIPT_DIR/bin/"*; do
            cp -f "$binfile" "$TARGET/bin/.$(basename "$binfile").new"
            mv -f "$TARGET/bin/.$(basename "$binfile").new" "$TARGET/bin/$(basename "$binfile")"
        done
        chmod +x "$TARGET/bin/orgseq"
        pass "bin/ (orgseq command line)"
    fi

    if [[ -f "$SCRIPT_DIR/pyim/rime-frost.pyim" ]]; then
        mkdir -p "$TARGET/pyim"
        cp -f "$SCRIPT_DIR/pyim/rime-frost.pyim" "$TARGET/pyim/"
        pass "pyim/rime-frost.pyim"
    fi

    # Restore custom.el from latest backup if needed
    local latest_backup
    latest_backup="$(ls -dt "${TARGET}.backup-"* 2>/dev/null | head -1 || true)"
    if [[ -n "$latest_backup" && ! -f "$TARGET/user/custom.el" ]]; then
        local saved=""
        if [[ -f "$latest_backup/user/custom.el" ]]; then saved="$latest_backup/user/custom.el"
        elif [[ -f "$latest_backup/custom.el" ]]; then saved="$latest_backup/custom.el"; fi
        if [[ -n "$saved" ]]; then
            cp "$saved" "$TARGET/user/custom.el"
            pass "user/custom.el restored from backup"
        fi
    fi

    local base_version="unknown"
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        base_version="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
        [[ -n "$base_version" ]] || base_version="unknown"
    fi
    local commit=""
    local short="unknown"
    if command -v git &>/dev/null; then
        commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$commit" ]]; then short="${commit:0:7}"; fi
    fi
    local version="$base_version ($short)"
    printf '%s' "$version" > "$TARGET/.org-seq-version"
    pass ".org-seq-version ($version)"

    # Where this deployment came from, so `orgseq upgrade' can find it again.
    # Device state, not user data.  Credentials embedded in the remote URL
    # are removed; nothing secret is recorded.
    local url=""
    local ref=""
    if command -v git &>/dev/null && [[ -n "$commit" ]]; then
        url="$(git -C "$SCRIPT_DIR" config --get remote.origin.url 2>/dev/null || true)"
        url="$(printf '%s' "$url" | sed -E \
            -e 's#^(https?|ftp)://[^/@]*@#\1://#' \
            -e 's#^([A-Za-z+.-]+://)[^/@:]*:[^/@]*@#\1#')"
        ref="$(git -C "$SCRIPT_DIR" symbolic-ref --short -q HEAD 2>/dev/null || true)"
    fi
    {
        printf 'path=%s\n' "$SCRIPT_DIR"
        printf 'url=%s\n' "$url"
        printf 'ref=%s\n' "$ref"
        printf 'commit=%s\n' "$commit"
    } > "$TARGET/.org-seq-source"
    pass ".org-seq-source (${url:-$SCRIPT_DIR})"
}

# ── Verify ──

verify_deployment() {
    section "Verifying deployment"

    if ! command -v emacs &>/dev/null; then
        fail "Emacs not found; deployment cannot be verified."
        return 1
    fi

    local pkg_dir="$TARGET/packages"
    local files=("$TARGET/early-init.el" "$TARGET/init.el")
    local load_paths=("-L" "$TARGET")
    local dir
    for dir in "${SOURCE_DIRS[@]}"; do
        while IFS= read -r f; do files+=("$f"); done < <(find "$TARGET/$dir" -name '*.el')
        while IFS= read -r d; do load_paths+=("-L" "$d"); done < <(find "$TARGET/$dir" -type d)
    done
    if [[ -d "$pkg_dir" ]]; then
        while IFS= read -r f; do files+=("$f"); done < <(find "$pkg_dir" -name '*.el')
    fi

    if [[ -d "$pkg_dir" ]]; then
        while IFS= read -r d; do load_paths+=("-L" "$d"); done \
            < <(find "$pkg_dir" -mindepth 1 -maxdepth 1 -type d)
    fi
    # Activate installed packages through package.el, which exposes only the
    # newest version of each package; adding every elpa directory with -L
    # would also load stale versions package.el could not delete.
    local package_init="(progn (require 'package) (setq package-user-dir (expand-file-name \"elpa\" \"$TARGET\")) (package-initialize))"

    local output
    local status
    set +e
    output="$(emacs --batch -Q "${load_paths[@]}" --eval "$package_init" -f batch-byte-compile "${files[@]}" 2>&1)"
    status=$?
    set -e

    # Remove only the bytecode this check produced; a recursive sweep would
    # also delete the compiled packages under elpa/.
    local f
    for f in "${files[@]}"; do rm -f "${f}c"; done

    if [[ "$status" -ne 0 ]]; then
        fail "Byte-compile check failed (exit code $status)"
        [[ -n "$output" ]] && printf '%s\n' "$output"
        return "$status"
    elif printf '%s\n' "$output" | grep -qi "warning"; then
        warn "Byte-compile produced warnings:"
        printf '%s\n' "$output"
    else
        pass "All files byte-compile cleanly"
    fi

}

# ── Summary ──

print_summary() {
    section "Deployment complete"
    local note_home="${ORG_SEQ_NOTE_HOME:-$TARGET/notes/}"
    echo ""
    echo "  Next steps:"
    echo "    1. Optional: ./scripts/bootstrap-notes.sh  (seed files; Emacs creates the library itself)"
    echo "    2. Launch Emacs — packages auto-install on first run (needs internet)"
    echo "    3. Run:  M-x nerd-icons-install-fonts"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "       On macOS, install the downloaded fonts through Font Book if prompted"
    elif [[ "$(uname -s)" == *"MINGW"* || "$(uname -s)" == *"MSYS"* ]]; then
        echo "       Then right-click downloaded .ttf files → Install (Windows)"
    fi
    echo "    4. Run:  M-x org-roam-db-sync  (first-time index of existing notes)"
    echo "    5. Optional: Point Obsidian at $note_home as reading client"
    echo ""
    echo "  Note library:"
    echo "    $note_home"
    echo "    Deployment never writes there.  Local snapshots: M-x my/storage-snapshot"
    echo "    Sync across devices:  M-x my/sync-setup  (WebDAV, OneDrive, Google Drive; needs rclone)"
    echo "    Bring notes in from a folder:  M-x my/storage-import  (or: orgseq import DIR)"
    echo ""
    echo "  Command line:"
    echo "    Add $TARGET/bin to PATH, then:  orgseq help   (orgseq mcp serves MCP clients)"
    echo ""
    echo "  Key bindings:"
    echo "    SPC d       → Daily workspace     SPC t d  → GTD dashboard"
    echo "    SPC n c     → new note            SPC # t/c → tags/templates"
    echo "    SPC P o/p/l → PARA navigation     SPC n v v → dashboards"
    echo ""
}

# ── Main ──

echo "org-seq deploy"
TARGET="$(resolve_safe_target "$TARGET")"
echo "Source: $SCRIPT_DIR"
echo "Target: $TARGET"

if [[ "$SKIP_CHECKS" -eq 0 ]]; then check_prerequisites; fi
backup_existing
deploy_config
if [[ "$SKIP_VERIFY" -eq 0 ]]; then verify_deployment; fi
print_summary
