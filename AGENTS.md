# org-seq

This file is the active contributor guidance for Codex in this repository.
It applies to the entire repository unless a deeper `AGENTS.md` overrides it.

## Project

- `org-seq` is a deployable `~/.emacs.d/` configuration, not a standalone app.
- Primary target is Windows, with Linux and macOS support.
- Treat Emacs 30+ as the active requirement. The repo still contains some older 29+ wording in docs; do not copy that drift into new changes.
- Runtime output is mainly `early-init.el`, `init.el`, `lisp/`, `packages/`, and selected scripts.

## Repo Boundaries

- Root files plus `lisp/` are the org-seq config itself.
- `packages/` holds bundled subprojects that should remain publishable on their own. See `packages/AGENTS.md`.
- `notehq/` is end-user scaffolding copied into a user's `~/NoteHQ/`. See `notehq/AGENTS.md`.
- `doc/` is user-facing documentation and architecture rationale, not runtime code.

## Elisp Conventions

These rules apply to `early-init.el`, `init.el`, root helper `.el` files, and `lisp/*.el`.

- Use `lexical-binding: t` in file headers.
- End module files with `(provide 'init-MODULE)`.
- Prefer `use-package` for package configuration; only use bare `require` for built-ins or when structurally necessary.
- Add a `Requires:` comment near the top when a module depends on variables or functions from another `init-*` module.
- Forward-declare cross-module variables with `defvar`.
- Prefix org-seq functions and variables with `my/`; use `my/module--helper` for private helpers.
- Use `defcustom` for user-facing settings, with `:type` and `:group 'org-seq`.
- Keep section heading style consistent within a file.

## Character Set Discipline

- Do not add emoji to Elisp source, comments, or strings.
- Do not add fullwidth punctuation to Elisp source, comments, or strings.
- ASCII is preferred for source and comments.
- Box-drawing characters in comments are acceptable because the repo already uses them consistently.

## Paths And Platform Notes

- Use forward slashes in Elisp paths.
- Use `file-truename` for paths that feed org-roam, org-mem, or org-supertag.
- Central path constants belong in `lisp/init-org.el`.
  - This includes `my/note-home`, `my/orgseq-dir`, `my/roam-dir`, PARA layer paths, dashboard paths, schema paths, and user capture-template paths.
  - Other modules should consume these variables via `defvar`, not rebuild `00_Roam/`, `10_Outputs/`, or `20_Practice/` by string.
- Keep Windows-specific notes in plain ASCII comments such as `NOTE(win): ...`.
- Remember that Windows uses `server-use-tcp t` and the named server `org-seq`.

## Load Order

The module load order in `init.el` is intentional:

`init-ui -> init-completion -> init-pyim -> init-markdown -> init-languages -> init-org -> init-roam -> init-gtd -> init-focus -> init-pkm -> init-supertag -> init-ai -> init-dashboard -> init-dired -> init-workspace -> init-update -> init-tty -> init-evil`

When adding a new module:

- Place it deliberately in the dependency chain.
- Update `init.el`.
- Update the load-order comment in `init.el` at the same time; do not let comments drift from the actual module list.
- Update `README.md`, `CONTRIBUTING.md`, and this file if the change is user-visible or affects repo structure.

Startup failure visibility:

- `init.el` intentionally guards module loading so one broken module does not kill the whole session.
- Preserve `my/--init-errors` and `M-x my/init-errors` as the inspection path for guarded module failures.
- If you change guarded loading, keep the warning actionable and point users to the inspection command.

## Adding Packages

- If you are integrating a third-party package into org-seq, add a `use-package` block to the appropriate `lisp/init-*.el`.
- If you are writing a reusable package that may later leave this repo, put it under `packages/<name>/` and add only a thin integration layer under `lisp/init-<name>.el`.
- Put global leader bindings in `lisp/init-evil.el`.
- Put Org local-leader bindings in `lisp/init-org.el`.
- Do not reintroduce split Emacs-29/30 bootstrap branches for GitHub packages; follow the existing `package-vc-install` bootstrap pattern already used in the repo.

## Validation

Validation is explicit in this repo. Run the checks yourself while working.

- After editing any `.el` file, byte-compile the changed file.
- Before a commit or after a multi-file refactor, run a full repo byte-compile pass.
- Also run `emacs --batch -Q -l init.el` after startup/load-order changes.
- Delete generated `.elc` files after validation; this repo does not commit bytecode.
- Treat `Cannot load PACKAGE` during `emacs --batch -Q` byte-compilation as expected when a third-party package is absent from the clean validation load path; still fix real warnings in files you touch when practical.
- Prefer `defvar` for cross-module/customization variables and `declare-function` for third-party functions used before their package is loaded, so warning noise does not hide real problems.

Single-file check from repo root:

```powershell
$lps = @("-L", ".", "-L", "lisp")
Get-ChildItem "packages" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $lps += @("-L", $_.FullName) }
emacs --batch -Q @lps -f batch-byte-compile path\to\file.el
Remove-Item path\to\file.elc -ErrorAction SilentlyContinue
```

Full-repo check from repo root:

```powershell
$lps = @("-L", ".", "-L", "lisp")
Get-ChildItem "packages" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $lps += @("-L", $_.FullName) }
$files = @("early-init.el", "init.el")
$files += Get-ChildItem "lisp/*.el" | ForEach-Object { Join-Path "lisp" $_.Name }
$files += Get-ChildItem "packages/*/*.el" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
foreach ($file in $files) { emacs --batch -Q @lps -f batch-byte-compile $file; Remove-Item ($file + "c") -ErrorAction SilentlyContinue }
```

## Deploy And Environment Checks

- Prefer `deploy.ps1` on Windows and `deploy.sh` on Linux/macOS instead of ad-hoc copying.
- Those deploy scripts are also the canonical prerequisite checks for Emacs, SQLite, `rg`, `fd`, `git`, and `HOME`.
- If you change deployment behavior, keep the scripts, README, and docs aligned.

## Org File Conventions

For `.org` files anywhere in the repo:

- Use `#+title:` and `#+filetags:` where the file is meant to be a structured note template or example.
- Preserve `:ID:` properties; do not rewrite or remove them casually.
- Prefer `[[id:...][title]]` links over `file:` links for inter-note references.
- Keep dashboard `.org` files query-only; do not turn them into data-entry files.
- Keep the TODO sequence aligned with org-seq's configured states:
  `PROJECT -> TODO -> NEXT -> IN-PROGRESS -> WAITING / SOMEDAY -> DONE / CANCELLED`

## Important Design Decisions

- Use `package.el` and `package-vc-install`, not `straight.el`.
- Keep Org sourced from GNU ELPA rather than relying on the bundled Org.
- `00_Roam/` is the atomic-note layer; GTD scans `00_Roam/`, `10_Outputs/`, and `20_Practice/`, but not `30_Library/` or `40_Archives/`.
- Markdown support exists for interoperability, but Markdown files are not part of the org-roam graph.
- `packages/org-focus-timer/` is intentionally bundled for now; keep org-seq-specific behavior in `lisp/init-focus.el`, not inside the package.
- This is a private, personally operated configuration. Do not spend change budget hardening away intentional personal choices such as automatic package updates, unconfirmed Babel execution, or unpinned GitHub packages unless the user asks.
- `custom.el` is an explicit user-override layer loaded before modules. Keep loading failures visible, and provide an easy way to inspect the file rather than making its influence implicit.

## Common Task Mappings

- `elisp-lint`: run the full byte-compile pass described above.
- `startup-check`: run `emacs --batch -Q -l init.el`.
- `add-package`: follow the package-placement rules in this file and `packages/AGENTS.md`.
- `centralize-paths`: define shared NoteHQ/PARA paths in `lisp/init-org.el`, then consume them elsewhere with `defvar`.
- `review-and-commit`: review `git diff`, stage only intended tracked files, leave local pi/session/untracked state alone unless asked, commit with the existing style, then push.
- `deploy-config`: prefer `deploy.ps1` or `deploy.sh`.
- `check-windows-deps`: use the prerequisite checks already implemented in `deploy.ps1`.
