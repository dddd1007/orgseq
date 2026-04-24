# Bundled Subprojects

This file overrides the repo-root `AGENTS.md` for everything under `packages/`.

## Golden Rule

Any package under `packages/<name>/` should be able to leave this repository with `git mv` and keep working without editing its source files.

## What Belongs Here

- Standalone Elisp with its own package header.
- Its own `defgroup` and `defcustom` values.
- Standalone defaults based on `user-emacs-directory` or other generic Emacs concepts.
- Package-local naming, docs, and README content.

## What Does Not Belong Here

- No `my/` prefix.
- No references to `my/note-home`, `my/roam-dir`, `my/orgseq-dir`, or other org-seq internals.
- No references to org-seq leader keys.
- No `require` of `init-*` modules.
- No `:group 'org-seq` in package customizations.

## Naming And File Shape

- Use the package name as the symbol prefix, for example `org-focus-...`.
- Use double-dash helpers for private functions.
- Keep `lexical-binding: t` in headers.
- End the top-level file with `(provide '<package-name>)`.

## Package Header Requirements

Each top-level package file should carry a real standalone package header with:

- one-line summary
- `Author`
- `Version`
- `Package-Requires`
- `Keywords`
- `URL`
- `Commentary`
- `Code`

## Dependencies

- Prefer built-in libraries where possible.
- Keep third-party dependencies minimal and explicit.
- If a bundled package starts accumulating several external dependencies, reconsider whether it still belongs under `packages/`.

## Validation

Packages here must compile without depending on org-seq modules on the load path.

Standalone compile check:

```powershell
emacs --batch -Q -L packages\<name> -f batch-byte-compile packages\<name>\<name>.el
Remove-Item packages\<name>\<name>.elc -ErrorAction SilentlyContinue
```

Also run the repo-wide compile pass from the root `AGENTS.md` after integration changes.

## Integration Boundary

Org-seq-specific behavior belongs in `lisp/init-<name>.el`, not inside the package directory.

- package source defines the reusable API
- integration module sets org-seq paths, bindings, and defaults
- deploy scripts copy `packages/` wholesale, so package code should stay self-contained
