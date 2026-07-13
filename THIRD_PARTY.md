# Third-Party Provenance

org-seq is distributed under the MIT License. This file records source-level
adaptations separately from design-only inspiration so future changes can keep
license and attribution boundaries explicit.

## Source-Level Adaptations

| Upstream | License | Local file | Adaptation |
|---|---|---|---|
| [Doom Emacs](https://github.com/doomemacs/doomemacs), historical Org/org-roam integration | MIT | `lisp/init-roam.el` | The Evil insertion-position advice and Vertico candidate-width advice were adapted to ordinary `define-advice` forms, renamed with the `my/` prefix, and detached from Doom macros and module APIs. |
| [Doom Emacs](https://github.com/doomemacs/doomemacs), Org appearance defaults | MIT | `lisp/init-org.el` | Small org-modern checkbox and hidden-star compatibility adjustments were retained in native `use-package` configuration without Doom macros. |

The local files retain comments beside these adaptations. No Doom package
manager, macro layer, profile loader, popup DSL, or module runtime is included.

## Design-Only Inspiration

The following work is independently implemented for org-seq. No source code
from these entries was copied during the 2026-07-13 optimization.

| Upstream | License | design-only ideas reimplemented locally |
|---|---|---|
| [Doom Emacs](https://github.com/doomemacs/doomemacs) | MIT | Observable module loading, actionable diagnostics, centralized popup policy, and small core interfaces. |
| [Spacemacs](https://github.com/syl20bnr/spacemacs) | GPL-3.0 | Mnemonic leader namespaces, discoverable command groups, and consistent local-leader concepts. No GPL implementation code was copied. |
| [LazyVim](https://github.com/LazyVim/LazyVim) | Apache-2.0 | Data-first metadata, explicit ownership, conditional activation, and documented override precedence. No Lua was translated line by line. |
| [GNU Emacs](https://www.gnu.org/software/emacs/manual/) | GPL-3.0-or-later | Built-in `use-package`, `display-buffer-alist`, ERT, byte compilation, and batch startup mechanisms are used through their public interfaces. |

## External Packages

Third-party packages installed through package.el or package-vc remain separate
works and are not vendored into this repository. Their source URLs and owning
org-seq modules are inspectable with `M-x my/vc-package-audit`. In particular,
[Ghostel](https://dakra.github.io/ghostel/) is the terminal dependency; its
source is not copied into org-seq.

## Maintenance Rule

Before directly copying or closely translating a new upstream fragment:

1. confirm the exact upstream file and revision;
2. confirm license compatibility with the repository license;
3. add the upstream URL, license, local file, and adaptation note here;
4. preserve any notices required by the upstream license;
5. reconsider the repository license before incorporating GPL-covered
   implementation code from Spacemacs or another GPL project.
