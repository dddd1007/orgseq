---
name: deploy-config
description: Deploy org-seq config files to the user's ~/.emacs.d/ directory
user_invocable: true
---

# Deploy Config

Copy the org-seq configuration to the user's Emacs directory for use.

## Steps

1. Verify the target directory (`~/.emacs.d/` or the user's configured Emacs directory)
2. **IMPORTANT**: Check if an existing config exists at the target. If yes, warn the user and ask for confirmation before overwriting. Offer to back up the existing config.
3. If confirmed, copy:
   - `early-init.el` -> `~/.emacs.d/early-init.el`
   - `init.el` -> `~/.emacs.d/init.el`
   - `lisp/` -> `~/.emacs.d/lisp/`
4. Verify the deployment by listing the target directory
5. Remind the user about post-deployment steps:
   - First launch will download packages (needs internet)
   - Run `M-x nerd-icons-install-fonts` then manually install .ttf files (Windows)
   - `~/org-roam/` and subdirs are auto-created on first launch by init-roam.el
   - Install external tools: `rg` (ripgrep), `fd` (fd-find)

## Files NOT deployed (stay in repo only)
- `org-seq-build.md` — reference documentation
- `CLAUDE.md` — development guidelines
- `README.md`, `LICENSE` — repo metadata
- `.claude/` — Claude Code config (not needed in ~/.emacs.d/)
- `.gitignore`, `.git/` — version control

## Safety

- NEVER overwrite without explicit user confirmation
- Always offer to create a backup first
- Check for and preserve `custom.el` if it exists at the target
