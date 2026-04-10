# org-seq: Emacs PKM Configuration System

A modular Emacs configuration for building a personal knowledge management (PKM) system, centered on org-roam with Zettelkasten methodology. Primary target: Windows (with cross-platform compatibility).

## Project Overview

This project produces a deployable `~/.emacs.d/` configuration. The output is Emacs Lisp — not a standalone application. The config targets **Emacs 29+** (required for built-in SQLite and use-package). Org-mode is installed from GNU ELPA (not the built-in version) for latest features.

### Core Stack
- **Editing**: Evil mode (Vim keybindings) + general.el (SPC leader keys)
- **Org**: org-mode (from GNU ELPA) + org-modern + evil-org + GTD dashboard
- **Markdown**: markdown-mode + markdown-toc (editing with Obsidian interop, not indexed by org-roam)
- **Completion**: Vertico + Orderless + Consult + Marginalia + Embark
- **PKM Engine**: org-supertag (data layer) + org-roam (graph layer) + org-node/org-mem (performance layer) + org-transclusion + org-ql
- **AI**: gptel (LLM client, OpenRouter) + ob-gptel (org-babel AI blocks) + purpose/schema context injection + KB overview generation
- **Menus**: casual (Transient keyboard-driven menus for built-in modes)
- **UI**: modus-themes (default) + doom-modeline + nerd-icons + olivetti
- **Fonts**: CJK mixed typesetting (set-fontset-font + face-font-rescale-alist)

### Directory Layout
```
org-seq/
├── CLAUDE.md              # This file — development guidelines for Claude Code
├── README.md              # Quick start and key bindings (user-facing)
├── LICENSE                # MIT license
├── early-init.el          # Pre-GUI: GC suppression, UI blocking, native-comp
├── init.el                # Bootstrap: package.el, use-package, module loading
├── ec.cmd                 # Windows quick-launch: emacsclient -c -a ""
├── deploy.ps1             # Windows deployment script (PowerShell)
├── deploy.sh              # Linux/macOS deployment script (Bash)
├── .gitattributes         # Line ending rules (LF for .el, CRLF for .ps1)
├── doc/
│   ├── GUIDE.md           # Long-form user guide (architecture + rationale)
│   ├── WORKFLOW.md        # Day-to-day GTD / roam habits (user-oriented)
│   └── NOTES_ARCHITECTURE.md # Roam + PARA design rationale (read-only)
├── lisp/
│   ├── init-ui.el         # Fonts, themes, modeline, olivetti (loaded 1st)
│   ├── init-completion.el # Vertico stack (loaded 2nd)
│   ├── init-markdown.el   # Markdown editing with Obsidian interop, not in org-roam (loaded 3rd)
│   ├── init-org.el        # Org-mode base + org-modern + org-appear + org-tempo + evil-org (loaded 4th)
│   ├── init-roam.el       # org-roam + org-node acceleration + capture + dailies + Doom-derived advices (loaded 5th)
│   ├── init-gtd.el        # GTD system: dashboard, agenda views, state machine (loaded 6th)
│   ├── init-focus.el      # org-focus-timer integration (Vitamin-R-style focus slices) (loaded 7th)
│   ├── init-pkm.el        # org-supertag (install) + org-transclusion + org-ql (loaded 8th)
│   ├── init-supertag.el   # Supertag schema/dashboard/PARA nav + NoteHQ bootstrap (loaded 9th)
│   ├── init-ai.el         # gptel + ob-gptel + .orgseq AI config + PKM AI commands + KB overview (loaded 10th)
│   ├── init-dashboard.el  # Startup dashboard with vertical centering (loaded 11th)
│   ├── init-dired.el      # Dired + dirvish (sidebar, override-dired, peek, quick-access) (loaded 12th)
│   ├── init-workspace.el  # Workspace layout: dirvish-side + imenu-list outline + eshell terminal (loaded 13th)
│   ├── init-evil.el       # Evil + general.el + which-key + magit + casual (loaded last)
│   ├── dashboard-quotes.el # Data-only file: `my/dashboard-quotes' list consumed by init-dashboard.el
│   └── banner-compact.txt # ASCII art banner for dashboard
├── .claude/
│   ├── settings.json      # Hooks: PostToolUse byte-compile, PreToolUse pre-commit lint
│   ├── settings.local.json # Permissions for Claude Code (not committed)
│   ├── rules/
│   │   ├── elisp-style.md     # Scoped to lisp/*.el — org-seq module conventions (my/ prefix, defgroup org-seq, ...)
│   │   ├── packages-style.md  # Scoped to packages/**/*.el — bundled-subproject conventions (package-local prefix, own defgroup)
│   │   └── org-conventions.md # Scoped to *.org — note structure rules
│   └── skills/
│       ├── elisp-lint.md      # /elisp-lint — batch byte-compile lisp/ + packages/
│       ├── add-package.md     # /add-package — add new package (module OR bundled subproject)
│       ├── deploy-config.md   # /deploy-config — deploy to ~/.emacs.d/ (includes packages/)
│       └── check-windows-deps.md # /check-windows-deps — verify external deps
├── notehq/                # Claude Code scaffolding deployed to ~/NoteHQ/ by bootstrap script
│   ├── CLAUDE.md          # Per-NoteHQ guidance (note conventions, supertag schema)
│   └── .claude/
│       ├── rules/         # org-notes.md, supertag-schema.md
│       └── skills/        # archive-project, new-dashboard, new-tag, new-template, weekly-review
├── packages/              # Bundled subprojects (copied to ~/.emacs.d/packages/ by deploy)
│   └── org-focus-timer/   # Vitamin-R-style focus timer (will graduate to its own repo when mature)
│       ├── org-focus-timer.el
│       └── README.md
└── scripts/
    ├── bootstrap-notes.sh   # Init ~/NoteHQ/ structure + copy notehq/ scaffold (Linux/macOS)
    └── bootstrap-notes.ps1  # Init ~/NoteHQ/ structure + copy notehq/ scaffold (Windows)

~/NoteHQ/                    # Created by bootstrap script or init-supertag
├── Roam/                    # Atomic layer (org-roam-directory)
│   ├── daily/               # Daily notes
│   ├── capture/             # All captured notes (flat, timestamp-prefixed)
│   ├── dashboards/          # Query-only dashboard files
│   └── supertag-schema.el   # Tag definitions
├── Outputs/                 # PARA: deliverable projects
├── Practice/                # PARA: long-term responsibility domains
├── Library/                 # PARA: reference materials
├── Archives/                # Completed/paused work
└── .orgseq/                 # Per-library personalized config (like .vscode/)
    └── ai-config.org        # AI backends, models, defaults
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
5. The PostToolUse hook will byte-compile the file on save; run `/elisp-lint` for full-repo verification before commit

### Adding a New Module
1. Create `lisp/init-<name>.el` with proper header and `(provide 'init-<name>)`
2. Add `(require 'init-<name>)` in `init.el` — **load order matters**
3. Update the directory layout section in this file

### Module Load Order (init.el)
```
init-ui -> init-completion -> init-markdown -> init-org -> init-roam -> init-gtd -> init-focus -> init-pkm -> init-supertag -> init-ai -> init-dashboard -> init-dired -> init-workspace -> init-evil
```
- `init-org` before `init-roam` because org-roam depends on org; defines `my/note-home`, `my/orgseq-dir`, `my/roam-dir` used by later modules
- `init-roam` before `init-gtd` because GTD agenda cache can use org-mem's async file list
- `init-gtd` before `init-focus` because focus-timer is conceptually adjacent to GTD (both are time/productivity features)
- `init-focus` before `init-pkm` because focus-timer is a thin external-package reference with no dependencies on supertag; grouping it next to GTD keeps the productivity stack together
- `init-pkm` before `init-supertag` because pkm installs org-supertag, supertag loads schema and provides higher-level functions
- `init-supertag` before `init-ai` because supertag's AI bridge uses gptel; supertag also ensures NoteHQ directory structure
- `init-dashboard` after `init-roam` because it needs org-roam and nerd-icons to be ready
- `init-dired` after `init-dashboard` because it depends on `nerd-icons` (loaded in `init-ui`) and `my/roam-dir` (from `init-org`); defines `my/dirvish-side-*` helpers consumed by `init-workspace`
- `init-workspace` after `init-dired` because the sidebar is provided by `dirvish-side` via helpers in `init-dired`
- `init-evil` loads last because general.el leader keys reference all other modules

### NoteHQ Architecture: Roam + PARA
```
~/NoteHQ/
├── Roam/                  ← Atomic layer (org-roam-directory), flat except:
│   ├── daily/             ← Daily notes
│   ├── capture/           ← All captured notes (timestamp-prefixed)
│   ├── dashboards/        ← Query-only dashboard files
│   └── supertag-schema.el ← Tag definitions (version-controlled with notes)
├── Outputs/               ← PARA: deliverable projects (bounded lifetime)
├── Practice/              ← PARA: long-term responsibility domains
├── Library/               ← PARA: reference materials (consumed, not maintained)
├── Archives/              ← Completed/paused work
└── .orgseq/               ← Per-library personalized config
```

### Scope: Agenda vs PKM vs PARA
- `my/note-home` (`~/NoteHQ/`): Root directory for all layers
- `org-roam-directory` / `org-mem-watch-dirs` / `org-supertag-sync-directories` (`~/NoteHQ/Roam/`): Atomic notes only
- GTD agenda scans `Roam/` + `Outputs/` + `Practice/` (not Library/ or Archives/)
- Classification is by supertag, not directory. Roam/capture/ is flat.

### Claude Code Hooks (`.claude/settings.json`)
Two automatic hooks run without user invocation:

- **PostToolUse** (matcher `Write|Edit`): on every `.el` file edit, runs `emacs --batch -Q -L . -L lisp --eval "(byte-compile-file ...)"` on the single changed file and reports `[hook] OK` or `[hook] FAILED`. This works for files under both `lisp/` and `packages/**/` because single-file byte-compilation doesn't need the full load path when the package is self-contained (as `org-focus-timer` is).
- **PreToolUse** (matcher `Bash(git commit*)`): before any `git commit`, byte-compiles every `.el` in the repo — specifically `early-init.el`, `init.el`, `lisp/*.el`, and `packages/*/*.el` — with a load path that dynamically picks up every `packages/*/` subdirectory. Blocks the commit if any file fails. This is the full-repo gate.

Together they mean per-edit feedback + commit-time enforcement, so manual `/elisp-lint` invocation is only needed when you want to verify the whole repo mid-session.

### Claude Code Rules (`.claude/rules/`)
Auto-loaded scoped guidance via the `globs:` frontmatter. The scopes are **mutually exclusive** so the same file never matches two rules:

- **`elisp-style.md`** — scoped to `early-init.el` / `init.el` / `lisp/*.el`; enforces `lexical-binding`, `my/` prefix, `defcustom` with `:group 'org-seq`, section header style, character-set discipline (no emoji, no fullwidth punctuation).
- **`packages-style.md`** — scoped to `packages/**/*.el`; enforces the opposite conventions for bundled subprojects: package-local prefix (not `my/`), own `defgroup` (not `org-seq`), proper package header for standalone consumption, no references to org-seq paths or keybindings. The goal is that any `packages/<name>/` directory can be graduated to its own repo with `git mv` alone.
- **`org-conventions.md`** — scoped to `*.org` (includes `notehq/`); enforces `:ID:` properties, `[[id:...]]` linking, supertag-over-directory classification, dashboard write-protection, TODO sequence.

### Claude Code Skills (`.claude/skills/`)
Slash commands defined for Claude Code; use them when the task matches.

| Skill | Purpose |
|-------|---------|
| `/elisp-lint` | Batch byte-compile `early-init.el`, `init.el`, `lisp/*.el`, and `packages/*/*.el`; report errors. Complements the per-edit PostToolUse hook for full-repo verification. |
| `/add-package` | Add a new package — either as a `use-package` block inside `lisp/init-*.el` (for 3rd-party integrations) or as a new bundled subproject under `packages/<name>/` (for packages you are writing yourself). Covers both flows. |
| `/deploy-config` | Deploy to `~/.emacs.d/` with backup/safety; copies `lisp/` AND `packages/`; do not overwrite without confirmation. |
| `/check-windows-deps` | Emacs 29+, SQLite, native-comp, rg, fd, git, HOME. |

After changing elisp, the PostToolUse hook auto-lints; run `/elisp-lint` if you want a full-repo sanity check.

### NoteHQ Scaffolding (`notehq/`)
The `notehq/` subdirectory holds Claude Code support files that the bootstrap script copies into the user's `~/NoteHQ/` on first setup. Its own `CLAUDE.md`, rules, and skills are scoped to that runtime location — they are **not** loaded for org-seq development. Treat `notehq/` as a deliverable for end users, not as project guidance.

**Updating deployed scaffolding**: `scripts/bootstrap-notes.sh --update` (or `.\bootstrap-notes.ps1 -Update`) overwrites `~/NoteHQ/CLAUDE.md`, `~/NoteHQ/.claude/skills/*`, and `~/NoteHQ/.claude/rules/*` with the latest from the org-seq repo. User content (notes, schema, capture-templates.el, ai-config.org) is never touched. The helper compares hashes and only writes changed files, so re-running is idempotent. Whenever you ship changes to anything under `notehq/` in this repo, mention the user should re-run with `--update` to pick them up.

## Key Design Decisions

- **package.el over straight.el**: Emacs 29+ has `package-vc-install` for git sources. Simpler for our config size.
- **Org from ELPA**: `package-install-upgrade-built-in` enables installing latest Org from GNU ELPA independently of Emacs version.
- **NoteHQ directory layout**: Roam/ (atomic notes, flat except `daily/`, `capture/`, `dashboards/`) + PARA layers (`Outputs/`, `Practice/`, `Library/`, `Archives/`). Classification by supertag, not directory. GTD agenda scans Roam/ + Outputs/ + Practice/. See `doc/NOTES_ARCHITECTURE.md` for full design.
- **Three-layer PKM architecture**: Designed for Tana-style database workflows at scale.
  - **org-supertag** (data layer): Core structured data engine. Turns `#tags` into database tables with typed fields. Provides queries, table views, kanban boards, and automation. Migrated from Tana's supertag concept. Not on MELPA; installed from GitHub.
  - **org-roam** (graph layer): Zettelkasten graph — nodes, links, backlinks, capture templates, dailies. Provides the node identity system (org-id) shared by all layers.
  - **org-node + org-mem** (performance layer): Async hash-table indexing (~2s for 3000 nodes vs org-roam's 2m48s). Accelerates backlinks, search, and DB sync. `org-mem-roamy-db-mode` feeds org-roam's SQLite DB so org-roam-ui works.
- **No md-roam**: Markdown is editable with Obsidian interop (wiki links, GFM) but NOT indexed by org-roam. PKM graph/backlinks are Org-only. md-roam removed because it conflicts with org-node indexing.
- **No GCMH**: Direct `gc-cons-threshold` (16MB) is safer than gcmh's timer-based approach.
- **org-modern over org-superstar**: org-modern uses text properties (more efficient), actively maintained by Daniel Mendler.
- **org-supertag as core**: v5.8+ is stable (336 stars, pure Elisp, ~16K LOC). Demand-loaded in init-pkm.el. Sync directory matches org-roam's `~/NoteHQ/Roam/`. AI bridge enabled via gptel. First-time setup requires `M-x supertag-sync-full-initialize`.
- **AI purpose/schema context** (inspired by llm_wiki): Two persistent org files — `~/NoteHQ/Roam/purpose.org` (knowledge base goals, key questions) and `~/NoteHQ/Roam/schema.org` (note types, tag conventions, linking rules) — are auto-injected into every gptel system prompt via `my/ai--build-system-prompt`. This gives the LLM persistent context about the user's PKM without manual repetition. Files are created with templates on first load (`SPC i g` or `my/ai--ensure-context-files`). Edit them to customize AI behavior.
- **KB overview generation**: `my/ai-overview` (`SPC i o`) collects org-roam statistics (total nodes, tag distribution, recent notes) and asks the LLM to generate a structured overview report (themes, gaps, connections, suggestions). Result is saved to `~/NoteHQ/Roam/overview.org` with timestamp. Inspired by llm_wiki's auto-updated overview.md.
- **Workspace layout**: Default startup opens dirvish-side + dashboard (lightweight). Full 3-column layout (dirvish-side + outline + terminal) is on-demand via `SPC l l`.
- **.orgseq personalized config**: `~/NoteHQ/.orgseq/` stores non-sensitive per-library settings (like `.vscode/`). First use case: `ai-config.org` — AI backend definitions, model lists, and defaults in an editable org file. API keys remain in `~/.authinfo.gpg` (auth-source). Init is incremental: files are created with templates only if missing, never overwritten. Parsed at gptel load time with hardcoded fallback on failure.
- **org-appear paired with org-hide-emphasis-markers**: Both must be enabled together. `org-hide-emphasis-markers t` makes `*bold*`/`/italic/` markers invisible at rest; `org-appear` reveals them only at the cursor for editing. Either alone is useless — hide-only loses editability, appear-only has nothing to reveal.
- **Doom-derived org-roam advices**: `init-roam.el` carries 4 fixes from Doom's `lang/org/contrib/roam.el` for issues that bite Evil + vertico users: (1) `org-roam-node-insert` places links *before* whitespace in evil normal mode — advised to insert after; (2) `magit-section-mode-map` overrides Evil keys in the org-roam buffer — parent keymap is detached on `org-roam-mode-hook`; (3) vertico truncates node candidates because of upstream org-roam#2066 — advised to use frame width; (4) `visual-line-mode` in the backlinks buffer prevents long titles from being cut off. All four are conditional on `evil`/`vertico` being loaded.
- **dirvish over treemacs**: The file sidebar was migrated from `treemacs` to `dirvish-side` in `init-dired.el`.  Rationale: (1) dirvish is based on dired — every dired keybinding works, muscle memory carries over; (2) active maintenance vs. treemacs' slower release cycle; (3) built-in preview pane (`dirvish-peek-mode`) for navigating notes without opening them; (4) `dirvish-override-dired-mode` upgrades every dired call globally, giving the whole config one consistent file-manager UI. `init-dired.el` is a dedicated module for dired+dirvish because the user is a dired-native and wants the package exposed beyond the sidebar. Sidebar helpers (`my/dirvish-side-open-at-notehq`, `my/dirvish-side-toggle`, `my/dirvish-side-visible-p`) are defined there and consumed by `init-workspace.el`.
- **org-focus-timer is a bundled subproject under `packages/`**: The Vitamin-R-style focus tracker lives at `packages/org-focus-timer/` inside this repository and is referenced from `lisp/init-focus.el` via a `:load-path` pointing at `<user-emacs-directory>/packages/org-focus-timer/`. Rationale: the package has enough independent value (zero deps, clean API) that it *could* be standalone, but until the API and data format stabilize it is easier to iterate with the source sitting right next to the config that calls it. The `packages/` directory is copied to `~/.emacs.d/packages/` by the deploy scripts alongside `lisp/`. When the package matures it will graduate to its own repo — at that point `init-focus.el` will switch to a `:vc` reference and the `packages/org-focus-timer/` directory will be deleted. **Do not add org-seq-specific code to the package**; keep it usable by any org user. The integration layer (`init-focus.el`) is the only place org-seq-specific defaults live — it points the log file at `~/NoteHQ/.orgseq/focus-log.org` and sets the Vitamin-R-style 10/30/15 duration parameters. Keybindings under `SPC a`: `SPC a f` starts a slice, `SPC a F` opens the dashboard, `SPC a X` aborts a running slice. If you clone org-seq but keep the package somewhere else, override `my/focus-timer-path` via `customize-group org-seq`.
- **NoteHQ scaffolding lives in `notehq/`**: A complete Claude Code support tree (CLAUDE.md + rules + skills) that bootstrap-notes copies to the user's `~/NoteHQ/`. Its rules and skills run *in* the user's notes directory, not in this repo. Keep notehq/ artifacts focused on note-author tasks (new-tag, weekly-review, archive-project), and keep org-seq/ artifacts focused on Emacs config tasks.

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
