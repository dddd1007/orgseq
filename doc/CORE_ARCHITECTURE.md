# Core Architecture Contracts

This document describes the small org-seq-owned interfaces that keep startup,
popups, keybindings, and user overrides observable without turning the
configuration into a general framework.

## Bootstrap And Diagnostics

`init.el` computes the module load order at startup. `my/init-modules-default`
is the set of built-in modules and the tie-break order. `my/init-sort-modules`
does a stable topological sort over `my/init-module-requires`, so a module
loads after everything it requires and unconstrained modules keep their
canonical order. `my/init-module-pins` pins `init-doctor` first and `init-evil`
last; these are positions, not dependencies. A dependency cycle produces an
error-level warning naming the cycle, and the canonical order is used. Every
attempt records the module, status, elapsed seconds, and original error
object. A failed module does not prevent later modules from being attempted.

The dependency data is the runtime source (nothing is parsed at startup). The
block of `my/init-module-requires` between the `BEGIN generated` and `END
generated` markers is generated from the `;; Requires:` headers in `core/` and
`modules/` by `scripts/gen-module-requires.el`, and
`scripts/test-init-loader.el` fails when it is stale. `my/init-check-module-order`
returns violations and startup emits an error-level warning for each one
before loading modules.

User modules extend the same loader. `user/modules.el` sets
`my/init-user-modules`, a list of `(FEATURE . REQUIRES)`; `user/` and
`user/modules/` go on `load-path`, each feature is loaded with `require`
through the guarded loader and placed by the same sort. A user module whose
requirement is unknown or disabled is skipped with a warning instead of
loading out of order.

- `M-x my/init-errors` shows legacy failure details.
- `M-x my/init-report` shows ordered module status and timings, where each
  module came from (built-in, user), its position in the computed
  order, and the modules left out of it with the reason.
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
disables that step. A deployment writes only the distribution files
(`early-init.el`, `init.el`, `ec`, `core/`, `kernel/`, `modules/`, `packages/`,
`bin/`) plus two device-state files, `.org-seq-version` (`<VERSION> (<short commit>)`,
from the `VERSION` file at the repository root) and `.org-seq-source` (plain
`key=value`: `path`, `url` with embedded credentials stripped, `ref`, `commit` of
the checkout deployed from; never a token). The note library, `user/` and
installed packages are never written. `orgseq upgrade` (Linux and macOS) reads
`.org-seq-source`, picks the recorded checkout as it is (never pulling or
resetting it) or else clones/fetches the recorded URL into `.cache/source`, and
runs that source's `deploy.sh --target`; `--check` only compares versions and
exits 10 when an upgrade is available. It runs in the shell launcher before
Emacs starts, and `deploy.sh` replaces `bin/` files by rename so the running
launcher is not corrupted. `deploy.sh --skip-verify` skips the byte-compile gate
and exists for the upgrade test only. `deploy.sh`
therefore backs up the replaced files plus `custom.el` (`--full-backup` copies
the whole target); `deploy.ps1` still copies the whole target. Byte-compilation is a completion gate: missing Emacs or a nonzero compile
result aborts the deployer before it prints the completion summary. The
timestamped backup is the rollback boundary; move a failed target aside before
restoring that backup.

## Git Package Governance

`core/init-packages.el` is the single source inventory for packages installed
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

### Storage, sync, and external access

The note library is `notes/` under the Emacs directory (`my/note-home`), so
org-seq owns its storage and no folder has to be chosen. Startup never asks
a storage question. Copies cross the library boundary through four commands
in `modules/notes/init-sync.el`, none of which modifies its source: import
(`my/storage-import`, copies missing files only), export
(`my/storage-export`), snapshots (`my/storage-snapshot`, dated copies in
`my/snapshot-dir` outside the Emacs directory, taken daily when the library
changed and before imports and full comparisons) and sync.
`my/storage-info` is the read-only status used by `my/storage-status`, the
doctor and `orgseq info`. See [DESIGN.md](DESIGN.md) for the layer model. `modules/notes/init-sync.el`
syncs it with a cloud remote through rclone bisync (WebDAV, OneDrive, Google
Drive): whole Org files are the sync unit, the newer side wins a conflict and
the other version is kept as a `.conflict` copy, and the node index is not
synced because it is a rebuildable local cache (a leftover `org-roam.db` in an old
library is skipped too). Device-local state lives in
`.cache/` under the Emacs directory.

`bin/orgseq` runs a batch Emacs with the same configuration and exposes the
node layer as subcommands and as MCP tools (`orgseq mcp`, stdio transport).
Both call the `my/api-*` functions in `core/orgseq-cli.el`, which write Org
files through the same path as the interactive commands.

### Kernel index

`kernel/` holds the UI-free note kernel. `orgseq-paths.el` defines every
library path. `orgseq-index.el` is the one index of nodes: a SQLite file under
`.cache/` (Emacs' built-in SQLite, no emacsql), filled by a plain-text scan of
the Org files, with an FTS5 trigram table for substring search in any script.
A refresh re-reads only files whose time or size changed, so nothing watches
the file system and edits made by sync or other programs are picked up. The
interactive session, the daemon and `bin/orgseq` share the file. Records are
plists (`:id :title :tags :file :mtime :props :todo :priority :level :olp
:pos`); views, node tables, dashboard blocks, the command line and MCP all
read them through `my/index-records`, `my/index-node`, `my/index-links` and
`my/index-search`. Interactive capture, node find/insert, the backlinks and
forward links buffers and the Daily commands are org-seq's own
(`init-capture`, `init-nodes`, `kernel/orgseq-note.el`); org-roam was removed
on 2026-11-12.

### Views

`modules/notes/init-views.el` turns a query plus a layout into a view (table, list,
board). Saved views are headings in `.orgseq/views.org`. The `orgseq-view`
dynamic block embeds a view in any note; `current` in its filter refers to
the enclosing node.

### Node layer

Notes are nodes: files and headings with an Org ID. `modules/notes/init-nodes.el`
adds node types, fields, table views, the review list, `orgseq-query`
dashboard blocks, and the node action menu on top of the kernel index. It
keeps no database of its own:

- Types are defined in `.orgseq/types.org` under NoteHQ (`my/types-file`). A
  type is an Org tag, a field list, and a capture template.
- Applying a type adds its tag; fields are ordinary Org properties; relations
  are `[[id:]]` links.
- Views and dashboard blocks read the kernel index, which
  `M-x my/index-rebuild` can recreate from Org at any time.

Supertag and its `textui` dependency were removed on 2026-10-22. `init-pkm`
now configures only org-transclusion and org-ql. Old `supertag-query`
dashboard blocks still render for the forms `(tag ...)`, `(property K V)`,
`(recent-days N)`, and `(and ...)`. Existing capture, Daily, PARA, and
GTD remain separate responsibilities.
See [the node model](NOTES_ARCHITECTURE.md#四节点模型与权威边界).

## Popup Policy

`modules/ui/init-popup.el` owns org-seq popup metadata. Each rule has a stable ID,
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

`modules/notes/init-daily.el` owns the persistent left sidebar used by the Daily
Workspace. It is a `special-mode` navigation buffer, not a popup rule:
rendering computes 14 calendar-date records without creating files, and opening
a missing date is the explicit mutation boundary. Each Daily file remains a
plain Org container; capture-ready top-level headings receive normal Org IDs
and become nodes. Saving a Daily file needs no extra hook: the kernel index
re-reads every changed Org file on its next refresh.

`init-workspace` owns the transition between persistent sidebars. Opening
the Daily Workspace closes only Treemacs in the selected frame; opening the
ordinary `SPC l l` workspace closes only the Daily sidebar before restoring
Treemacs and the optional outline. `init-popup` remains responsible only
for bottom/side popup placement and does not register the Daily sidebar.

## Leader-Key Contract

`modules/editor/init-keymap.el` contains two data sets:

- `my/leader-prefixes` records every top-level SPC namespace and description.
- `my/leader-critical-bindings` records a focused cross-section of terminal,
  GTD, focus, node type, AI CLI, and yazi workflows.

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
