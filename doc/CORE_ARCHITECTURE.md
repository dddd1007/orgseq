# Core Architecture Contracts

This document describes the small org-seq-owned interfaces that keep startup,
popups, keybindings, and user overrides observable without turning the
configuration into a general framework.

## Bootstrap And Diagnostics

`init.el` loads a fixed module list. Every attempt records the module, status,
elapsed seconds, and original error object. A failed module does not prevent
later modules from being attempted.

The load-order contract is machine-checkable: `my/init-module-requires`
declares each module's dependencies (mirroring the `;; Requires:` headers in
`lisp/*.el`), `my/init-check-module-order` returns violations, startup emits
an error-level warning for each violation before loading modules, and
`scripts/test-init-loader.el` fails when the declarations, the headers, or
the order disagree.

- `M-x my/init-errors` shows legacy failure details.
- `M-x my/init-report` shows ordered module status and timings.
- `M-x my/doctor` checks requirements without installing, downloading, or
  creating user directories.
- `scripts/check.ps1` is the canonical Windows contributor check.
  It serializes guarded module status, non-passing doctor results, and actual
  normal-state leader bindings into one structured startup audit. The default
  mode reports missing runtime dependencies without downloading them.
  `-PackageUserDir` exposes an explicit deployed package set while keeping
  source validation isolated;
  `-RequireAllModules -RequireDependencies` turns module errors and required
  dependency failures into a deployed-readiness gate. Optional tools remain
  warnings in both modes.

`init-doctor` loads first so the diagnostic commands survive failures in later
feature modules.

## Deployment Safety

`deploy.ps1` and `deploy.sh` resolve their target before any mutation and
refuse a filesystem root, the user's home directory, or any path overlapping
the source tree. PowerShell exposes `SupportsShouldProcess`, so `-WhatIf` is
the canonical dry run. Existing targets are backed up unless the user explicitly
disables that step. Byte-compilation is a completion gate: missing Emacs or a nonzero compile
result aborts the deployer before it prints the completion summary. The
timestamped backup is the rollback boundary; move a failed target aside before
restoring that backup.

## Git Package Governance

`lisp/init-packages.el` is the single source inventory for packages installed
from Git. Each record declares the package symbol, loadable library, source
URL, owner module, and purpose.

`my/vc-package-ensure` is the only bootstrap boundary for those records. It:

- returns immediately when the package is installed or loadable;
- never accesses the network in a noninteractive session;
- records interactive installation errors without aborting startup;
- rejects packages that are not registered.

Feature-specific `use-package` forms stay in the owner module. Use
`M-x my/vc-package-audit` for read-only status, ownership, and source details.
The doctor reports missing or failed records without installing them.

### org-supertag compatibility exception

`init-pkm` contains a narrow compatibility manager for org-supertag 5.8.1 at
revision `7e98ed9ad01f985881afced0fdc4a1ef3fedfa2a`. It accepts only the recorded
original or patched Git blob hashes, creates revision-specific backups outside
the package directory, rewrites through same-directory temporary files, and
removes stale bytecode. Unknown versions, revisions, or source hashes are never
mutated. `M-x my/supertag-rollback-compat-patches` restores the verified
originals. The source-level diff and GPL boundary are recorded in
`patches/org-supertag-5.8.1-emacs-30.patch` and `THIRD_PARTY.md`.

## Popup Policy

`lisp/init-popup.el` owns org-seq popup metadata. Each rule has a stable ID,
buffer matcher, side, slot, size, selection behavior, and optional dedication.
The module translates these plists into normal `display-buffer-alist` entries.

Rules already supplied by `custom.el` or another user module remain first and
therefore keep priority. Re-registering org-seq rules removes only entries with
the `my/popup-rule-id` marker, so unrelated rules are neither reordered nor
deleted.

Use `my/popup-display-buffer` when a workflow needs a per-call size override.
Ghostel popup lifecycle remains in `init-terminal`; the popup module controls
placement, not terminal process management.

## Persistent Daily Sidebar

`lisp/init-daily.el` owns the persistent left sidebar used by the Daily
Workspace. It is a `special-mode` navigation buffer, not a popup rule:
rendering computes 14 calendar-date records without creating files, and opening
a missing date is the explicit mutation boundary. Each Daily file remains a
plain Org container; capture-ready top-level headings receive normal Org IDs
and participate in the existing supertag sync path.

`init-workspace` owns the transition between persistent sidebars. Opening
the Daily Workspace closes only Treemacs in the selected frame; opening the
ordinary `SPC l l` workspace closes only the Daily sidebar before restoring
Treemacs and the optional outline. `init-popup` remains responsible only
for bottom/side popup placement and does not register the Daily sidebar.

## Leader-Key Contract

`lisp/init-keymap.el` contains two data sets:

- `my/leader-prefixes` records every top-level SPC namespace and description.
- `my/leader-critical-bindings` records a focused cross-section of terminal,
  GTD, focus, org-roam, supertag, AI CLI, and yazi workflows.

`init-evil` defines the complete map and then calls
`my/keymap-apply-general-contract`. The contract is applied through the
`general-define-key` function boundary, not by trying to call a generated
general.el macro dynamically.

`M-x my/keymap-audit` compares effective critical bindings with the contract.
ERT also checks uniqueness, descriptions, expected commands, and the absence
of removed EAF bindings.

## Startup Delay Policy

Numeric `use-package :defer` values are allowed only when the delay represents
real background readiness. Every such site must carry a nearby
`NOTE(startup):` comment. `scripts/test-startup-policy.el` enforces this rule.

The current retained delays are:

- org-roam graph and accelerator readiness after the first frame;
- pyim dictionary/input readiness without blocking frame creation;
- dirvish global Dired takeover after UI setup.

Other timers implement concrete behavior such as dashboard recentering,
workspace rebalancing, focus-package loading, update scheduling, or delayed
warning visibility. Do not replace those timers solely to improve an
unmeasured startup number.

## AI Send Boundary

The in-buffer summarize, tag-suggestion, and connection helpers prefer an
active region. If no region is active, `my/ai--get-text` confirms before
returning the entire buffer while `my/ai-confirm-full-buffer-send` is non-nil.
This confirmation is the privacy boundary; callers must not bypass it when
adding another whole-note request.

## User Override Order

`custom.el` remains the explicit user override layer loaded before modules.
Core registries follow these rules:

1. Preserve unrelated user entries.
2. Mark and replace only org-seq-owned entries.
3. Keep final values inspectable through ordinary Emacs variables and commands.
4. Avoid implicit deep merges or hidden profile directories.

When a public customization name changes, use an obsolete alias and document
the migration rather than silently ignoring the old value.
