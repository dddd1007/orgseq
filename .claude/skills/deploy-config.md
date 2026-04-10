---
name: deploy-config
description: Deploy org-seq config files to the user's ~/.emacs.d/ directory
user_invocable: true
---

# Deploy Config

Copy the org-seq configuration to the user's Emacs directory for use.

## Steps

Most of the time you should invoke `./deploy.sh` (or `.\deploy.ps1`) from the repo root — they already do everything listed below. This skill exists to mirror the logic when doing a manual deploy, or when helping a user debug a deploy-script issue.

1. Verify the target directory (`~/.emacs.d/` or the user's configured Emacs directory)
2. **IMPORTANT**: Check if an existing config exists at the target. If yes, warn the user and ask for confirmation before overwriting. Offer to back up the existing config to `~/.emacs.d.backup-YYYYMMDD-HHMMSS/`.
3. If confirmed, copy:
   - `early-init.el` → `~/.emacs.d/early-init.el`
   - `init.el` → `~/.emacs.d/init.el`
   - `lisp/` → `~/.emacs.d/lisp/`
   - `packages/` → `~/.emacs.d/packages/` (bundled subprojects like `org-focus-timer`)
4. Preserve `~/.emacs.d/custom.el` if it exists (restore from the backup after deploying new files).
5. Verify the deployment by listing the target directory and running `emacs --batch -Q -L ~/.emacs.d -L ~/.emacs.d/lisp -L ~/.emacs.d/packages/org-focus-timer -f batch-byte-compile ...` on all the deployed `.el` files.
6. Remind the user about post-deployment steps:
   - First launch will download all MELPA/ELPA packages (needs internet, ~2-5 minutes)
   - Run `M-x nerd-icons-install-fonts`, then (Windows only) manually install the downloaded `.ttf` files
   - `~/NoteHQ/Roam/` and its subdirectories are auto-created on first launch by init-supertag.el
   - Install external tools if missing: `rg` (ripgrep), `fd` (fd-find), `git`
   - Post-install **org-supertag** first-time sync: `M-x supertag-sync-full-initialize` (or `SPC n p R` after packages load)

## Files NOT deployed (stay in repo only)
- `doc/` — GUIDE.md, WORKFLOW.md, NOTES_ARCHITECTURE.md (read in repo clone)
- `CLAUDE.md` — development guidelines (not relevant at runtime)
- `README.md`, `LICENSE` — repo metadata
- `.claude/` — Claude Code dev config (hooks, rules, skills for repo work, not Emacs)
- `notehq/` — scaffolding deployed by `scripts/bootstrap-notes.*` to `~/NoteHQ/`, not to `~/.emacs.d/`
- `scripts/` — bootstrap scripts (run from repo, not copied)
- `.gitignore`, `.gitattributes`, `.git/` — version control
- `debug-*.el` — local debugging files (gitignored)

Deployed users should still read `README.md` and `doc/GUIDE.md` in the repo clone for prerequisites; post-install **org-supertag** first-time: `M-x supertag-sync-full-initialize` (or `SPC n p R` after packages load).

## Safety

- NEVER overwrite without explicit user confirmation
- Always offer to create a backup first
- Check for and preserve `custom.el` if it exists at the target
