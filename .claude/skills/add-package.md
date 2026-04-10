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
   - `init-org.el` — Org base: org-modern, org-appear, org-tempo, evil-org, babel, **local leader** (org-mode-map only); not GTD-specific; also defines the root path constants (`my/note-home`, `my/roam-dir`, `my/orgseq-dir`)
   - `init-roam.el` — org-roam, org-node/org-mem, dailies, capture templates, org-roam-ui hooks, Doom-derived Evil/vertico advices
   - `init-gtd.el` — GTD dashboard, `org-agenda-custom-commands`, state machine, inbox/today hooks, **org-ql** dashboard queries
   - `init-pkm.el` — **org-supertag** (bootstrap install + use-package), org-transclusion, org-ql; after roam + gtd where IDs and helper fns exist
   - `init-supertag.el` — supertag schema/dashboard/PARA navigation; depends on `my/roam-dir` from init-org
   - `init-ai.el` — gptel, ob-gptel, claude-code, PKM AI helpers, .orgseq ai-config parsing
   - `init-dashboard.el` — startup dashboard (emacs-dashboard + custom quotes + vertical centering)
   - `init-dired.el` — **dired + dirvish** (override mode, peek, quick-access); defines sidebar helpers consumed by init-workspace
   - `init-workspace.el` — 3-column layout using dirvish-side + imenu-list + eshell; depends on init-dired's sidebar helpers
   - `init-evil.el` — Evil, **global** `SPC` / `M-SPC` leader, magit, casual, which-key
3. Write a `use-package` declaration following these conventions:
   - Use `:after` for dependencies
   - Use `:hook` for mode activation
   - Use `:custom` for setq where possible
   - Use `:bind` for keybindings
   - Add `:demand t` only if immediate loading is required
   - Prefix custom functions with `my/`
   - Add Windows-specific notes with `;;` comments and ⚠️ marker
4. If the package needs leader key bindings, add them in `init-evil.el` under the appropriate SPC group; if the package adds an org-mode local action, register it under `,` in `init-org.el`
5. The PostToolUse hook auto-byte-compiles each `.el` on save — watch for `[hook] FAILED` lines and fix immediately. Run `/elisp-lint` if you want a full-repo verification
6. If adding a runtime dependency users must install manually (e.g. an external binary), add a troubleshooting row to `CLAUDE.md` and a prerequisite to `README.md`
7. If the package needs an extra Windows path/exec adjustment, follow the pattern in `init.el` (`exec-path` block for WinGet/Scoop) rather than scattering platform conditionals across modules
