---
name: add-package
description: Add a new Emacs package to the org-seq configuration with proper use-package declaration
user_invocable: true
args: package_name - the name of the package to add
---

# Add Package

Add a new Emacs package to the org-seq configuration following project conventions.

## First decision: `lisp/init-*.el` module or `packages/` subproject?

Before picking a module, decide which side of the divide the package belongs on.

**Add it as a `use-package` block inside an existing `lisp/init-*.el` module** when:

- The package is on MELPA / GNU ELPA and installs cleanly via `:ensure t`
- You are integrating a **3rd-party** package into org-seq (you're not writing the package yourself)
- The package needs non-trivial org-seq-specific defaults (paths, keybindings, integration with other modules)
- You are adding a single `use-package` form with customization; no new elisp files are needed

**Add it as a bundled subproject under `packages/<name>/`** when:

- You are **writing the package yourself** inside org-seq but want to keep the door open to publishing it independently later
- The package has a clean, standalone API (no dependencies on org-seq internals)
- You expect the package to have its own README, changelog, and eventually its own GitHub repo
- The integration layer reduces to a thin `lisp/init-<name>.el` (~50-100 lines) doing nothing but `use-package` plus a few defcustom overrides

For the second case, follow the rules in `.claude/rules/packages-style.md` — notably: no `my/` prefix inside the package, no references to org-seq paths, declare its own `defgroup`, write it so `git mv packages/<name>/ ../<name>/` can graduate it without editing a single line.

## Steps (for a `lisp/init-*.el` integration)

1. **Research the package**: check its source (GNU ELPA, MELPA, or GitHub), dependencies, and any known Windows issues.

2. **Pick the right module** based on the package's purpose. The load order is fixed in `init.el`; see `CLAUDE.md` "Module Load Order" for the rationale. Current modules in load order:

   1. `init-ui.el` — fonts, themes, modeline, olivetti, icons
   2. `init-completion.el` — Vertico stack, Consult, Embark
   3. `init-markdown.el` — Markdown editing, preview, TOC
   4. `init-org.el` — Org base: org-modern, org-appear, org-tempo, evil-org, babel, **local leader** (org-mode-map only); not GTD-specific. Also defines the root path constants (`my/note-home`, `my/roam-dir`, `my/orgseq-dir`) and the `org-seq` customize group
   5. `init-roam.el` — org-roam, org-node/org-mem, dailies, capture templates, org-roam-ui hooks, Doom-derived Evil/vertico advices
   6. `init-gtd.el` — GTD dashboard, `org-agenda-custom-commands`, state machine, inbox/today hooks, org-ql dashboard queries
   7. `init-focus.el` — integration layer for `packages/org-focus-timer/`; thin use-package wrapping the bundled subproject
   8. `init-pkm.el` — org-supertag (bootstrap install + use-package), org-transclusion, org-ql
   9. `init-supertag.el` — supertag schema/dashboard/PARA navigation; depends on `my/roam-dir`
   10. `init-ai.el` — gptel, ob-gptel, claude-code, PKM AI helpers, .orgseq ai-config parsing
   11. `init-dashboard.el` — startup dashboard (emacs-dashboard + custom quotes + vertical centering)
   12. `init-dired.el` — dired + dirvish (override mode, peek, quick-access); defines sidebar helpers consumed by init-workspace
   13. `init-workspace.el` — 3-column layout using dirvish-side + imenu-list + eshell
   14. `init-evil.el` — Evil, **global** `SPC` / `M-SPC` leader, magit, casual, which-key

3. **Write a `use-package` declaration** following these conventions:
   - `:after` for dependencies
   - `:hook` for mode activation
   - `:custom` for settings (uses `customize-set-variable` under the hood)
   - `:bind` for package-local keybindings
   - `:commands` for autoloads
   - `:demand t` only if the package must load at startup (most packages should lazy-load)
   - Prefix all custom functions/variables with `my/`
   - Use `:group 'org-seq` for any `defcustom` you add alongside the package
   - For Windows-specific caveats, write a plain comment like `;; Windows: ...` (no emoji — see elisp-style rule)

4. **If the package is GitHub-only** (not on MELPA), use the unified bootstrap pattern instead of a bifurcated Emacs 29/30 form:

   ```elisp
   ;; Bootstrap install (works on Emacs 29+)
   (unless (package-installed-p 'PKG)
     (condition-case err
         (package-vc-install "https://github.com/AUTHOR/PKG")
       (error (message "WARNING org-seq: failed to install PKG: %s" err))))

   (use-package PKG
     :if (locate-library "PKG")
     :after SOMETHING
     :commands (...)
     :config ...)
   ```

   This pattern is already used for `org-supertag`, `ob-gptel`, `claude-code`, and `which-key`. Don't reintroduce the old `(if (>= emacs-major-version 30) ...)` dual branch.

5. **If the package needs leader-key bindings**, add them in `init-evil.el` under the appropriate SPC group. Cross-check that all function references resolve — the pre-commit hook doesn't catch dangling key bindings.

6. **If the package adds an org-mode local action**, register it under `,` (local leader) in `init-org.el`.

7. **If the package needs its own defcustoms**, use `:group 'org-seq` to keep them in the central customize group.

8. **Verify compilation**: the PostToolUse hook auto-byte-compiles each `.el` on save — watch for `[hook] FAILED` lines and fix immediately. Run `/elisp-lint` for a full-repo verification before considering the task done.

9. **If the package requires a runtime dependency users must install manually** (e.g. an external binary like `rg`, `fd`, `dot`), add a troubleshooting row to `CLAUDE.md` and a prerequisite line to `README.md`.

10. **If the package needs a Windows-specific path or exec tweak**, follow the pattern in `init.el` (`exec-path` block for WinGet/Scoop) rather than scattering platform conditionals across modules.

## Steps (for a new `packages/<name>/` subproject)

1. **Create the directory structure**:
   ```
   packages/<name>/
   ├── <name>.el      # single-file package (for now)
   └── README.md      # package-level docs
   ```

2. **Write `<name>.el` with a proper package header** (see `packages-style.md` for the full template).

3. **Create a thin integration module** at `lisp/init-<name>.el` (~50-100 lines) containing:
   - A forward-declare of any required variables from `init-org.el`
   - A `defcustom my/<name>-path` pointing at `(expand-file-name "packages/<name>" user-emacs-directory)` so the deploy scripts find it
   - A `use-package <name>` block with `:load-path my/<name>-path`, `:if (file-exists-p ...)`, org-seq-specific `:custom` overrides, and `:commands` autoloads
   - A deferred warning (`run-with-idle-timer`) if the package source is missing

4. **Register the new integration module in `init.el`** load order, with a comment explaining where it fits dependency-wise.

5. **Add leader-key bindings** in `init-evil.el`.

6. **Verify both byte-compile paths**: the package file alone (`emacs --batch -Q -L packages/<name> -f batch-byte-compile packages/<name>/<name>.el`) AND the integration module as part of the full project lint.

7. **Update documentation**:
   - `CLAUDE.md` directory layout + module list + (optionally) a design-decision entry
   - `README.md` module table
   - `CONTRIBUTING.md` bundled-subprojects list
   - `doc/GUIDE.md` — add a user-facing chapter if the feature is visible
   - `doc/WORKFLOW.md` — add a key reference entry

8. **No need to update deploy scripts** — `deploy.sh` and `deploy.ps1` already copy all of `packages/` wholesale.

## Anti-patterns to avoid

- Don't add `:ensure t` on a package and ALSO do `(unless (package-installed-p ...) (package-install ...))` — pick one.
- Don't bifurcate Emacs 29/30 use-package forms. If you need different behavior per version, use the bootstrap-install pattern above.
- Don't hardcode `~/NoteHQ/` paths anywhere. Use `my/note-home`, `my/roam-dir`, or `my/orgseq-dir` from `init-org.el` (forward-declared at the top of any module that needs them).
- Don't add emoji or fullwidth punctuation to any `.el` file, strings and comments included. See `elisp-style.md` for the past incident this rule prevents.
- Don't cross the package/config boundary. Code under `lisp/` may reference `my/*` variables freely; code under `packages/` must not.
