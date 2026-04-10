---
name: elisp-lint
description: Byte-compile check all .el files in the project for errors and warnings
user_invocable: true
---

# Elisp Lint

Run byte-compilation checks on every `.el` file in the project — both org-seq config modules (`lisp/`) and bundled subprojects (`packages/**/`).

> **Synergy with hooks**: `.claude/settings.json` already auto-compiles each `.el` file on Write/Edit (PostToolUse) and rejects any `git commit` that breaks compilation (PreToolUse). This skill is for **full-repo verification mid-session** — e.g. after refactoring across multiple files, or before pushing without committing, or after editing bundled subproject files where you want to verify everything still composes.

## What gets linted

1. `early-init.el`
2. `init.el`
3. `lisp/init-*.el` — the 14 org-seq modules
4. `packages/*/*.el` — every elisp file inside any bundled subproject (currently just `packages/org-focus-timer/org-focus-timer.el`)

The load path must include `.`, `lisp/`, and every `packages/*/` directory so `require` forms resolve at compile time.

## Steps

1. Build the list of files and load-path flags, including any subdirectories discovered under `packages/`
2. Invoke `emacs --batch -Q` with the load-path flags and `-f batch-byte-compile` on every file
3. Report files that passed, failed, or produced warnings
4. Delete all `.elc` files afterwards — we don't ship bytecode

## Command (Bash — Git Bash, WSL, Linux, macOS)

```bash
# From the org-seq repo root
lps=(-L . -L lisp)
for d in packages/*/; do [ -d "$d" ] && lps+=(-L "$d"); done

files=(early-init.el init.el lisp/*.el)
for p in packages/*/*.el; do [ -f "$p" ] && files+=("$p"); done

fail=0
for f in "${files[@]}"; do
  echo "=== Checking $f ==="
  emacs --batch -Q "${lps[@]}" -f batch-byte-compile "$f" 2>&1 \
    || { echo "[FAIL] $f"; fail=1; }
  rm -f "${f}c"
done
echo "---"
if [ $fail -eq 0 ]; then
  echo "All ${#files[@]} files compile clean."
else
  echo "Byte-compile errors above; fix before committing."
  exit 1
fi
```

## Command (PowerShell — repo root)

```powershell
# From the org-seq repo root; emacs must be on PATH
$lps = @("-L", ".", "-L", "lisp")
if (Test-Path "packages") {
    Get-ChildItem "packages" -Directory | ForEach-Object {
        $lps += @("-L", $_.FullName)
    }
}

$files = @("early-init.el", "init.el")
$files += Get-ChildItem "lisp/*.el" | ForEach-Object { Join-Path "lisp" $_.Name }
if (Test-Path "packages") {
    $files += Get-ChildItem "packages/*/*.el" -File | ForEach-Object { $_.FullName }
}

$fail = $false
foreach ($f in $files) {
    Write-Host "=== Checking $f ==="
    & emacs --batch -Q @lps -f batch-byte-compile $f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] $f" -ForegroundColor Red
        $fail = $true
    }
    Remove-Item ($f + "c") -ErrorAction SilentlyContinue
}
Write-Host "---"
if (-not $fail) {
    Write-Host "All $($files.Count) files compile clean." -ForegroundColor Green
} else {
    Write-Host "Byte-compile errors above; fix before committing." -ForegroundColor Red
    exit 1
}
```

## Why both `-L lisp` and `-L packages/*/` are needed

- `-L lisp` lets `init-*.el` modules resolve `(require 'init-org)` and similar cross-module references
- `-L packages/org-focus-timer` lets any future package that builds on another package (or any file that wants to byte-compile after `(require 'org-focus-timer)`) find the required library

For the current single-package state (`packages/org-focus-timer/org-focus-timer.el` is self-contained and only requires `cl-lib` / `org` / `subr-x` from ambient Emacs), the package path technically isn't required. But adding all `packages/*/` directories to the load path is cheap and future-proof for when more subprojects arrive.

## Reporting

Report results clearly: which files pass, which have issues, and what the issues are. Always delete `.elc` files before exiting — the repo should not commit bytecode.
