---
globs: ["*.el", "lisp/*.el"]
---

# Elisp Style Rules

- Always use `lexical-binding: t` in file headers
- Every module file must end with `(provide 'init-MODULE)`
- Use `use-package` for all package configuration
- Prefix all custom functions/variables with `my/` (e.g., `my/setup-fonts`)
- Use `my/module--helper` for private functions (double dash)
- Use `defcustom` (not `defvar`) for user-customizable settings, with `:type` and `:group 'org-seq`
- Forward-declare cross-module variables with `(defvar my/varname)` at file top
- Add `; Requires: init-xxx (variable-list)` comment at file top for cross-module dependencies
- Section headers use `═══` for major sections, `----` for subsections
- Windows compatibility: use forward slashes in paths, `file-truename` for org-roam dirs
- After editing any .el file, byte-compile check must pass before committing
