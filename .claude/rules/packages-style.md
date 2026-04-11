---
globs: ["packages/**/*.el"]
---

# Bundled Subproject Style Rules

> Scope: this rule covers elisp files under `packages/**/*.el`. These are **independent subprojects** that happen to live inside org-seq for now but will eventually graduate to their own repositories. They follow **different conventions** from the org-seq config modules under `lisp/` — specifically, they must not carry any org-seq-specific code.

## The golden rule

**The day we `git mv packages/<name>/ ../<name>/` and publish it as its own repo, it should work without editing a single line of code inside that directory.**

Everything that follows is a consequence of this rule.

## What belongs inside `packages/<name>/`

- Standalone elisp with its own package-header comment (`Package-Requires:`, `Version:`, `URL:`, etc.)
- Its own `defgroup` (not `org-seq`)
- Its own `defcustom` with sensible standalone defaults (not tied to `~/NoteHQ/` or any org-seq-specific path)
- Its own `(provide '<package-name>)` matching the filename
- Its own README.md that can be read independently
- Ideally zero external dependencies beyond Emacs 30+

## What does NOT belong inside `packages/<name>/`

- **No `my/` prefix** — that's the org-seq private-variable convention. Bundled packages use their own prefix, typically the package name (e.g., `org-focus-` for `org-focus-timer`).
- **No references to org-seq paths** — `my/note-home`, `my/roam-dir`, `my/orgseq-dir` are org-seq concepts. The package must not import or assume them. If the package needs a directory, it defines its own defcustom with `user-emacs-directory` as the default and lets the integration layer override it.
- **No references to org-seq keybindings or leader keys** — the package exposes interactive commands; binding them to `SPC a f` is the integration layer's job, done inside `lisp/init-<name>.el`, not here.
- **No `(require 'init-org)` or any other `init-*` require** — config modules depend on packages, never the other way around.
- **No `:group 'org-seq` in package defcustoms** — the package owns its own group.

## Naming

- Function and variable prefix: the package name (e.g., `org-focus-start`, `org-focus-log-file`)
- Private helpers: double dash (e.g., `org-focus--snap-end-time`)
- Same `lexical-binding: t` header as the rest of the project

## Package-header requirements

Every top-level package file must have a proper package header for standalone consumption:

```elisp
;;; <name>.el --- One-line description -*- lexical-binding: t; -*-

;; Author: <your name>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: <comma-separated>
;; URL: <future github url or placeholder>

;;; Commentary:
;; <paragraph describing what this does>

;;; Code:
```

This makes the file installable directly by users who don't use org-seq — copy it to their load-path, `(require 'package-name)`, done.

## Character set discipline

Same rules as `elisp-style.md` apply: no emoji, no fullwidth punctuation, box-drawing characters OK in comments. The same past Windows-Emacs parse-error incident applies equally here.

## Dependencies

- Minimum Emacs version: 29.1 (same as org-seq)
- Prefer built-in libraries (`cl-lib`, `subr-x`, `org` itself) over third-party
- If you need a third-party package, declare it in `Package-Requires:` and document it in the package's README
- If you find yourself adding three or more ELPA dependencies to a bundled package, that's a signal it's getting too entangled — either simplify, move it fully into `lisp/init-*.el`, or push it out to its own repo early

## Testing

- Byte-compile independently: `emacs --batch -Q -L packages/<name> -f batch-byte-compile packages/<name>/<name>.el`
- The package must compile clean **without** any org-seq modules on the load-path (this verifies no hidden deps on `lisp/`)
- The PreToolUse pre-commit hook automatically includes `packages/**/*.el` in its compile pass

## Graduation checklist

When the package is ready to graduate to its own repo:

1. `cd org-seq && git mv packages/<name>/ ../<name>/` (or use `git filter-repo` to preserve history)
2. `cd ../<name> && git init && git remote add origin <github url> && git push -u origin main`
3. Back in org-seq, change `lisp/init-<name>.el`'s `:load-path` directive to `:vc (:url "<github url>" :rev :newest)`
4. Remove the `packages/<name>/` entry from `CLAUDE.md` directory layout
5. Update `CONTRIBUTING.md` "Bundled subprojects" section
6. Commit org-seq with "refactor: graduate <name> to its own repo"
