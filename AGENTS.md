# org-seq

This file is the active contributor guidance for Codex in this repository.
It applies to the entire repository unless a deeper `AGENTS.md` overrides it.

## Project

- `org-seq` is a deployable `~/.emacs.d/` configuration, not a standalone app.
- Platform priority: Linux is P0 and is where every change must be validated. Windows and macOS are P1: keep their code paths and scripts consistent, say so when a change to them was not run, and do not block Linux work on them.
- Treat Emacs 30+ as the active requirement. The repo still contains some older 29+ wording in docs; do not copy that drift into new changes.
- Runtime output is mainly `early-init.el`, `init.el`, `core/`, `kernel/`, `modules/`, `packages/`, `bin/`, and selected scripts.

## Repo Boundaries

- Root files plus three source trees are the org-seq config itself (`my/init-source-directories` in `init.el` puts them on `load-path`):
  - `core/` is the distribution core: platform repair, package governance, doctor, updates, and the command line (`orgseq-cli.el`).
  - `kernel/` is the note kernel. It has no UI and must load in a batch Emacs without any `modules/` file, evil, or a theme. Files there are named `orgseq-*.el` and provide the feature of the same name.
  - `modules/` holds feature modules grouped by area: `ui/`, `editor/`, `notes/`, `tools/`, `lang/`. Module files keep the `init-*.el` name and feature.
- `user.example/` is copied once into `user/` under the Emacs directory by the deploy scripts. `user/modules.el` (sets `my/init-disabled-modules` and `my/init-enabled-optional-modules`) loads before the modules, `user/config.el` after them, and `user/custom.el` is the Customize file. Never write into a deployed `user/` from org-seq code other than through Customize.
- `packages/` holds bundled subprojects that should remain publishable on their own. See `packages/AGENTS.md`.
- `notehq/` is end-user scaffolding copied into the user's note library. See `notehq/AGENTS.md`.
- `bin/orgseq` (and `bin/orgseq.cmd`) is the command line and MCP launcher. It runs a batch Emacs that loads `init.el` and then `core/orgseq-cli.el`; that file is not an init module and must not be added to `my/init-modules-default`.
- `doc/` is user-facing documentation and architecture rationale, not runtime code.

## Elisp Conventions

These rules apply to `early-init.el`, `init.el`, root helper `.el` files, and the Elisp under `core/`, `kernel/`, and `modules/`.

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
- Use `file-truename` for paths that feed org-roam or org-mem.
- Central path constants belong in `kernel/orgseq-paths.el`.
  - This includes `my/note-home`, `my/orgseq-dir`, `my/roam-dir`, PARA layer paths, dashboard paths, and user capture-template paths.
  - Other modules should consume these variables via `defvar`, not rebuild `00_Roam/`, `10_Outputs/`, or `20_Practice/` by string.
- The note library (`my/note-home`) defaults to `notes/` under `user-emacs-directory`; the name NoteHQ in docs and identifiers refers to that library. Do not reintroduce a required user-chosen directory. `ORG_SEQ_NOTE_HOME` remains as an override and is what validation uses to isolate writes. The old `~/NoteHQ/` location is only read by `my/storage-import` in `modules/notes/init-sync.el` and is never modified.
- The Emacs directory has four owners; keep them apart (see `doc/DESIGN.md`): distribution files (`early-init.el`, `init.el`, `ec`, `core/`, `kernel/`, `modules/`, `packages/`, `bin/`; the only things deployment writes), user settings (`user/`), the library (`notes/`), and rebuildable device state (`.cache/`, `elpa/`, `eln-cache/`).
- Device-local state (sync baseline, legacy notice, the command-line index) lives under `.cache/` in the Emacs directory, never inside the library, because the library is synced between devices.
- Content crosses the library boundary only through import, export, snapshots and sync in `modules/notes/init-sync.el`. Each copies and never modifies its source; import never overwrites. Do not add startup prompts about storage; report state through `my/storage-info` instead.
- Snapshots live in `my/snapshot-dir` (defined in `kernel/orgseq-paths.el`), outside the Emacs directory and outside the library. When `ORG_SEQ_NOTE_HOME` is set the default follows it to a sibling `.snapshots` directory, so validation never writes to the real data directory.
- Keep Windows-specific notes in plain ASCII comments such as `NOTE(win): ...`.
- Remember that Windows uses `server-use-tcp t` and the named server `org-seq`.

## Load Order

`core/init-platform.el` is a bootstrap-phase module. `init.el` requires it
directly, before package management, because `exec-path` repair and the ELPA
signature probe must run before the first package is installed. It has no
org-seq module dependencies, must not require another `init-*` module, and is
intentionally absent from `my/init-modules-default`.

The module load order in `init.el` is intentional:

`init-doctor -> init-packages -> init-popup -> init-keymap -> init-ui -> init-completion -> init-pyim -> init-python -> init-markdown -> init-languages -> init-org -> init-capture -> init-roam -> init-gtd -> init-gtd-dashboard -> init-focus -> init-pkm -> init-nodes -> init-views -> init-palette -> init-sync -> init-daily -> init-terminal -> init-ai -> init-ai-cli -> init-dashboard -> init-dired -> init-mouse -> init-frame -> init-workspace -> init-update -> init-tty -> init-evil`

Module dependencies are machine-checked: `my/init-module-requires` in `init.el`
declares each module's dependencies, mirroring the module's `;; Requires:`
header. Startup emits a warning for order violations, and
`scripts/test-init-loader.el` fails when the list, the headers, or the order
drift apart.

When adding a new module:

- Place it deliberately in the dependency chain.
- Update `init.el`: add the module to `my/init-modules-default` and, if it
  depends on other modules, add a matching `my/init-module-requires` record
  that agrees with the module's `;; Requires:` header.
- Update the load-order comment in `init.el` at the same time; do not let comments drift from the actual module list.
- Update `README.md`, `CONTRIBUTING.md`, and this file if the change is user-visible or affects repo structure.

Startup failure visibility:

- `init.el` intentionally guards module loading so one broken module does not kill the whole session.
- Preserve `my/--init-errors` and `M-x my/init-errors` as the inspection path for guarded module failures.
- If you change guarded loading, keep the warning actionable and point users to the inspection command.

## Adding Packages

- If you are integrating a third-party package into org-seq, add a `use-package` block to the appropriate `modules/<area>/init-*.el`.
- If you are writing a reusable package that may later leave this repo, put it under `packages/<name>/` and add only a thin integration layer under `modules/<area>/init-<name>.el`.
- Put global leader bindings in `modules/editor/init-evil.el`.
- Put Org local-leader bindings in `modules/notes/init-org.el`.
- Register Git-hosted package source, owner, and purpose metadata in `core/init-packages.el`; keep feature configuration in the owning module.
- Use `my/vc-package-ensure` for registered Git packages; do not add split Emacs-29/30 bootstrap branches or batch-time network installation.
- Record copied or closely adapted upstream fragments in `THIRD_PARTY.md` before committing them.
- A note is a node: any file or heading with an Org ID. The kernel index (`kernel/orgseq-index.el`) is the one index of nodes: built-in SQLite, a plain-text scan of the Org files, FTS5 trigram search, refreshed incrementally from file time and size. Everything that reads nodes (views, node tables, dashboard blocks, the command line, MCP, AI overview) gets records from `my/index-records`, `my/index-node`, `my/index-links` or `my/index-search`. Do not read the org-roam database from org-seq code, and do not add a second index or a package that keeps its own copy of note data.
- org-roam is optional and off by default: `init-roam` is listed in `my/init-optional-modules` and loads only when the user adds it to `my/init-enabled-optional-modules` in `user/modules.el`. Capture, Daily, node find, link insertion, backlinks and id-link following work without it (`modules/notes/init-capture.el`, `modules/notes/init-nodes.el`, `kernel/orgseq-note.el`). No module of the default set may require `init-roam`, call org-roam, or read its database; keys for org-roam-only features go through `my/roam-required` in `init-evil.el`.
- New note files are written only by `my/note-create` in `kernel/orgseq-note.el` (interactive capture, `my/api-create`, region extraction). Capture templates use the org-roam-capture format subset documented there.
- The node layer (`modules/notes/init-nodes.el`) adds types, fields, table views, and dashboard queries on top of the kernel index.
- Node types are defined only in `.orgseq/types.org` under NoteHQ (`my/types-file`, defined in `kernel/orgseq-paths.el`). A type is an Org tag, a list of fields, and a capture template. Do not hard-code types in Elisp.
- Org text is the only authority. Types are tags, fields are ordinary Org properties, relations are `[[id:]]` links. The index is disposable: `M-x my/index-rebuild` or `orgseq reindex` recreates it from the Org files.
- Views (`modules/notes/init-views.el`) are a query plus a layout (table, list, board) over node records. Saved views are headings in `.orgseq/views.org` (`my/views-file`); they hold no note data. Edits made in a view go through `my/node-call-at-id` into the node's Org file. Add new layouts and filter forms there instead of building a separate view store.
- Every type is a database: `my/node-view` opens the saved view named after the type, else `my/view-type-default` (its nodes, fields and formulas, shaped by optional `TYPE_VIEW_*` properties). Do not build a second table implementation for types.
- Named record templates are `Template: NAME` child headings of a type heading; the heading's own body stays the default template, and template children are never fields or types.
- Formulas (`FORMULA_NAME` on a type heading) and rollup columns (`count(<-tag)`, `sum(<-tag.FIELD)`, ...) are computed from the index while a view runs, never written to Org files, and read-only in views. Formula text is read as data and interpreted by the operator whitelist in `my/view--eval` (`modules/notes/init-views.el`); never `eval` user text.
- Field kinds are suffixes in `TYPE_FIELDS`: `node`, `nodes`, `date`, `number`, `check`, `url`, `multi` (values from `NAME_ALL`); each stays one ordinary Org property, and values written before a kind existed must keep reading.
- A type may extend one parent type (`TYPE_EXTENDS`). `my/node-single-type` makes a node an instance of one type by default; notes carrying several type tags must keep working.
- Library sync (`modules/notes/init-sync.el`) uses rclone bisync so one engine covers WebDAV, OneDrive and Google Drive. Credentials stay in rclone's config; never store them in the repo, `custom.el`, or the library. The org-roam database is a local index and is excluded from sync.
- The command line and the MCP tools (`core/orgseq-cli.el`) call the same `my/api-*` functions and the same write path as the interactive commands. They read the same kernel index as the interactive session (`.cache/index-<hash>.db`, one file per library path) and do not load org-roam. Standard output of `orgseq mcp` carries protocol messages only.
- Keep dashboards in `00_Roam/dashboards/` query-only. Write new dashboard tables as `orgseq-query` dynamic blocks; the `supertag-query` renderer exists only so dashboards written before Supertag was removed (2026-10-22) keep working.
- Preserve capture, Daily, PARA, and GTD.

## Validation

Validation is explicit in this repo. Run the checks yourself while working.

The canonical validation entry point (Linux, also macOS) is:

```bash
scripts/check.sh                                    # clean checkout
scripts/check.sh --packages ~/.emacs.d/elpa --strict  # deployed readiness
```

It runs all ERT files, byte-compiles every org-seq Elisp file, starts the
configuration in a batch Emacs, isolates NoteHQ writes through
`ORG_SEQ_NOTE_HOME`, and removes generated `.elc` files. `--strict` fails on
guarded module errors and required doctor failures.

The Windows validation entry point (P1; not run since the source trees moved
out of `lisp/`) is:

```powershell
pwsh -NoLogo -NoProfile -File scripts/check.ps1
```

It requires PowerShell 7 and Emacs 30+, automatically locates standard Windows
Emacs installations, runs all ERT files, full byte compilation, and batch
startup, isolates NoteHQ writes, and removes generated `.elc` files.
The default check keeps absent runtime and optional dependencies as warnings so
a clean source checkout remains testable without network access. For a deployed
or release-readiness check, run:

```powershell
pwsh -NoLogo -NoProfile -File scripts/check.ps1 `
  -PackageUserDir "$HOME\.emacs.d\elpa" `
  -RequireAllModules -RequireDependencies
```

Strict mode fails on guarded module errors, keymap drift, and required doctor failures.

- After editing any `.el` file, byte-compile the changed file.
- Before a commit or after a multi-file refactor, run a full repo byte-compile pass.
- Also run `emacs --batch -Q -l init.el` after startup/load-order changes.
- Delete generated `.elc` files after validation; this repo does not commit bytecode.
- Treat `Cannot load PACKAGE` during `emacs --batch -Q` byte-compilation as expected when a third-party package is absent from the clean validation load path; still fix real warnings in files you touch when practical.
- Prefer `defvar` for cross-module/customization variables and `declare-function` for third-party functions used before their package is loaded, so warning noise does not hide real problems.

Single-file check from repo root:

```bash
lps=(-L .)
while IFS= read -r d; do lps+=(-L "$d"); done < <(find core kernel modules packages -type d)
emacs --batch -Q "${lps[@]}" -f batch-byte-compile path/to/file.el
rm -f path/to/file.elc
```

The full-repo pass is the byte-compilation step of `scripts/check.sh`.

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
- Keep Daily sidebar rendering read-only; rendering must not create missing notes.
- Test Daily rendering and mutation boundaries with temporary NoteHQ roots.
- Keep the TODO sequence aligned with org-seq's configured states:
  `PROJECT -> TODO -> NEXT -> IN-PROGRESS -> WAITING / SOMEDAY -> DONE / CANCELLED`

## Important Design Decisions

- Use `package.el` and `package-vc-install`, not `straight.el`.
- Keep Org sourced from GNU ELPA rather than relying on the bundled Org.
- `00_Roam/` is the atomic-note layer; GTD scans `00_Roam/`, `10_Outputs/`, and `20_Practice/`, but not `30_Library/` or `40_Archives/`.
- Markdown support exists for interoperability, but Markdown files are not part of the org-roam graph.
- CLI tools such as terminal, Codex, OpenCode, and kimi-cli live in bottom popups rooted at `my/note-home`; do not add them back as permanent workspace panes.
- Keep yazi as an external TUI picker under `SPC o y` / `SPC o Y`; dirvish remains the native Emacs file manager.
- `packages/org-focus-timer/` is intentionally bundled for now; keep org-seq-specific behavior in `modules/notes/init-focus.el`, not inside the package.
- This is a private, personally operated configuration. Do not spend change budget hardening away intentional personal choices such as automatic package updates, unconfirmed Babel execution, or unpinned GitHub packages unless the user asks.
- `custom.el` is an explicit user-override layer loaded before modules. Keep loading failures visible, and provide an easy way to inspect the file rather than making its influence implicit.

## Common Task Mappings

- `elisp-lint`: run the full byte-compile pass described above.
- `startup-check`: run `emacs --batch -Q -l init.el`.
- `add-package`: follow the package-placement rules in this file and `packages/AGENTS.md`.
- `cli-check`: from a source checkout run `ORG_SEQ_PACKAGE_DIR=~/.emacs.d/elpa ORG_SEQ_NOTE_HOME=<temp dir> bin/orgseq doctor`; never point a test run at the real library.
- `centralize-paths`: define shared NoteHQ/PARA paths in `kernel/orgseq-paths.el`, then consume them elsewhere with `defvar`.
- `review-and-commit`: review `git diff`, stage only intended tracked files, leave local pi/session/untracked state alone unless asked, commit with the existing style, then push.
- `deploy-config`: prefer `deploy.ps1` or `deploy.sh`.
- `check-windows-deps`: use the prerequisite checks already implemented in `deploy.ps1`.
- `update-rime-frost-dict`: run `scripts/update-rime-frost-pyim.ps1`; it requires `git` and Python 3, keeps the upstream checkout in `.cache/rime-frost`, and writes the ignored `pyim/rime-frost.pyim` file that `init-pyim.el` auto-loads when present.
