---
name: add-package
description: Add a new Emacs package to the org-seq configuration with proper use-package declaration
user_invocable: true
args: package_name - the name of the package to add
---

# Add Package

Add a new Emacs package to the org-seq configuration following project conventions.

## Steps

1. Research the package: check its source (GNU ELPA, MELPA, or GitHub), dependencies, and any known Windows issues
2. Determine which module file (`lisp/init-*.el`) it belongs in based on its purpose (load order: see `CLAUDE.md` / `init.el`):
   - `init-ui.el` — fonts, themes, modeline, olivetti, icons
   - `init-completion.el` — Vertico stack, consult, embark
   - `init-markdown.el` — Markdown, preview, TOC
   - `init-org.el` — Org base: org-modern, evil-org, babel, **local leader** (org-mode-map only); not GTD-specific
   - `init-roam.el` — org-roam, org-node/org-mem, dailies, capture templates, org-roam-ui hooks
   - `init-gtd.el` — GTD dashboard, `org-agenda-custom-commands`, state machine, inbox/today hooks, **org-ql** dashboard queries
   - `init-pkm.el` — **org-supertag** (lazy/sync), org-transclusion, org-ql extras; after roam + gtd where IDs and helper fns exist
   - `init-ai.el` — gptel, ob-gptel, PKM AI helpers
   - `init-dashboard.el` — startup dashboard
   - `init-workspace.el` — treemacs, outline, terminal layout
   - `init-evil.el` — Evil, **global** `SPC` / `M-SPC` leader, magit, casual, which-key
3. Write a `use-package` declaration following these conventions:
   - Use `:after` for dependencies
   - Use `:hook` for mode activation
   - Use `:custom` for setq where possible
   - Use `:bind` for keybindings
   - Add `:demand t` only if immediate loading is required
   - Prefix custom functions with `my/`
   - Add Windows-specific notes with `;;` comments and ⚠️ marker
4. If the package needs leader key bindings, add them in `init-evil.el` under the appropriate SPC group
5. Run byte-compile on changed files, or `/elisp-lint` on the whole repo (`emacs --batch -Q -L . -L lisp -f batch-byte-compile …`)
6. If adding a dependency users must install manually, update `org-seq-build.md` package table and any troubleshooting rows in `CLAUDE.md`
