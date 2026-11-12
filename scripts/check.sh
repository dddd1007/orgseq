#!/usr/bin/env bash
# check.sh --- Validate an org-seq source checkout (Linux, macOS)
#
# Runs every ERT file, byte-compiles all org-seq Elisp, starts the
# configuration in a batch Emacs, and removes the bytecode it produced.
# Notes are isolated: the library and its snapshots go to a temporary
# directory through ORG_SEQ_NOTE_HOME.
#
# Usage:
#   scripts/check.sh                      # clean checkout, no packages
#   scripts/check.sh --packages DIR       # use an installed package set
#   scripts/check.sh --strict             # module errors and required
#                                         # doctor failures fail the check
#   scripts/check.sh --no-upgrade-test    # skip the orgseq upgrade test
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES=""
STRICT=0
UPGRADE_TEST=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --packages) PACKAGES="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        --no-upgrade-test) UPGRADE_TEST=0; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

EMACS="${ORG_SEQ_EMACS:-emacs}"
cd "$ROOT"

SOURCE_DIRS=(core kernel modules)
load_paths=(-L "$ROOT")
files=(early-init.el init.el)
for dir in "${SOURCE_DIRS[@]}"; do
    while IFS= read -r d; do load_paths+=(-L "$d"); done < <(find "$ROOT/$dir" -type d)
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -name '*.el' | sort)
done
while IFS= read -r d; do load_paths+=(-L "$d"); done \
    < <(find "$ROOT/packages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
while IFS= read -r f; do files+=("$f"); done \
    < <(find packages -mindepth 2 -maxdepth 2 -name '*.el' 2>/dev/null | sort)

package_init="(progn)"
if [[ -n "$PACKAGES" ]]; then
    package_init="(progn (require 'package) (setq package-user-dir (expand-file-name \"$PACKAGES\")) (package-initialize))"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export ORG_SEQ_NOTE_HOME="$work/notes"
failures=0

echo "== ERT"
for test in scripts/test-*.el; do
    out="$("$EMACS" --batch -Q "${load_paths[@]}" --eval "$package_init" \
        -l "$test" -f ert-run-tests-batch-and-exit 2>&1)"
    status=$?
    summary="$(printf '%s\n' "$out" | grep -E '^Ran ' | tail -1)"
    if [[ $status -ne 0 ]]; then
        failures=$((failures + 1))
        echo "FAIL $test"
        printf '%s\n' "$out" | grep -E 'FAILED|^Test .* condition|error' | head -20
    else
        echo "ok   $test  ${summary#Ran }"
    fi
done

echo "== Byte compilation"
for file in "${files[@]}"; do
    out="$("$EMACS" --batch -Q "${load_paths[@]}" --eval "$package_init" \
        -f batch-byte-compile "$file" 2>&1)"
    status=$?
    rm -f "${file}c"
    if [[ $status -ne 0 ]]; then
        failures=$((failures + 1))
        echo "FAIL $file"
        printf '%s\n' "$out"
    elif printf '%s\n' "$out" | grep -q "Warning"; then
        # A package absent from a clean load path is expected; show the rest.
        printf '%s\n' "$out" | grep "Warning" | grep -v "Cannot load" | sed "s|^|warn |"
    fi
done
echo "compiled ${#files[@]} files"

echo "== Startup"
startup_args=(--batch --init-directory "$ROOT")
if [[ -n "$PACKAGES" ]]; then
    startup_args+=(--eval "(setq package-user-dir (expand-file-name \"$PACKAGES\"))")
fi
out="$("$EMACS" "${startup_args[@]}" -l "$ROOT/init.el" --eval \
    '(progn (princ (format "FAILED-MODULES %S\n" (mapcar (function car) my/--init-errors))) (princ (format "DOCTOR-FAIL %S\n" (if (fboundp (quote my/doctor-run)) (delq nil (mapcar (lambda (r) (and (eq (plist-get r :status) (quote fail)) (plist-get r :label))) (my/doctor-run)))))))' 2>&1)"
status=$?
printf '%s\n' "$out" | grep -E '^(FAILED-MODULES|DOCTOR-FAIL)'
if [[ $status -ne 0 ]]; then
    failures=$((failures + 1))
    echo "FAIL batch startup exited $status"
    printf '%s\n' "$out" | tail -20
elif [[ $STRICT -eq 1 ]] && ! printf '%s\n' "$out" | grep -q '^FAILED-MODULES nil'; then
    failures=$((failures + 1))
    echo "FAIL modules failed to load (strict)"
elif [[ $STRICT -eq 1 ]] && ! printf '%s\n' "$out" | grep -q '^DOCTOR-FAIL nil'; then
    failures=$((failures + 1))
    echo "FAIL required doctor checks failed (strict)"
fi

if [[ $UPGRADE_TEST -eq 1 ]]; then
    echo "== Upgrade"
    if ! bash "$ROOT/scripts/test-upgrade.sh"; then
        failures=$((failures + 1))
        echo "FAIL scripts/test-upgrade.sh"
    fi
fi

leftover="$(find "${SOURCE_DIRS[@]}" packages -name '*.elc' 2>/dev/null | wc -l)"
find "${SOURCE_DIRS[@]}" packages . -maxdepth 3 -name '*.elc' -not -path './elpa/*' -delete 2>/dev/null
[[ "$leftover" -ne 0 ]] && echo "removed $leftover leftover .elc files"

if [[ $failures -ne 0 ]]; then
    echo "== $failures check(s) failed"
    exit 1
fi
echo "== All checks passed"
