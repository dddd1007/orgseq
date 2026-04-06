---
name: check-windows-deps
description: Check if all required external dependencies for org-seq are installed on this Windows system
user_invocable: true
---

# Check Windows Dependencies

Verify that all external dependencies needed by the org-seq Emacs PKM configuration are available.

## Checks to perform

Run these checks and report status for each:

1. **Emacs**: `emacs --version` - need 29+
2. **SQLite support**: `emacs --batch --eval "(message \"%s\" (sqlite-available-p))"` - must be `t`
3. **Native-comp**: `emacs --batch --eval "(message \"%s\" (native-comp-available-p))"` - nice to have
4. **ripgrep**: `rg --version` - required by consult-ripgrep
5. **fd**: `fd --version` - required by consult-find
6. **git**: `git --version` - required by magit
7. **HOME env var**: `echo $HOME` - should be set explicitly
8. **MSYS2** (optional): check if `C:/msys64/mingw64/bin` exists

## Report format

For each dependency:
- PASS: installed and meets version requirements
- WARN: installed but version may be insufficient
- FAIL: not found, with installation instructions (winget/scoop/msys2)
