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
   ```

2. Copy config to Emacs directory:
   ```bash
   cp early-init.el init.el ~/.emacs.d/
   cp -r lisp/ ~/.emacs.d/lisp/
   ```

3. Launch Emacs — packages will auto-install on first run (needs internet).

4. Post-install (Windows only):
   ```
   M-x nerd-icons-install-fonts
   ```
   Then right-click the downloaded `.ttf` files and select "Install".

## Key Bindings

All leader keys use `SPC` (normal/visual mode) or `M-SPC` (insert mode).

| Key | Action |
|-----|--------|
| `SPC SPC` | M-x |
| `SPC n f` | Find note (org-roam) |
| `SPC n c` | New note |
| `SPC n d` | Daily note |
| `SPC n b` | Toggle backlinks |
| `SPC n g` | Graph view |
| `SPC /` | Project-wide search (ripgrep) |
| `SPC ,` | Switch buffer |
| `SPC g g` | Magit status |

Press `SPC` and wait for the which-key popup to see all available keys.

## Module Structure

| Module | Purpose |
|--------|---------|
| `init-ui.el` | Fonts (CJK mixed), doom-themes, doom-modeline |
| `init-completion.el` | Vertico + Orderless + Consult + Marginalia + Embark |
| `init-org.el` | Org-mode config + org-modern + evil-org |
| `init-roam.el` | org-roam + capture templates + dailies + graph UI |
| `init-pkm.el` | org-transclusion + org-ql |
| `init-evil.el` | Evil mode + general.el leader keys + magit |

## Reference

See [org-seq-build.md](org-seq-build.md) for the full research guide covering Windows-specific issues, package rationale, and troubleshooting.

## License

[MIT](LICENSE)
