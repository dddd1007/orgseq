# org-seq

A modular Emacs configuration for personal knowledge management, built on org-roam with Zettelkasten methodology.

Primary target: **Windows** (with Linux/macOS compatibility).

## Prerequisites

- **Emacs 29+** (required for built-in SQLite and use-package)
  - Windows: MSYS2 build recommended for native-comp support
  - Verify: `M-: (sqlite-available-p)` must return `t`
- **ripgrep** (`rg`): `winget install BurntSushi.ripgrep.MSVC`
- **fd**: `winget install sharkdp.fd`
- **git**: for magit integration
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

   PowerShell options: `-Force`, `-SkipChecks`, `-Target DIR`
   Bash options: `--force`, `--skip-checks`, `--target DIR`

3. Launch Emacs — packages will auto-install on first run (needs internet).

4. Post-install (Windows only):
   ```
   M-x nerd-icons-install-fonts
   ```
   Then right-click the downloaded `.ttf` files and select "Install".

## Key Bindings

Leader keys use `SPC` in normal/visual mode. In insert mode, use `M-SPC`.

| Key | Action |
|-----|--------|
| `SPC SPC` | M-x |
| `SPC a n` | GTD task dashboard |
| `SPC a p` | GTD project dashboard |
| `SPC a w` | GTD weekly review |
| `SPC a c` | Org capture |
| `SPC a d` | GTD Dashboard (live counts) |
| `SPC a u` | Upcoming tasks (grouped by day) |
| `SPC n f` | Find note (org-roam) |
| `SPC n c` | New note (org-roam capture) |
| `SPC n i` | Insert link (org-roam) |
| `SPC n b` | Toggle backlinks |
| `SPC n s` | Search notes (ripgrep) |
| `SPC n g` | Graph view |
| `SPC n d d` | Daily note (capture today) |
| `SPC n d t` | Daily note (goto today) |
| `SPC i i` | Send to AI (gptel) |
| `SPC i m` | AI menu (models/params) |
| `SPC i c` | AI chat buffer |
| `SPC i r` | AI rewrite region |
| `SPC i s` | AI summarize note |
| `SPC i l` | AI translate |
| `SPC c c` | Casual menu (contextual Transient) |
| `SPC /` | Project-wide search (ripgrep) |
| `SPC ,` | Switch buffer |
| `SPC g g` | Magit status |
| `SPC l l` | Open 3-column workspace |
| `, r` | Org refile (org buffers) |
| `, x` | Org export (org buffers) |
| `, k i` | Clock in (org buffers) |
| `, v` | Toggle preview (markdown buffers) |
| `, e` | Export (markdown buffers) |

Press `SPC` and wait for the which-key popup to see all available keys.

Task flow (GTD style): `TODO -> NEXT -> IN-PROGRESS -> DONE`, plus `WAITING` and `SOMEDAY`.

## Module Structure

| Module | Purpose |
|--------|---------|
| `init-ui.el` | Fonts (CJK mixed), modus-themes (default), doom-modeline, olivetti |
| `init-completion.el` | Vertico + Orderless + Consult + Marginalia + Embark |
| `init-markdown.el` | Markdown mode + TOC + preview/export |
| `init-org.el` | Org-mode config + org-modern + evil-org + GTD agenda |
| `init-roam.el` | org-roam + md-roam (org/md mixed graph) + dailies + graph UI |
| `init-pkm.el` | org-transclusion + org-ql |
| `init-ai.el` | gptel (LLM client, OpenRouter) + ob-gptel (org-babel AI) |
| `init-dashboard.el` | Startup dashboard with recent files and quick actions |
| `init-workspace.el` | Three-column layout: treemacs + outline + terminal |
| `init-evil.el` | Evil mode + general.el leader keys + magit |

Notes live under `~/NoteHQ/`. org-roam uses `~/NoteHQ/Roam/`; other subdirectories are for non-roam notes. Tasks from all subdirectories appear in the GTD dashboard.

Obsidian workflow: point Obsidian at `~/NoteHQ/` as vault, use Emacs as the editing/workbench, Obsidian as a fast reading/search client.

## Reference

See [org-seq-build.md](org-seq-build.md) for the full research guide covering Windows-specific issues, package rationale, and troubleshooting.

## License

[MIT](LICENSE)
