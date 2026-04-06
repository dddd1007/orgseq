# org-seq: Emacs PKM Configuration System

A modular Emacs configuration for building a personal knowledge management (PKM) system, centered on org-roam with Zettelkasten methodology. Primary target: Windows (with cross-platform compatibility).

## Project Overview

This project produces a deployable `~/.emacs.d/` configuration. The output is Emacs Lisp — not a standalone application. The config targets **Emacs 29+** (required for built-in SQLite and use-package).

### Core Stack
- **Editing**: Evil mode (Vim keybindings) + general.el (SPC leader keys)
- **Completion**: Vertico + Orderless + Consult + Marginalia + Embark
- **PKM Engine**: org-roam (Zettelkasten) + org-transclusion + org-ql
- **UI**: doom-themes + doom-modeline + org-modern + nerd-icons
- **Fonts**: CJK mixed typesetting (set-fontset-font + face-font-rescale-alist)

### Directory Layout
```
org-seq/
├── CLAUDE.md              # This file
├── org-seq-build.md       # Research & reference guide (read-only)
├── early-init.el          # Pre-GUI: GC suppression, UI blocking, native-comp
├── init.el                # Bootstrap: package.el, use-package, module loading
├── lisp/
│   ├── init-ui.el         # Fonts, themes, modeline (loaded 1st)
│   ├── init-completion.el # Vertico stack (loaded 2nd)
│   ├── init-org.el        # Org-mode base + org-modern + evil-org (loaded 3rd)
│   ├── init-roam.el       # org-roam + capture templates + dailies (loaded 4th)
│   ├── init-pkm.el        # org-transclusion + org-ql (loaded 5th)
│   └── init-evil.el       # Evil + evil-collection + general.el + which-key + magit (loaded last)
├── .claude/
│   ├── settings.local.json # Permissions for Claude Code
│   └── skills/
│       ├── elisp-lint.md      # /elisp-lint — batch byte-compile all .el files
��       ├── add-package.md     # /add-package — add new package following conventions
│       ├── deploy-config.md   # /deploy-config — deploy to ~/.emacs.d/
│       └── check-windows-deps.md # /check-windows-deps — verify external deps
├── README.md              # Quick start and usage guide
├── LICENSE                # MIT license
├── snippets/              # YASnippet templates (future)
└── templates/             # org-roam capture template files (future)
```

## Code Conventions

### Elisp Style
- Always use `lexical-binding: t` in file headers: `;;; file.el --- description -*- lexical-binding: t; -*-`
- Every module file must end with `(provide 'init-MODULE)`
- Use `use-package` for all package configuration — no bare `require` except for built-ins
- Use `:demand t` on core packages (evil, vertico, org, org-roam, themes); omit for optional/lazy packages
- Prefix all custom functions/variables with `my/` (e.g., `my/setup-fonts`, `my/org-roam-rg-search`)
- Use `:custom` in use-package for `setq` where possible; use `:config` for imperative setup

### Windows Compatibility (Critical)
- **Paths**: Always use forward slashes `/` in elisp. Use `file-truename` for org-roam directories.
- **Encoding**: Enforce `utf-8-unix` everywhere to avoid CRLF issues.
- **External tools**: consult-ripgrep needs `rg.exe`, consult-find needs `fd.exe`. Check with `executable-find`.
- **Process performance**: Set `read-process-output-max` to 1MB, `w32-pipe-read-delay` to 0.
- **find.exe conflict**: Windows `find.exe` != Unix find. Configure consult to use fd.
- **Font installation**: nerd-icons fonts must be manually installed on Windows (right-click .ttf).
- **Server mode**: Use `server-use-tcp t` on Windows (no Unix domain sockets).

### Cross-Platform Pattern
```elisp
(when (eq system-type 'windows-nt)
  ;; Windows-specific settings
  )
(when (eq system-type 'gnu/linux)
  ;; Linux-specific settings
  )
(when (eq system-type 'darwin)
  ;; macOS-specific settings
  )
```

## Development Workflow

### Testing Config Changes
1. Byte-compile check: `emacs --batch -f batch-byte-compile <file>.el`
2. Load test: `emacs -Q -l early-init.el -l init.el`
3. Startup time: `emacs --eval="(message \"%s\" (emacs-init-time))"`

### Adding a New Package
1. Add `use-package` declaration in the appropriate `lisp/init-*.el` module
2. Use `:after` for dependencies, `:hook` for mode activation
3. Add Windows-specific notes as comments with `⚠️` prefix
4. Add leader key bindings in `init-evil.el` if needed
5. Update the package table in `org-seq-build.md` if it's a new dependency

### Adding a New Module
1. Create `lisp/init-<name>.el` with proper header and `(provide 'init-<name>)`
2. Add `(require 'init-<name>)` in `init.el` — **load order matters**: UI/completion -> org stack -> evil (last, needs org for evil-org)
3. Update the directory layout section in this file

### Module Load Order (init.el)
```
init-ui -> init-completion -> init-org -> init-roam -> init-pkm -> init-evil
```
- `init-evil` loads last because `evil-org` (in init-org) uses `:after (org evil)`
- `init-org` before `init-roam` because org-roam depends on org
- `init-pkm` before `init-evil` because leader keys reference `my/org-roam-rg-search`

### Claude Code Skills
- `/elisp-lint` — Byte-compile check all `.el` files, report errors
- `/add-package` — Add a new Emacs package following project conventions
- `/deploy-config` — Copy config to `~/.emacs.d/` with safety checks
- `/check-windows-deps` — Verify Emacs version, SQLite, rg, fd, etc.

## Key Design Decisions

- **package.el over straight.el**: Emacs 29+ has `package-vc-install` for git sources. Simpler for our config size.
- **Flat org-roam structure**: org-roam uses ID links (not file paths), so folders add no value. Only `daily/`, `lit/`, `concepts/` as subdirs.
- **No GCMH**: Direct `gc-cons-threshold` (16MB) is safer than gcmh's timer-based approach.
- **org-modern over org-superstar**: org-modern uses text properties (more efficient), actively maintained by Daniel Mendler.
- **org-supertag is experimental**: Included but behind awareness — frequent API changes, not on MELPA.

## Troubleshooting Quick Reference

| Symptom | Check |
|---------|-------|
| org-roam won't start | `M-: (sqlite-available-p)` must return `t` |
| No native-comp | `M-: (native-comp-available-p)`, need MSYS2 build |
| Chinese fonts broken | `M-: (font-family-list)` to verify font names |
| ripgrep not found | `M-: (executable-find "rg")`, install via winget/scoop |
| Slow startup | `M-x esup` or `M-x benchmark-init/show-durations-tabulated` |
