---
name: org-seq Elisp Maintenance
description: Maintain org-seq Emacs Lisp modules with the repository's load-order, warning-hygiene, and private-configuration conventions.
---

# org-seq Elisp Maintenance

Use this skill when editing `early-init.el`, `init.el`, root helper `.el` files, or `lisp/*.el`.

## Ground Rules

- Treat org-seq as a deployable `~/.emacs.d/` configuration for Emacs 30+.
- Preserve `lexical-binding: t` headers and `(provide 'init-MODULE)` endings.
- Prefer `use-package` for packages; use bare `require` for built-ins or structural needs.
- Keep public org-seq names under `my/`; use `my/module--helper` for private helpers.
- Use ASCII in Elisp comments and strings unless the file already needs non-ASCII content.

## Load Order Discipline

The load order in `init.el` is intentional:

`init-ui -> init-completion -> init-pyim -> init-markdown -> init-languages -> init-org -> init-roam -> init-gtd -> init-focus -> init-pkm -> init-supertag -> init-ai -> init-dashboard -> init-dired -> init-workspace -> init-update -> init-tty -> init-evil`

When changing it:

1. Update the actual module list.
2. Update the load-order comment in `init.el` in the same patch.
3. Update `AGENTS.md` if the order or rationale changes.
4. Run a startup check with `emacs --batch -Q -l init.el`.

## Diagnostics and Warnings

- Keep guarded module loading visible through `my/--init-errors` and `M-x my/init-errors`.
- If a module is allowed to fail without aborting startup, the warning must tell the user how to inspect details.
- Reduce warning noise in touched files with:
  - `defvar` for cross-module variables and customization variables set before their package loads.
  - `declare-function` for third-party functions called from this config.
  - a structural `require` for built-ins used directly by helper functions.
- During `emacs --batch -Q` byte-compilation, `Cannot load PACKAGE` is expected for third-party packages absent from the clean load path. Do not confuse that with warnings caused by code in the edited file.

## User Overrides

- `custom.el` is an explicit user-override layer loaded before modules.
- Keep failures visible and easy to inspect.
- Do not silently move user-facing configuration out of `defcustom` or `.orgseq/` files.

## Private Configuration Scope

This repository is the user's private Emacs configuration. Do not harden away intentional personal choices such as automatic updates, unconfirmed Babel execution, or unpinned GitHub packages unless the user explicitly asks.
