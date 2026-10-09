# Emacs 31.1 Compatibility

org-seq keeps Emacs 30 as its minimum version and treats Emacs 31.1 as a
supported runtime.  This note records the compatibility audit performed on
2026-08-27 so that time-sensitive package conclusions are not mistaken for
permanent guarantees.

## Core changes covered

- Emacs 31 obsoletes `if-let` and `when-let`.  Runtime modules and ERT
  helpers use `if-let*` and `when-let*`, which also work on Emacs 30.
- Terminal Emacs 31 supports child frames.  Corfu therefore uses the native
  implementation when the `tty-child-frames` feature is present;
  `corfu-terminal` remains the fallback for Emacs 30 and older/non-supporting
  terminal builds.
- Emacs 31 includes Org 9.8.  org-seq does not use the renamed
  `org-edit-src-content-indentation` variable.  Its standard LaTeX preview
  calls remain available in Org 9.8.
- The validation runner only compiles and removes bytecode belonging to
  org-seq source roots.  It does not recursively delete `.elc` files from
  unrelated cache or tool directories under the checkout.

## Package follow-up snapshot

The completion stack has explicit upstream Emacs 31 follow-up:

- Corfu documents native terminal child-frame support on Emacs 31.
- Consult accounts for the Emacs 31 completion UI and can use the built-in
  `grep-edit-mode`; the optional `wgrep` integration remains supported.
- Vertico and org-modern have current Emacs 31 compatibility work.
- Posframe can use terminal child frames on Emacs 31, but org-seq does not
  need to force it for Corfu.

The following packages need a more conservative boundary:

- org-supertag 5.9.0 was the current upstream release during this audit, but
  its published CI matrix did not yet include Emacs 31.  org-seq therefore
  retains the existing version-and-hash-gated compatibility layer for the
  installed 5.8.1 source instead of broadening an unverified patch.
- org-fragtog had no explicit Org 9.8 compatibility release during this audit.
  Its preview calls still exist in Org 9.8, so the integration is retained and
  should be rechecked visually after future Org or org-fragtog updates.

Use `M-x my/package-update-all` only with the existing snapshot/rollback
workflow, then run the strict validation command from the README.  A green
source check does not replace visual testing of terminal popups or rendered
LaTeX previews.

## Upstream references

- [Emacs 31 NEWS](https://raw.githubusercontent.com/emacs-mirror/emacs/emacs-31/etc/NEWS)
- [Org 9.8 NEWS](https://raw.githubusercontent.com/emacs-mirror/emacs/emacs-31/etc/ORG-NEWS)
- [Corfu](https://github.com/minad/corfu)
- [Consult](https://github.com/minad/consult)
- [Vertico](https://github.com/minad/vertico)
- [org-modern](https://github.com/minad/org-modern)
- [org-supertag changelog](https://github.com/yibie/org-supertag/blob/main/CHANGELOG.org)
- [org-fragtog](https://github.com/io12/org-fragtog)
