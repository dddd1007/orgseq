# org-seq: Emacs PKM Configuration System

A modular Emacs configuration for building a personal knowledge management (PKM) system, centered on org-roam with Zettelkasten methodology. Primary target: Windows (with cross-platform compatibility).

## Project Overview

This project produces a deployable `~/.emacs.d/` configuration. The output is Emacs Lisp — not a standalone application. The config targets **Emacs 29+** (required for built-in SQLite and use-package). Org-mode is installed from GNU ELPA (not the built-in version) for latest features.

### Core Stack
- **Editing**: Evil mode (Vim keybindings) + general.el (SPC leader keys)
- **Org**: org-mode (from GNU ELPA) + org-modern + evil-org + GTD dashboard
- **Markdown**: markdown-mode + markdown-toc (preview/export/TOC workflow)
- **Completion**: Vertico + Orderless + Consult + Marginalia + Embark
- **PKM Engine**: org-supertag (data layer) + org-roam (graph layer) + org-node/org-mem (performance layer) + org-transclusion + org-ql
- **AI**: gptel (LLM client, OpenRouter) + ob-gptel (org-babel AI blocks) + purpose/schema context injection + KB overview generation
- **Menus**: casual (Transient keyboard-driven menus for built-in modes)
- **UI**: modus-themes (default) + doom-modeline + nerd-icons + olivetti
- **Fonts**: CJK mixed typesetting (set-fontset-font + face-font-rescale-alist)

### Directory Layout
```
org-seq/
├── CLAUDE.md              # This file
├── org-seq-build.md       # Research & reference guide (read-only)
├── WORKFLOW.md            # Day-to-day GTD / roam habits (user-oriented)
├── early-init.el          # Pre-GUI: GC suppression, UI blocking, native-comp
├── init.el                # Bootstrap: package.el, use-package, module loading
├── .gitattributes         # Line ending rules (LF for .el, CRLF for .ps1)
├── lisp/
│   ├── init-ui.el         # Fonts, themes, modeline, olivetti (loaded 1st)
│   ├── init-completion.el # Vertico stack (loaded 2nd)
│   ├── init-markdown.el   # Markdown mode + TOC + preview/export (loaded 3rd)
│   ├── init-org.el        # Org-mode base config + org-modern + evil-org (loaded 4th)
│   ├── init-roam.el       # org-roam + org-node acceleration + capture + dailies (loaded 5th)
│   ├── init-gtd.el        # GTD system: dashboard, agenda views, state machine (loaded 6th)
│   ├── init-pkm.el        # org-supertag (core) + org-transclusion + org-ql (loaded 7th)
│   ├── init-ai.el         # gptel + ob-gptel + .orgseq AI config + PKM AI commands + KB overview (loaded 8th)
│   ├── init-dashboard.el  # Startup dashboard with vertical centering (loaded 9th)
│   ├── init-workspace.el  # Workspace layout: treemacs + outline + terminal (loaded 10th)
│   ├── init-evil.el       # Evil + general.el + which-key + magit + casual (loaded last)
│   └── banner-compact.txt # ASCII art banner for dashboard
├── .claude/
│   ├── settings.local.json # Permissions for Claude Code (not committed)
│   └── skills/
│       ├── elisp-lint.md      # /elisp-lint — batch byte-compile all .el files
│       ├── add-package.md     # /add-package — add new package following conventions
│       ├── deploy-config.md   # /deploy-config — deploy to ~/.emacs.d/
│       └── check-windows-deps.md # /check-windows-deps — verify external deps
├── deploy.ps1             # Windows deployment script (PowerShell)
├── deploy.sh              # Linux/macOS deployment script (Bash)
├── README.md              # Quick start and usage guide
├── LICENSE                # MIT license
├── snippets/              # YASnippet templates (future)
└── templates/             # org-roam capture template files (future)

~/NoteHQ/
└── .orgseq/               # Per-library personalized config (like .vscode/)
    └── ai-config.org      # AI backends, models, defaults (API keys stay in ~/.authinfo.gpg)
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
- **Encoding**: Enforce `utf-8-unix` on Windows to avoid CRLF issues (cross-platform via `.gitattributes`).
- **External tools**: consult-ripgrep needs `rg.exe`, consult-find needs `fd.exe`. Check with `executable-find`.
- **Process performance**: Set `read-process-output-max` to 1MB, `w32-pipe-read-delay` to 0, `w32-pipe-buffer-size` to 64KB.
- **find.exe conflict**: Windows `find.exe` != Unix find. Configure consult to use fd.
- **Font installation**: nerd-icons fonts must be manually installed on Windows (right-click .ttf).
- **Server mode**: Use `server-use-tcp t` on Windows (no Unix domain sockets).
- **Package upgrades**: `package-install-upgrade-built-in` is set to `t` to allow upgrading Org and Transient from ELPA.

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
1. Byte-compile check: `emacs --batch -Q -L . -L lisp -f batch-byte-compile <file>.el`
2. Load test (from repo root): `emacs -Q --eval "(setq user-emacs-directory default-directory)" -l early-init.el -l init.el`
3. Startup time (deployed): `emacs --eval "(message \"%s\" (emacs-init-time))"`

### Adding a New Package
1. Add `use-package` declaration in the appropriate `lisp/init-*.el` module
2. Use `:after` for dependencies, `:hook` for mode activation
3. Add Windows-specific notes as comments with `⚠️` prefix
4. Add leader key bindings in `init-evil.el` if needed
5. Update the package table in `org-seq-build.md` if it's a new dependency

### Adding a New Module
1. Create `lisp/init-<name>.el` with proper header and `(provide 'init-<name>)`
2. Add `(require 'init-<name>)` in `init.el` — **load order matters**
3. Update the directory layout section in this file

### Module Load Order (init.el)
```
init-ui -> init-completion -> init-markdown -> init-org -> init-roam -> init-gtd -> init-pkm -> init-ai -> init-dashboard -> init-workspace -> init-evil
```
- `init-evil` loads last because `evil-org` (in init-org) uses `:after (org evil)`
- `init-org` before `init-roam` because org-roam depends on org; defines `my/note-home` and `my/orgseq-dir` used by later modules
- `init-roam` before `init-gtd` because GTD agenda cache can use org-mem's async file list
- `init-gtd` before `init-pkm` because GTD functions must exist before supertag bindings reference them
- `init-pkm` after `init-gtd` because org-supertag uses org-id set up by org-roam, and org-ql is used by GTD dashboard
- `init-ai` after `init-pkm` because org-supertag's AI bridge uses gptel
- `init-dashboard` after `init-roam` because it needs org-roam and nerd-icons to be ready
- `init-workspace` after `init-dashboard` because startup layout displays the dashboard buffer

### Scope: Agenda vs PKM Directories
- `my/note-home` (`~/NoteHQ/`): Broad scope for GTD agenda scanning (all org files including non-roam)
- `org-roam-directory` / `org-mem-watch-dirs` / `org-supertag-sync-directories` (`~/NoteHQ/Roam/`): Scoped to structured PKM notes with org-id
- When org-mem is active, the agenda cache uses org-mem's file list (Roam/ only) for speed; falls back to full NoteHQ scan otherwise
- GTD task files should live under `~/NoteHQ/Roam/` to be indexed by all three PKM layers

### Claude Code Skills (`.claude/skills/`)
Slash commands are defined there for Claude Code; use them when the task matches.

| Skill | Purpose |
|-------|---------|
| `/elisp-lint` | Batch byte-compile all `early-init.el`, `init.el`, `lisp/*.el`; report errors |
| `/add-package` | Add a `use-package` block in the correct `init-*.el`, keys in `init-evil` if needed |
| `/deploy-config` | Deploy to `~/.emacs.d/` with backup/safety; do not overwrite without confirmation |
| `/check-windows-deps` | Emacs 29+, SQLite, native-comp, rg, fd, git, HOME |

After changing elisp, run `/elisp-lint` before considering work done.

## Key Design Decisions

- **package.el over straight.el**: Emacs 29+ has `package-vc-install` for git sources. Simpler for our config size.
- **Org from ELPA**: `package-install-upgrade-built-in` enables installing latest Org from GNU ELPA independently of Emacs version.
- **NoteHQ directory layout**: All notes live under `~/NoteHQ/`. org-roam uses `~/NoteHQ/Roam/` (with `daily/`, `lit/`, `concepts/` subdirs). Other subdirectories under NoteHQ can hold non-roam notes; GTD agenda scans the entire NoteHQ tree.
- **Three-layer PKM architecture**: Designed for Tana-style database workflows at scale.
  - **org-supertag** (data layer): Core structured data engine. Turns `#tags` into database tables with typed fields. Provides queries, table views, kanban boards, and automation. Migrated from Tana's supertag concept. Not on MELPA; installed from GitHub.
  - **org-roam** (graph layer): Zettelkasten graph — nodes, links, backlinks, capture templates, dailies. Provides the node identity system (org-id) shared by all layers.
  - **org-node + org-mem** (performance layer): Async hash-table indexing (~2s for 3000 nodes vs org-roam's 2m48s). Accelerates backlinks, search, and DB sync. `org-mem-roamy-db-mode` feeds org-roam's SQLite DB so org-roam-ui works.
- **No md-roam**: Markdown support removed in favor of pure Org. md-roam conflicts with org-node's indexing. All notes are Org-only; Obsidian compatibility is no longer a goal.
- **No GCMH**: Direct `gc-cons-threshold` (16MB) is safer than gcmh's timer-based approach.
- **org-modern over org-superstar**: org-modern uses text properties (more efficient), actively maintained by Daniel Mendler.
- **org-supertag as core**: v5.8+ is stable (336 stars, pure Elisp, ~16K LOC). Demand-loaded in init-pkm.el. Sync directory matches org-roam's `~/NoteHQ/Roam/`. AI bridge enabled via gptel. First-time setup requires `M-x supertag-sync-full-initialize`.
- **AI purpose/schema context** (inspired by llm_wiki): Two persistent org files — `~/NoteHQ/Roam/concepts/purpose.org` (knowledge base goals, key questions) and `~/NoteHQ/Roam/concepts/schema.org` (note types, tag conventions, linking rules) — are auto-injected into every gptel system prompt via `my/ai--build-system-prompt`. This gives the LLM persistent context about the user's PKM without manual repetition. Files are created with templates on first load (`SPC i g` or `my/ai--ensure-context-files`). Edit them to customize AI behavior.
- **KB overview generation**: `my/ai-overview` (`SPC i o`) collects org-roam statistics (total nodes, tag distribution, recent notes) and asks the LLM to generate a structured overview report (themes, gaps, connections, suggestions). Result is saved to `~/NoteHQ/Roam/concepts/overview.org` with timestamp. Inspired by llm_wiki's auto-updated overview.md.
- **Workspace layout**: Default startup opens treemacs + dashboard (lightweight). Full 3-column layout (treemacs + outline + terminal) is on-demand via `SPC l l`.
- **.orgseq personalized config**: `~/NoteHQ/.orgseq/` stores non-sensitive per-library settings (like `.vscode/`). First use case: `ai-config.org` — AI backend definitions, model lists, and defaults in an editable org file. API keys remain in `~/.authinfo.gpg` (auth-source). Init is incremental: files are created with templates only if missing, never overwritten. Parsed at gptel load time with hardcoded fallback on failure.

## Troubleshooting Quick Reference

| Symptom | Check |
|---------|-------|
| org-roam won't start | `M-: (sqlite-available-p)` must return `t` |
| No native-comp | `M-: (native-comp-available-p)`, need MSYS2 build |
| Chinese fonts broken | `M-: (font-family-list)` to verify font names |
| ripgrep not found | `M-: (executable-find "rg")`, install via package manager |
| Slow startup | `M-x esup` or `M-x benchmark-init/show-durations-tabulated` |
| org-node cache stale | `M-x org-mem-reset` to force full rescan |
| org-roam-ui graph incomplete | Check `org-mem-roamy-do-overwrite-real-db` is `t` |
| supertag data missing | `M-x supertag-sync-full-initialize` (one-time rebuild) |
| supertag fields not syncing | `M-x supertag-sync-check-now` or check `supertag-sync-status` |
| supertag install failed | Run `(package-vc-install "https://github.com/yibie/org-supertag")` manually |
| Transient version too old | Verify `package-install-upgrade-built-in` is `t` |
| claude-code won't start | Ensure `claude` CLI is on PATH: `M-: (executable-find "claude")` |
| claude-code garbled display | Try switching backend: `(setq claude-code-terminal-backend 'vterm)` (needs libvterm) |
