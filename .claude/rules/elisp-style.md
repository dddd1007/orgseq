---
globs: ["lisp/*.el", "early-init.el", "init.el"]
---

# Elisp Style Rules (org-seq config modules)

> Scope: this rule covers the **org-seq config itself** — `early-init.el`, `init.el`, and the `lisp/init-*.el` module files. Bundled subprojects under `packages/` follow different conventions; see [`packages-style.md`](packages-style.md).

## File structure
- Always use `lexical-binding: t` in file headers
- Every module file must end with `(provide 'init-MODULE)`
- Use `use-package` for all package configuration
- Add `; Requires: init-xxx (variable-list)` comment at file top for cross-module dependencies
- Forward-declare cross-module variables with `(defvar my/varname)` at file top

## Naming
- Prefix all custom functions/variables with `my/` (e.g., `my/setup-fonts`)
- Use `my/module--helper` for private functions (double dash)
- Use `defcustom` (not `defvar`) for user-customizable settings, with `:type` and `:group 'org-seq`

## Section headers
- Major sections: a line of `═` (U+2550) — e.g. `;; ═══════════════`
- Subsections: a line of `─` (U+2500) or `;; ----`
- Box-drawing characters (`═ ─ ┌ ┐ │`) are allowed in comments and the dashboard banner
- Section heading style should be consistent within a single file

## Character set discipline (Windows-safe)
- **NO emoji** (U+1F300+ and friends like ⚠️ 🔴 ✓ 📝) anywhere in elisp source — including strings and comments. Past incident: emoji in strings broke parsing on some Windows Emacs builds (commit `200854b`). Use ASCII text instead: `WARNING`, `ERROR`, `[ok]`, `note:`.
- **NO fullwidth punctuation** (`，。；：（）【】"""''`) in code, strings, or comments. They cause inconsistent rendering in TTY mode and on legacy Windows code pages. Use ASCII `, . ; : ( ) [ ] " "` and let CJK content live in user-edited org files, not config source.
- **OK in source**: ASCII, box-drawing chars (above), em-dash `—`, ellipsis `…`, smart quotes `' '` are tolerable in comments but not preferred. When in doubt, use ASCII.
- The PostToolUse byte-compile hook will catch parse errors immediately, but rendering / locale issues are silent — prefer ASCII to avoid them entirely.

## Cross-platform paths
- Use forward slashes `/` in elisp paths (Emacs normalizes on Windows)
- Use `file-truename` for paths that go to org-roam, org-mem, or org-supertag (resolves Windows 8.3 short names and case differences)
- Path constants derived from `my/note-home` should live in `init-org.el` so all modules can reference them via forward-declare

## Validation
- After editing any .el file, byte-compile must pass (PostToolUse hook handles this automatically)
- Run `/elisp-lint` for full-repo verification before committing or pushing
- The PreToolUse `git commit` hook will block any commit with byte-compile errors
