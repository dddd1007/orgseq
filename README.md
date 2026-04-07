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
| `SPC n s` | Search notes (ripgrep) |
| `SPC n g` | Graph view |
| `SPC n a` | Add alias |
| `SPC n r` | Add ref |
| `SPC n d d` | Daily note (capture today) |
| `SPC n d t` | Daily note (goto today) |
| `SPC n d y` | Yesterday |
| `SPC n d f` | Find date |
| `SPC n t a` | Transclusion add |
| `SPC n q s` | org-ql search |

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

**In Org buffers:**

| Key | Action |
|-----|--------|
| `, r` | Refile |
| `, a` | Archive |
| `, t` | Set tags |
| `, s` | Schedule |
| `, d` | Deadline |
| `, x` | Export |
| `, l` | Insert link |
| `, q` | State picker |
| `, h` | Hide/show done |
| `, n` | Narrow to subtree |
| `, w` | Widen |
| `, k i/o/g` | Clock in/out/goto |
| `, b e/b/t` | Babel execute/buffer/tangle |

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

| # | Module | Purpose |
|---|--------|---------|
| 1 | `init-ui.el` | Fonts (CJK mixed), modus-themes, doom-modeline, olivetti |
| 2 | `init-completion.el` | Vertico + Orderless + Consult + Marginalia + Embark |
| 3 | `init-markdown.el` | Markdown mode + TOC + preview/export + visual-fill |
| 4 | `init-org.el` | Org-mode + GTD dashboard + 7 agenda views + state picker |
| 5 | `init-roam.el` | org-roam + md-roam (org/md mixed graph) + dailies + graph UI |
| 6 | `init-pkm.el` | org-transclusion + org-ql |
| 7 | `init-ai.el` | gptel (OpenRouter) + ob-gptel (org-babel AI blocks) |
| 8 | `init-dashboard.el` | Startup dashboard with vertical centering + random quotes |
| 9 | `init-workspace.el` | Workspace: treemacs + outline + eshell terminal |
| 10 | `init-evil.el` | Evil + general.el leader keys + magit + casual + which-key |

## Notes Directory

Notes live under `~/NoteHQ/`. org-roam uses `~/NoteHQ/Roam/` with subdirectories (`daily/`, `lit/`, `concepts/`). Other NoteHQ subdirectories can hold non-roam notes. GTD agenda scans the entire NoteHQ tree.

**Obsidian workflow**: point Obsidian at `~/NoteHQ/` as vault. Use Emacs for editing/GTD, Obsidian as a fast reading/search client.

## Reference

See [org-seq-build.md](org-seq-build.md) for the full research guide covering Windows-specific issues, package rationale, and troubleshooting.

## License

[MIT](LICENSE)
