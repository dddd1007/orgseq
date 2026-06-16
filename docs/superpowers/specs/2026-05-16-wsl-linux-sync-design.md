# WSL and Linux sync design

## Goal

Make org-seq feel like one coherent workspace across Windows, WSL, and Linux. The first target is path consistency for NoteHQ, because terminal popups, yazi, Codex, OpenCode, kimi-cli, org-roam, GTD, dashboard files, and scaffolding all depend on the same root path.

The design favors stable, explicit behavior over hidden detection. Users should be able to set one environment variable and know exactly which NoteHQ directory org-seq will use.

## Scope

This change covers:

- Resolving `my/note-home` from `ORG_SEQ_NOTE_HOME` before falling back to `~/NoteHQ/`.
- Keeping all derived NoteHQ paths under `init-org.el`, so other modules continue to consume central path variables.
- Making Linux and WSL client startup smoother by adding a TUI client path to `ec`.
- Updating deployment and user documentation so Windows, WSL, and Linux setup instructions describe the same path model.
- Letting existing CLI popups and yazi naturally inherit the resolved `my/note-home`.

This change does not create symbolic links, copy NoteHQ data, or decide which external sync tool the user should use.

## Path Resolution

`init-org.el` should introduce a small resolver for the NoteHQ root:

1. Read `ORG_SEQ_NOTE_HOME`.
2. If it is non-empty, expand and normalize it as the NoteHQ root.
3. If it is unset or empty, fall back to `~/NoteHQ/`.
4. Use `file-truename` only when the path already exists, preserving first-run behavior when the directory has not been created yet.

`my/note-home` remains the public user-facing defcustom. `my/orgseq-dir`, `my/roam-dir`, `my/outputs-dir`, `my/practice-dir`, `my/library-dir`, and `my/archives-dir` continue to derive from it.

## Environment Contract

The cross-system contract is:

```sh
export ORG_SEQ_NOTE_HOME="$HOME/NoteHQ"
```

For WSL users who intentionally want to use a Windows-side directory:

```sh
export ORG_SEQ_NOTE_HOME="/mnt/c/Users/exrld/NoteHQ"
```

For Windows PowerShell users:

```powershell
$env:ORG_SEQ_NOTE_HOME = "$HOME\NoteHQ"
```

Long-term shell persistence belongs in the user's shell profile, not inside the repository.

## Client Startup

The Unix `ec` helper should support a terminal client mode while keeping the existing GUI behavior:

- `ec file.org` keeps opening a GUI client frame with `emacsclient -c -n -s org-seq`.
- `ec --tty file.org` opens a terminal client with `emacsclient -t -s org-seq`.
- `ORG_SEQ_CLIENT=tty ec file.org` provides the same behavior for shell aliases.

Both modes use the same named server, so a WSL or Linux user can choose GUI or TUI without changing the server model.

## Deployment And Documentation

`deploy.sh` should report the relevant NoteHQ source in its summary:

- If `ORG_SEQ_NOTE_HOME` is set, show that value.
- If it is unset, explain that org-seq will use `~/NoteHQ/`.

`deploy.ps1` should document the same environment variable for Windows users, even though the immediate target is WSL and Linux consistency.

`README.md`, `doc/GUIDE.md`, and `doc/TUTORIAL.md` should describe the environment variable, the WSL example, and the `ec --tty` entry.

## Error Handling

The resolver should avoid failing startup just because the NoteHQ directory does not exist yet. Existing bootstrap commands may create the directory later.

If `ORG_SEQ_NOTE_HOME` points to a malformed or inaccessible location, org-seq should surface the problem through the existing path consumers rather than adding a second warning system. This keeps startup behavior simple and avoids noisy false positives when a removable or synced directory is temporarily unavailable.

## Verification

Implementation should be verified with:

- Unit-level batch checks for the NoteHQ resolver with unset and set environment variables.
- `emacs --batch -Q -l init.el` to confirm guarded startup still works.
- A byte-compile pass for changed Elisp files.
- Shell syntax checks for `ec` and `deploy.sh` where the local environment permits them.
- `git diff --check` before finalizing.

## Open Decisions

No open product decision remains. The chosen default is environment-variable-first resolution with a plain `~/NoteHQ/` fallback.
