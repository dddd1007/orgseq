# Contributing to org-seq

Whether you're sending a PR or returning to the codebase later, this is the orientation page. The detailed reference is [`AGENTS.md`](AGENTS.md); this file is the short version.

## Project shape

- **~3,500 lines of elisp** across `lisp/init-*.el`
- **Emacs 30+** required for the actively supported configuration
- **Windows-first**, but keep Linux and macOS working at the boundaries
- Output is a deployable `~/.emacs.d/` configuration, not a standalone application
- Notes live separately at `~/NoteHQ/` and are initialized by `scripts/bootstrap-notes.{sh,ps1}`
- One **bundled subproject** lives at `packages/org-focus-timer/`; see `packages/AGENTS.md` for package-local rules

## Module load order

```
init-ui  →  init-completion  →  init-pyim  →  init-markdown  →  init-languages
        →  init-org  →  init-roam  →  init-gtd  →  init-focus  →  init-pkm
        →  init-supertag  →  init-ai  →  init-dashboard  →  init-dired
        →  init-workspace  →  init-update  →  init-tty  →  init-evil
```

Order is fixed in `init.el` and matters. See `AGENTS.md` for the dependency rationale. The short version:

- `init-org` defines the path constants and base Org behavior used downstream
- `init-roam`, `init-gtd`, `init-focus`, `init-pkm`, `init-supertag`, and `init-ai` all build on that foundation
- `init-dired` provides the file-manager helpers that `init-workspace` depends on
- `init-update` runs after the package-config modules it manages
- `init-evil` loads last because the leader-key map references functions from nearly every earlier module

If you add a new module, place it deliberately in the chain, update `init.el`, and keep `AGENTS.md`, `README.md`, and this file aligned.

## Bundled subprojects

Some features live under `packages/<name>/` until their API and behavior are stable enough to leave this repo. When working there:

1. Keep org-seq-specific defaults in the integration layer under `lisp/`, not inside the package.
2. Let the package declare its own `defgroup`; do not attach package internals to `org-seq`.
3. Keep dependencies minimal so the package can still graduate into its own repository later.
4. Treat `deploy.sh` / `deploy.ps1` and the byte-compile pass as the validation boundary for new package files.

Current bundled subproject:

- `packages/org-focus-timer/` — Vitamin-R-style focus timer, referenced by `lisp/init-focus.el`

## Code conventions

Use `AGENTS.md` as the full rulebook. The short version:

- `;;; init-MODULE.el --- description -*- lexical-binding: t; -*-` header
- File ends with `(provide 'init-MODULE)`
- Custom functions/variables use the `my/` prefix; private helpers use `my/module--name`
- User settings use `defcustom` with `:type` and `:group 'org-seq`
- Forward-declare cross-module variables with `defvar`
- Prefer `use-package`; only use bare `require` for built-ins or structural necessities
- Keep Elisp source ASCII-friendly: no emoji, no fullwidth punctuation

## Adding a package

1. Put org-seq integration in the right `lisp/init-*.el` based on load order.
2. Use `use-package` with `:after`, `:hook`, `:custom`, and `:bind` where they fit.
3. Add leader keys in `lisp/init-evil.el` and Org local actions in `lisp/init-org.el`.
4. After editing `.el` files, byte-compile the changed file explicitly.
5. Before a commit or broad refactor, run the full-repo byte-compile pass from `AGENTS.md`.
6. If users must install a runtime dependency manually, document it in `README.md` and any affected architecture/workflow docs.

For GitHub-only packages, follow the existing `package-vc-install` bootstrap pattern already used in the repo instead of reviving split Emacs 29/30 branches.

## Testing

- **Changed-file validation**: byte-compile every edited `.el` file.
- **Repo-wide validation**: run the full byte-compile pass before commits or after multi-file changes.
- **Load test**: `emacs -Q --eval "(setq user-emacs-directory default-directory)" -l early-init.el -l init.el` from the repo root.
- **Startup time**: `emacs --eval "(message \"%s\" (emacs-init-time))"` after deploying.

## Codex workflow

The repository's active contributor guidance lives in the `AGENTS.md` hierarchy:

- `AGENTS.md` — root repo rules, validation commands, load order
- `packages/AGENTS.md` — package-specific constraints for bundled subprojects
- `notehq/AGENTS.md` — end-user NoteHQ scaffolding guidance

Treat `notehq/` as a deliverable for end users, not as repo-development instructions. `scripts/bootstrap-notes.{sh,ps1}` copies that subtree's Codex guidance into `~/NoteHQ/`.

## Documentation expectations

org-seq has unusually extensive docs for a personal config. Keep them in sync when behavior changes:

- **`README.md`** — user-facing key bindings and module table
- **`AGENTS.md`** — development guidelines and validation workflow
- **`doc/GUIDE.md`** — long-form beginner guide
- **`doc/WORKFLOW.md`** — daily PKM/GTD workflows
- **`doc/NOTES_ARCHITECTURE.md`** — Roam + PARA design rationale

When you change a leader key, update `README.md` and `doc/WORKFLOW.md`. When you add a module or change repo structure, update `AGENTS.md`, `README.md`, and this file.

## Commit hygiene

- Commit messages: short imperative subject, optional body. Check `git log --oneline` for precedent.
- Conventional prefixes commonly used here: `feat:`, `fix:`, `refactor:`, `perf:`, `docs:`, `revert:`
- Do not skip validation casually.
- Never `git push --force` to `master` without confirming first.

## Where to start reading

1. `AGENTS.md` — top-down architecture, rules, validation
2. `init.el` and `early-init.el` — runtime entry points
3. `lisp/init-org.el` — foundational path and Org variables
4. `lisp/init-evil.el` — the leader-key map gives a structural overview of the config
5. `doc/NOTES_ARCHITECTURE.md` — the "why" behind the Roam + PARA layout

## Getting help

- Workflow or contributor questions: start with `AGENTS.md`
- org-seq bugs or behavior regressions: open an issue in this repo
