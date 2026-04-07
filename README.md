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

   Options: `--force` (skip prompts), `--skip-checks` (skip prerequisite check), `--target DIR` (custom directory).

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
| `SPC n f` | Find note (org-roam) |
| `SPC n c` | New note |
| `SPC n a` | Task dashboard (all org-roam tasks) |
| `SPC n p` | Project dashboard |
| `SPC n r` | Weekly review |
| `SPC n t` | All tasks list |
| `SPC n d` | Daily note |
| `SPC n b` | Toggle backlinks |
| `SPC n g` | Graph view |
| `, p` | Markdown preview (markdown buffers only) |
| `, e` | Markdown export (markdown buffers only) |
| `, t` | Markdown TOC insert (markdown buffers only) |
| `, r` | Markdown TOC refresh (markdown buffers only) |
| `SPC l l` | Open 3-column workspace |
| `SPC l t` | Toggle treemacs sidebar |
| `SPC l o` | Toggle outline sidebar |
| `SPC l e` | Toggle terminal |
| `SPC /` | Project-wide search (ripgrep) |
| `SPC ,` | Switch buffer |
| `SPC g g` | Magit status |

Press `SPC` and wait for the which-key popup to see all available keys.

Task flow (GTD style): `TODO -> NEXT -> IN-PROGRESS -> DONE`, plus `WAITING` and `SOMEDAY`.

## Module Structure

| Module | Purpose |
|--------|---------|
| `init-ui.el` | Fonts (CJK mixed), doom-themes, doom-modeline |
| `init-completion.el` | Vertico + Orderless + Consult + Marginalia + Embark |
| `init-markdown.el` | Markdown mode + TOC + preview/export |
| `init-org.el` | Org-mode config + org-modern + evil-org |
| `init-roam.el` | org-roam + md-roam (org/md mixed graph) + dailies + graph UI |
| `init-workspace.el` | Three-column layout: treemacs + outline + terminal |
| `init-pkm.el` | org-transclusion + org-ql |
| `init-evil.el` | Evil mode + general.el leader keys + magit |

Notes live under `~/NoteHQ/`. org-roam uses `~/NoteHQ/Roam/`; other subdirectories are for non-roam notes. Tasks from all subdirectories appear in the GTD dashboard.

Obsidian workflow: point Obsidian at `~/NoteHQ/` as vault, use Emacs as the editing/workbench, Obsidian as a fast reading/search client.

## Reference

See [org-seq-build.md](org-seq-build.md) for the full research guide covering Windows-specific issues, package rationale, and troubleshooting.

## License

[MIT](LICENSE)
