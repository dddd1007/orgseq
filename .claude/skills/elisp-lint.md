---
name: elisp-lint
description: Byte-compile check all .el files in the project for errors and warnings
user_invocable: true
---

# Elisp Lint

Run byte-compilation checks on all `.el` files in the org-seq project to catch errors.

## Steps

1. Find all `.el` files in the project root and `lisp/` directory
2. For each file, run: `emacs --batch -f batch-byte-compile <file>`
3. Report any errors or warnings found
4. Clean up generated `.elc` files (we don't ship bytecode)

## Command (Bash — e.g. Git Bash, WSL, deploy.sh environment)

```bash
for f in early-init.el init.el lisp/*.el; do
  echo "=== Checking $f ==="
  emacs --batch -Q -L . -L lisp -f batch-byte-compile "$f" 2>&1
  rm -f "${f}c"
done
```

## Command (PowerShell — repo root)

From `org-seq` root, `emacs` must be on PATH:

```powershell
$files = @("early-init.el", "init.el") +
  (Get-ChildItem "lisp\*.el" | ForEach-Object { Join-Path "lisp" $_.Name })
foreach ($f in $files) {
  Write-Host "=== Checking $f ==="
  & emacs --batch -Q -L . -L lisp -f batch-byte-compile $f 2>&1
  Remove-Item ($f + "c") -ErrorAction SilentlyContinue
}
```

**Always** pass `-L . -L lisp` so modules and `init.el` resolve `require` forms. Delete stray `.elc` after check; the repo should not commit bytecode.

Report results clearly: which files pass, which have issues, and what the issues are.
