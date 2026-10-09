---
name: org-seq Validation and Git
description: Validate org-seq changes, keep generated artifacts out of the tree, and commit/push only intentional files.
---

# org-seq Validation and Git

Use this skill before committing or after a multi-file refactor.

## Validation Commands

From the repository root, run a startup check after load-order or startup changes:

```bash
emacs --batch -Q -l init.el
```

Run byte-compile on changed files after editing `.el` files. On Unix-like shells:

```bash
lps=("-L" "." "-L" "lisp")
for d in packages/*; do [ -d "$d" ] && lps+=("-L" "$d"); done
emacs --batch -Q "${lps[@]}" -f batch-byte-compile path/to/file.el
rm -f path/to/file.elc
```

For full-repo validation:

```bash
lps=("-L" "." "-L" "lisp")
for d in packages/*; do [ -d "$d" ] && lps+=("-L" "$d"); done
files=(early-init.el init.el lisp/*.el packages/*/*.el)
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  emacs --batch -Q "${lps[@]}" -f batch-byte-compile "$f"
  rm -f "${f}c"
done
```

On Windows PowerShell, use the commands documented in `AGENTS.md`.

## Interpreting Output

- `Cannot load PACKAGE` during `-Q` byte-compilation usually means the clean validation environment does not have a third-party package in `load-path`.
- The tree compiles warning-free against Emacs 30 and 31 when the packages are
  installed. Treat any file-attributed warning as a regression to fix, not as
  background noise: `scripts/check.ps1 -RequireNoWarnings` fails the run.
- A definition placed inside a `use-package` `:config` body is invisible to the
  byte compiler. That is not only a warning: a macro defined there compiles its
  call sites into plain function calls, and the whole `:config` block then
  aborts at startup. Keep `defun`, `defvar`, `defmacro`, and `define-advice`
  at top level and leave only configuration inside `:config`.
- Always remove generated `.elc` files. The repo does not commit bytecode;
  `scripts/check.ps1` compiles into a temporary directory instead.

## Git Review Checklist

Before commit:

1. Run `git status --short --branch`.
2. Run `git diff --stat` and `git diff --check`.
3. Review the actual diff, not just the stat.
4. Stage only intended tracked files.
5. Leave local pi/session/runtime untracked files alone unless the user asks.
6. Commit using the existing style, e.g. `refactor(init): ...`, `fix(init): ...`, `docs: ...`.
7. Push only after validation and review.

Common local/untracked state can include files such as `config.json`, `events.jsonl`, `labels/`, `sessions/`, `statuses/`, `views.json`, or `.claude-plugin/`. Do not add these casually.
