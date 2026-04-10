# Contributing to org-seq

Whether you're sending a PR or returning to the codebase six months from now, this is the orientation page. The detailed reference is [`CLAUDE.md`](CLAUDE.md); this file is the short version.

## Project shape

- **~3,500 lines of elisp** across 14 modules in `lisp/init-*.el`
- **Emacs 29+** required (built-in SQLite, use-package, package-vc-install)
- **Windows-first**, cross-platform compatible
- Output is a deployable `~/.emacs.d/` configuration, not a standalone application
- Notes live separately at `~/NoteHQ/` (created by `scripts/bootstrap-notes.{sh,ps1}`)
- One **bundled subproject** lives at `packages/org-focus-timer/` inside this repo and is referenced by `init-focus.el`. The deploy scripts copy it to `~/.emacs.d/packages/` alongside `lisp/`. It will graduate to its own repository when mature.

## Module load order

```
init-ui  →  init-completion  →  init-markdown  →  init-org  →  init-roam
        →  init-gtd  →  init-focus  →  init-pkm  →  init-supertag  →  init-ai
        →  init-dashboard  →  init-dired  →  init-workspace  →  init-evil
```

Order is fixed in `init.el` and matters — see CLAUDE.md "Module Load Order" for the dependency rationale. The general rule:

- `init-org` defines `my/note-home`, `my/orgseq-dir`, `my/roam-dir` (path constants used everywhere downstream)
- `init-roam` and `init-gtd` consume them; `init-focus`, `init-pkm`, `init-supertag`, `init-ai` extend them
- `init-focus` is a thin reference to the standalone `org-focus-timer` package (located at `my/focus-timer-path`, default `~/CodeProject/org-focus-timer/`)
- `init-dired` provides dired + dirvish + sidebar helpers (`my/dirvish-side-*`)
- `init-workspace` uses those helpers to build the 3-column layout; therefore loads AFTER init-dired
- `init-evil` loads last because `general.el` leader keys reference functions from every prior module

If you add a new module, decide where in the chain it fits, add `(require 'init-<name>)` to `init.el`, and update both CLAUDE.md and this file.

### Bundled subprojects (`packages/`)

Occasionally a feature has enough independent value that it should eventually live as its own package — zero deps, clean API, useful to any org user — but the API and data format aren't stable enough yet to justify the overhead of a separate repository. The pattern we use in that intermediate phase is: develop the package inside `packages/<name>/` within this repository, reference it from a dedicated `lisp/init-<name>.el` integration module, and let the deploy scripts copy the whole `packages/` tree to `~/.emacs.d/packages/` alongside `lisp/`.

Rules for code that lives under `packages/`:

1. **No org-seq-specific code inside the package itself.** All org-seq defaults (log file location, directory paths, customization group membership) go into the integration module under `lisp/`, never into the package source. This keeps the package portable: the day we extract it to its own repo, you should be able to `git mv packages/<name>/ ../<name>/` without editing a single line of the package.
2. **The package declares its own `defgroup`**. Don't attach its defcustoms to `org-seq`. The integration module can still re-bind package defcustoms via `use-package :custom` to org-seq-flavored defaults, but the underlying definitions belong to the package.
3. **Keep dependencies minimal.** If a bundled package starts requiring three other ELPA packages, that's a signal it's getting too entangled to stay in this pattern — either simplify it, move it fully into `lisp/`, or push it out to its own repo.
4. **Update the deploy scripts** if you add a new subdirectory under `packages/` — both `deploy.sh` and `deploy.ps1` copy `packages/` wholesale, so adding a new subproject requires no deploy-script changes; but the byte-compile verification step already globs `packages/**/*.el`, so new files will be linted automatically.

Current bundled subprojects:

- `packages/org-focus-timer/` — Vitamin-R-style focus timer, referenced by `lisp/init-focus.el`

## Code conventions (the short version)

Full rules in [`.claude/rules/elisp-style.md`](.claude/rules/elisp-style.md). Highlights:

- `;;; init-MODULE.el --- description -*- lexical-binding: t; -*-` header
- File ends with `(provide 'init-MODULE)`
- Custom functions/variables: `my/` prefix; private helpers: `my/module--name` (double dash)
- User-tunable settings: `defcustom` with `:type` and `:group 'org-seq` (the group is defined in `init-org.el`)
- Cross-module variable references: forward-declare with `(defvar my/varname)` near the file top
- Use `use-package` for every package; never bare `require` except for built-ins like `cl-lib`, `subr-x`
- Section headers: `;; ═══════════` for major sections, `;; ----` or `;; ─────` for subsections
- **No emoji, no fullwidth punctuation** in elisp source — past incident broke parsing on Windows. Use ASCII (`WARNING`, `[ok]`, `--`).

## Adding a new package

1. Pick the right `lisp/init-*.el` based on the load order above
2. Use `use-package` with `:after` for dependencies, `:hook` for mode activation, `:custom` for settings, `:bind` for keys
3. Add `:demand t` only if loading must be immediate; otherwise let it lazy-load
4. If the package needs leader-key bindings, add them in `init-evil.el` under the appropriate `SPC` group
5. If the package adds an org-mode local action, register it under `,` in `init-org.el`
6. Save the file — the **PostToolUse hook auto-byte-compiles it** and prints `[hook] OK` or `[hook] FAILED`
7. Run `/elisp-lint` for full-repo verification before committing
8. If users must install a runtime dependency manually (external binary, font, etc.), add a row to the troubleshooting table in `CLAUDE.md`

For a package not on MELPA (GitHub-only): wrap the `use-package` declaration in the Emacs 29 vs 30 dual-branch pattern used in `init-pkm.el` and `init-ai.el`. Both branches must keep their `:commands` and `:config` lists in sync.

## Testing

- **Per-edit auto-lint**: `.claude/settings.json` has a `PostToolUse` hook that runs `emacs --batch --eval "(byte-compile-file ...)"` on every `.el` write/edit. Watch for `[hook] FAILED` lines and fix immediately.
- **Pre-commit gate**: `.claude/settings.json` has a `PreToolUse` hook on `git commit` that byte-compiles the entire repo and refuses the commit if anything fails. **Do not skip this with `--no-verify`** — diagnose and fix the underlying issue.
- **Manual full-repo verification**: run `/elisp-lint` (or `bash` the loop in `.claude/skills/elisp-lint.md`) when you want to check everything mid-session.
- **Load test**: `emacs -Q --eval "(setq user-emacs-directory default-directory)" -l early-init.el -l init.el` from the repo root.
- **Startup time**: `emacs --eval "(message \"%s\" (emacs-init-time))"` after deploying.

## Claude Code helpers

The repo ships its own Claude Code support so future development sessions stay consistent:

- **`.claude/settings.json`** — hooks (PostToolUse byte-compile, PreToolUse pre-commit lint)
- **`.claude/rules/`** — scoped guidance auto-loaded by glob
  - `elisp-style.md` — applies to `*.el`
  - `org-conventions.md` — applies to `*.org`
- **`.claude/skills/`** — slash commands invocable from Claude Code
  - `/elisp-lint` — full-repo byte-compile check
  - `/add-package` — add a new use-package block
  - `/deploy-config` — deploy to `~/.emacs.d/`
  - `/check-windows-deps` — verify Emacs/SQLite/rg/fd/git

There is also `notehq/` — a separate scaffolding tree (CLAUDE.md + rules + skills) that `scripts/bootstrap-notes.sh` deploys to the user's `~/NoteHQ/`. **Treat `notehq/` as a deliverable for end users**; its contents do not apply to this repo's development. Use `scripts/bootstrap-notes.sh --update` to push changes from `notehq/` to a live `~/NoteHQ/` deployment.

## Documentation expectations

org-seq has unusually extensive docs for a personal config — keep them in sync when you change behavior:

- **`README.md`** — user-facing key bindings and module table
- **`CLAUDE.md`** — development guidelines (this file's parent reference)
- **`doc/GUIDE.md`** — long-form beginner guide (15 chapters)
- **`doc/WORKFLOW.md`** — daily PKM/GTD workflows
- **`doc/NOTES_ARCHITECTURE.md`** — Roam + PARA design rationale

When you change a leader key, you must update README.md AND doc/WORKFLOW.md. When you add a module, you must update CLAUDE.md (directory layout, load order) AND README.md (module table) AND CONTRIBUTING.md (this file).

## Commit hygiene

- Commit messages: short imperative subject, optional body. Examples in `git log --oneline`.
- Conventional prefixes used: `feat:`, `fix:`, `refactor:`, `perf:`, `docs:`, `revert:`
- Do not skip the pre-commit hook (`--no-verify`) without a strong reason
- Never `git push --force` to `master` without confirming
- The `.claude/settings.local.json` is gitignored — your personal Claude Code permissions don't get committed

## Where to start reading

1. `CLAUDE.md` — top-down architecture, design decisions, troubleshooting
2. `init.el` and `early-init.el` — runtime entry points
3. `lisp/init-org.el` — defines the foundational variables (`my/note-home`, `my/roam-dir`)
4. `lisp/init-evil.el` — the leader-key map gives you a structural overview of every feature
5. `doc/NOTES_ARCHITECTURE.md` — the "why" behind the Roam + PARA layout

## Getting help

- Issues / questions about Claude Code itself: `/help` inside Claude Code
- Issues / bugs in org-seq: open an issue in this repo
- Quick fixes: just send a PR — the hooks will catch most mistakes
