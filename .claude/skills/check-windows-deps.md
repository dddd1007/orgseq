---
name: check-windows-deps
description: Check if all required external dependencies for org-seq are installed on this Windows system
user_invocable: true
---

# Check Windows Dependencies

Verify that all external dependencies needed by the org-seq Emacs PKM configuration are available.

## Checks to perform

Run these checks and report status for each:

1. **Emacs**: `emacs --version` - need 30+ (check `C:\Program Files\Emacs\` if not on PATH)
2. **SQLite support**: `emacs --batch --eval "(message \"%s\" (sqlite-available-p))"` - must be `t`
3. **Native-comp**: `emacs --batch --eval "(message \"%s\" (native-comp-available-p))"` - nice to have (optional; official Windows build omits libgccjit)
4. **ripgrep**: `rg --version` - recommended for consult-ripgrep (warned if missing)
5. **fd**: `fd --version` - recommended for consult-find (warned if missing)
6. **git**: `git --version` - required by magit
7. **HOME env var**: should be set explicitly so `~` matches Unix expectations
   - PowerShell: `[Environment]::GetEnvironmentVariable('HOME','User')` or `$env:HOME`
   - Bash/Git Bash: `echo $HOME`

## Report format

For each dependency:
- PASS: installed and meets version requirements
- WARN: installed but version may be insufficient
- FAIL: not found, with installation instructions (winget/scoop)
