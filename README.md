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

### SPC n s — org-supertag (data layer)

| Key | Action |
|-----|--------|
| `SPC n s a` | Add supertag |
| `SPC n s v` | View node (supertag) |
| `SPC n s s` | Search supertag DB |
| `SPC n s k` | Kanban view |
| `SPC n s c` | Supertag capture |
| `SPC n s n` | Create node |
| `SPC n s p` | Set parent tag |
| `SPC n s m` | Migrate properties → fields |
| `SPC n s S` | Sync status |
| `SPC n s r` | Sync now |
| `SPC n s R` | Full rebuild (`supertag-sync-full-initialize`) |

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
| `SPC l` | Layout (workspace/treemacs/outline/terminal/dashboard) |
| `SPC o` | Open (terminal/dashboard/agenda/treemacs/config) |
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
| `, # a` | Supertag: add tag |
| `, # v` | Supertag: view node |
| `, # s` | Supertag: search |
| `, # k` | Supertag: kanban |
| `, # c` | Supertag: capture |
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
| 4 | `init-org.el` | Org base: org-modern, evil-org, org-babel, local leader (incl. supertag `, #`) |
| 5 | `init-roam.el` | org-roam + org-node/org-mem (indexing, DB sync), dailies, org-roam-ui |
| 6 | `init-gtd.el` | GTD: dashboard (org-ql), agenda views, state machine, capture hooks |
| 7 | `init-pkm.el` | org-supertag (lazy sync), org-transclusion, org-ql extras |
| 8 | `init-ai.el` | gptel (OpenRouter) + ob-gptel (org-babel AI blocks) |
| 9 | `init-dashboard.el` | Startup dashboard with vertical centering + random quotes |
| 10 | `init-workspace.el` | Workspace: treemacs + outline + eshell terminal |
| 11 | `init-evil.el` | Evil + general.el leader keys + magit + casual + which-key |

## Notes Directory

Notes live under `~/NoteHQ/`. org-roam, org-mem, and org-supertag sync use `~/NoteHQ/Roam/` (with `daily/`, `lit/`, `concepts/`). Other `NoteHQ/` subtrees can hold non-roam Org files. GTD uses `my/note-home` (entire `NoteHQ/` by default); when org-mem is active, some caches prefer the Roam file list for speed—see [CLAUDE.md](CLAUDE.md) scope notes.

The graph is **Org-only** (no md-roam). First-time supertag index: `M-x supertag-sync-full-initialize`.

You can still point another tool at `~/NoteHQ/` for browsing; Roam-linked notes should stay `.org` for full PKM stack support.

## Reference

See [org-seq-build.md](org-seq-build.md) for the research guide (Windows, packages, troubleshooting) and [WORKFLOW.md](WORKFLOW.md) for day-to-day GTD/roam habits.

## License

[MIT](LICENSE)
