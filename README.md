# org-seq

A modular Emacs configuration for personal knowledge management, built on org-roam with Zettelkasten methodology.

Primary target: **Windows** (with Linux/macOS compatibility).

## Prerequisites

- **Emacs 29+** (required for built-in SQLite and use-package)
  - Windows: MSYS2 build recommended for native-comp support
  - Verify: `M-: (sqlite-available-p)` must return `t`
- **ripgrep** (`rg`): recommended for consult-ripgrep
- **fd**: recommended for consult-find
- **git**: required for magit
- **Fonts** (optional but recommended):
  - [Cascadia Code](https://github.com/microsoft/cascadia-code) (Latin)
  - [LXGW WenKai Mono](https://github.com/lxgw/LxgwWenKai) (CJK)

## Quick Start

1. Clone this repo:
   ```bash
   git clone <repo-url> ~/CodeProject/org-seq
   cd ~/CodeProject/org-seq
   ```

2. Run the deploy script (checks prerequisites, backs up existing config, deploys):

   PowerShell (Windows):
   ```powershell
   .\deploy.ps1
   ```

   Bash (Linux/macOS):
   ```bash
   ./deploy.sh
   ```

   Options: `-Force` / `--force`, `-SkipChecks` / `--skip-checks`, `-Target DIR` / `--target DIR`

3. Launch Emacs — packages will auto-install on first run (needs internet).

4. Post-install (Windows only):
   ```
   M-x nerd-icons-install-fonts
   ```
   Then right-click the downloaded `.ttf` files and select "Install".

## Key Bindings

Leader key is `SPC` in normal/visual mode, `M-SPC` in insert mode. Press `SPC` and wait for the which-key popup to see all available keys.

### Top-level

| Key | Action |
|-----|--------|
| `SPC SPC` | M-x |
| `SPC .` | Find file |
| `SPC ,` | Switch buffer |
| `SPC /` | Project-wide search (ripgrep) |
| `SPC TAB` | Last buffer |
| `SPC RET` | Jump to bookmark |
| `SPC '` | Toggle terminal |

### SPC a — Agenda / GTD

| Key | Action |
|-----|--------|
| `SPC a d` | GTD Dashboard (live counts + projects) |
| `SPC a n` | GTD overview (composite view) |
| `SPC a p` | Project dashboard |
| `SPC a w` | Weekly review |
| `SPC a u` | Upcoming tasks (grouped by day) |
| `SPC a c` | Org capture |
| `SPC a e` | State picker (single-keypress) |
| `SPC a 0` | Inbox |
| `SPC a 1` | Today |
| `SPC a 3` | Anytime (NEXT, no schedule) |
| `SPC a 4` | Waiting |
| `SPC a 5` | Someday |
| `SPC a 6` | Logbook (completed) |
| `SPC a 7` | Context view |
| `SPC a f` | Focus: start a Vitamin-R-style slice at point |
| `SPC a F` | Focus: open dashboard with recent slices + stats |
| `SPC a X` | Focus: abort the currently running slice |

### SPC n — Notes / org-roam

| Key | Action |
|-----|--------|
| `SPC n f` | Find note |
| `SPC n c` | New note (capture) |
| `SPC n i` | Insert link |
| `SPC n b` | Toggle backlinks |
| `SPC n /` | Search notes in Roam dir (ripgrep) |
| `SPC n g` | Graph view |
| `SPC n a` | Add alias |
| `SPC n r` | Add ref |
| `SPC n d d` | Daily note (capture today) |
| `SPC n d t` | Daily note (goto today) |
| `SPC n d y` | Yesterday |
| `SPC n d f` | Find date |
| `SPC n t a` | Transclusion add |
| `SPC n q s` | org-ql search |
| `SPC n q v` | org-ql view |

### SPC n p — org-supertag (data layer)

| Key | Action |
|-----|--------|
| `SPC n p p` | Quick action |
| `SPC n p a` | Add tag |
| `SPC n p e` | Edit field |
| `SPC n p x` | Remove tag |
| `SPC n p l` | List fields |
| `SPC n p j` | Jump to linked node |
| `SPC n p k` | Kanban view |
| `SPC n p s` | Search supertag DB |
| `SPC n p S` | Sync status |
| `SPC n p r` | Sync now |
| `SPC n p R` | Full rebuild (`supertag-sync-full-initialize`) |

### SPC n m — Meta (schema, templates, dashboards)

| Key | Action |
|-----|--------|
| `SPC n m t` | Edit tag schema |
| `SPC n m T` | Reload tag schema |
| `SPC n m c` | Edit capture templates |
| `SPC n m C` | Reload capture templates |
| `SPC n m d` | Create new dashboard |

### SPC i — AI

| Key | Action |
|-----|--------|
| `SPC i i` | Send to LLM |
| `SPC i m` | AI menu (models/params) |
| `SPC i c` | Chat buffer |
| `SPC i r` | Rewrite region |
| `SPC i s` | Summarize note |
| `SPC i t` | Suggest tags |
| `SPC i l` | Translate |
| `SPC i k` | Find connections |
| `SPC i p` | Improve writing |
| `SPC i o` | Generate KB overview |
| `SPC i g` | Init AI context files |

All AI commands are enriched with your **purpose.org** and **schema.org** context files (stored in `~/NoteHQ/Roam/concepts/`). Edit these files to customize how the LLM understands your knowledge base — no manual repetition needed.

### Other groups

| Key | Action |
|-----|--------|
| `SPC b` | Buffer (switch/kill/save/revert/ibuffer) |
| `SPC c c` | Casual menu (Transient for current mode) |
| `SPC e` | Eval (last-sexp/buffer/region/defun) |
| `SPC f` | File (open/recent/save/rename/delete/copy-path) |
| `SPC g` | Git (status/blame/log/diff) |
| `SPC h` | Help (function/variable/key/mode/info) |
| `SPC l` | Layout (workspace/sidebar/outline/terminal/dashboard) |
| `SPC o` | Open (dirvish/dired/terminal/dashboard/agenda/config) |
| `SPC f j` | Dired jump (to current file's directory) |
| `SPC p` | Project (switch/find-file/search/buffer) |
| `SPC s` | Search (line/ripgrep/imenu/outline/bookmark/replace) |
| `SPC t` | Toggle (theme/line-numbers/wrap/olivetti/fullscreen) |
| `SPC w` | Window (split/close/maximize/navigate/resize) |
| `SPC q q` | Quit Emacs |

### `, ` Local leader (mode-specific)

**In Org buffers** (local leader `,`):

| Key | Action |
|-----|--------|
| `, r` | Refile |
| `, a` | Archive subtree |
| `, t` | Set tags |
| `, p` | Set property |
| `, e` | Set effort |
| `, x` | Export |
| `, l` / `, L` | Insert link / Store link |
| `, s` | Schedule |
| `, d` | Deadline |
| `, i` / `, I` | Active / inactive timestamp |
| `, q` | GTD state picker |
| `, h` | Hide/show done |
| `, n` | Narrow to subtree |
| `, w` | Widen |
| `, c` | Toggle checkbox |
| `, # #` | Supertag: quick action |
| `, # a` | Supertag: add tag |
| `, # e` | Supertag: edit field |
| `, # x` | Supertag: remove tag |
| `, # j` | Supertag: jump to linked node |
| `, k i/o/g/r/c` | Clock in/out/goto/report/cancel |
| `, b e/b/t` | Babel execute block/buffer/tangle |

**In Markdown buffers:**

| Key | Action |
|-----|--------|
| `, v` | Toggle live preview |
| `, p` | Preview |
| `, e` | Export |
| `, t` | Insert TOC |
| `, r` | Refresh TOC |
| `, l` | Insert link |

## GTD System

TODO keywords: `PROJECT` → `TODO` → `NEXT` → `IN-PROGRESS` → `WAITING` / `SOMEDAY` → `DONE` / `CANCELLED`

The GTD Dashboard (`SPC a d`) shows live counts and is the central hub:
- **Inbox / Today / Upcoming / Anytime / Waiting / Someday / Logbook** with task counts
- **Projects** with status indicators (● stuck, ~ no NEXT, blank = healthy)
- **Context tags** (@work, @home, etc.) with NEXT task counts
- Click any row to open the corresponding view in the right pane

## Module Structure

Load order is fixed in `init.el` (see [CLAUDE.md](CLAUDE.md)).

| # | Module | Purpose |
|---|--------|---------|
| 1 | `init-ui.el` | Fonts (CJK mixed), modus-themes, doom-modeline, olivetti |
| 2 | `init-completion.el` | Vertico + Orderless + Consult + Marginalia + Embark |
| 3 | `init-markdown.el` | Markdown mode + TOC + preview/export + visual-fill |
| 4 | `init-org.el` | Org base: org-modern, org-appear, org-tempo, evil-org, org-babel, local leader (incl. supertag `, #`) |
| 5 | `init-roam.el` | org-roam + org-node/org-mem (indexing, DB sync), dailies, org-roam-ui, Doom-derived advices |
| 6 | `init-gtd.el` | GTD: dashboard (org-ql), agenda views, state machine, capture hooks |
| 7 | `init-focus.el` | Integration layer for the standalone `org-focus-timer` package (Vitamin-R-style focus slices) |
| 8 | `init-pkm.el` | org-supertag (install) + org-transclusion + org-ql |
| 9 | `init-supertag.el` | Supertag schema/dashboard/PARA navigation + NoteHQ bootstrap |
| 10 | `init-ai.el` | gptel (OpenRouter) + ob-gptel + claude-code + .orgseq AI config + KB overview |
| 11 | `init-dashboard.el` | Startup dashboard with vertical centering + random quotes |
| 12 | `init-dired.el` | Dired + dirvish (modern file manager, sidebar, peek, quick-access) |
| 13 | `init-workspace.el` | Workspace: dirvish-side sidebar + imenu-list outline + eshell terminal |
| 14 | `init-evil.el` | Evil + general.el leader keys + magit + casual + which-key |

### Bundled subproject: `packages/org-focus-timer/`

`init-focus.el` loads a Vitamin-R-style focus timer that currently lives inside this repository at `packages/org-focus-timer/`. The deploy scripts copy the whole `packages/` tree to `~/.emacs.d/packages/` alongside `lisp/`, and `init-focus.el` resolves the load path relative to `user-emacs-directory`, so no extra configuration is needed — clone the repo, run `deploy.sh` / `deploy.ps1`, and the focus timer is available as `SPC a f` / `SPC a F` / `SPC a X`.

The package has zero dependencies beyond Emacs 29+ and no org-seq-specific code inside it, which means it stays portable. When it matures, it will graduate into its own repository and `init-focus.el` will switch to referencing it via `:vc`. Until then, the source lives next to the config that calls it so iteration is fast — edit the file, `M-x eval-buffer`, and changes take effect immediately.

See `packages/org-focus-timer/README.md` for the package-level documentation.

## Notes Directory

Notes live under `~/NoteHQ/`, organized as a Roam + PARA hybrid:

```
~/NoteHQ/
├── Roam/                ← Atomic notes (org-roam-directory) — flat, plus daily/, capture/, dashboards/
│   ├── daily/           ← Daily journal entries
│   ├── capture/         ← Captured notes (timestamp-prefixed)
│   ├── dashboards/      ← Read-only supertag query views
│   └── supertag-schema.el  ← Tag definitions (version-controlled with notes)
├── Outputs/             ← PARA: deliverable projects (bounded lifetime)
├── Practice/            ← PARA: long-term responsibility domains
├── Library/             ← PARA: reference materials
├── Archives/            ← Completed/paused work
└── .orgseq/             ← Per-library config (ai-config.org, etc.)
```

Classification is by **supertag**, not directory — `Roam/` itself is flat. GTD agenda scans `Roam/` + `Outputs/` + `Practice/` (skips `Library/` and `Archives/`). org-roam, org-mem, and org-supertag all sync against `~/NoteHQ/Roam/`.

The graph is **Org-only** (no md-roam). First-time supertag index: `M-x supertag-sync-full-initialize` (or `SPC n p R`).

## Reference

- [doc/GUIDE.md](doc/GUIDE.md) — long-form architecture and rationale
- [doc/WORKFLOW.md](doc/WORKFLOW.md) — day-to-day GTD / roam habits
- [doc/NOTES_ARCHITECTURE.md](doc/NOTES_ARCHITECTURE.md) — Roam + PARA design
- [CLAUDE.md](CLAUDE.md) — development guidelines (for contributors / Claude Code)

## License

[MIT](LICENSE)
