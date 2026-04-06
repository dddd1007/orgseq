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

## Command

```bash
for f in early-init.el init.el lisp/*.el; do
  echo "=== Checking $f ==="
  emacs --batch -f batch-byte-compile "$f" 2>&1
  rm -f "${f}c"
done
```

Report results clearly: which files pass, which have issues, and what the issues are.
