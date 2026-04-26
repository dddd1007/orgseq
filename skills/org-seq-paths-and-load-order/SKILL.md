---
name: org-seq Paths and Load Order
description: Work on NoteHQ/PARA paths, org-seq module dependencies, and load-order-sensitive refactors.
---

# org-seq Paths and Load Order

Use this skill when a change touches NoteHQ paths, PARA directories, org-roam/org-mem/org-supertag paths, or module dependencies.

## Central Path Source

Shared NoteHQ path constants belong in `lisp/init-org.el`.

This includes:

- `my/note-home`
- `my/orgseq-dir`
- `my/roam-dir`
- `my/outputs-dir`
- `my/practice-dir`
- `my/library-dir`
- `my/archives-dir`
- `my/dashboards-dir`
- `my/schema-file`
- `my/capture-templates-file`

Other modules should consume these with `defvar` declarations. Do not rebuild canonical paths with repeated string literals like `"00_Roam/"`, `"10_Outputs/"`, or `"20_Practice/"` unless the path is purely local and intentionally not a shared constant.

## GTD Path Semantics

GTD agenda scans actionable layers only:

- `my/roam-dir`
- `my/outputs-dir`
- `my/practice-dir`

It intentionally excludes:

- `my/library-dir`
- `my/archives-dir`

Keep that behavior unless the user asks for a workflow change.

## SuperTag and Dashboard Paths

- `init-supertag.el` should consume paths from `init-org.el`, not define PARA constants itself.
- Dashboard `.org` files live under `my/dashboards-dir` and should remain query-oriented.
- User capture templates live at `my/capture-templates-file` and are merged with built-in defaults from `init-roam.el`.

## Dependency Refactor Checklist

When moving a variable or function across modules:

1. Update the `Requires:` comments near the top of affected modules.
2. Add or remove `defvar` forward declarations.
3. Remove duplicate hard-coded paths.
4. Check the `init.el` module order still satisfies dependencies.
5. Run byte-compile on changed `.el` files.
6. Run `emacs --batch -Q -l init.el` for startup/load-order changes.
