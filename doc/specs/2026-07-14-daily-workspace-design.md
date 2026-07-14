# Daily Workspace Design

Date: 2026-07-14

## Status

Approved in conversation. Awaiting the user's review of this written
specification before implementation planning begins.

## Objective

Make Daily Notes the default entry point for org-seq while preserving plain
Org files, org-roam navigation, org-supertag structure, and the existing
Treemacs workspace.

The target experience combines three ideas:

- Tana's Today view as the default place to begin work;
- Roam Research's low-friction chronological Daily Notes workflow;
- org-seq's local-first Org, org-roam, and org-supertag data model.

## Confirmed Product Decisions

- Emacs starts in a dedicated Daily Workspace rather than the Dashboard.
- The center window edits today's ordinary Org file.
- A dedicated left sidebar replaces Treemacs only while using the Daily
  Workspace.
- The sidebar shows the most recent 14 calendar days, including missing days.
- A daily file is a date container; every top-level heading is an independent
  node that can receive an org ID, supertags, and typed fields.
- Capture is a low-friction chronological stream. It does not require choosing
  a supertag before writing.
- The Dashboard remains available and lists Daily Notes before recent files.
- Existing org-roam, Treemacs, Dashboard, and supertag public workflows remain
  available.

## Non-Goals

- Do not copy Tana or Roam's proprietary data model or interface code.
- Do not turn Dashboard buffers into editable Org buffers.
- Do not replace Treemacs globally.
- Do not introduce a new sidebar or calendar package.
- Do not require a supertag before a user can capture text.
- Do not move existing Daily files or rewrite their content.
- Do not create missing historical notes merely by rendering the sidebar.

## Module Architecture

Add `lisp/init-daily.el` after `init-supertag` in the guarded module order.
The module owns Daily-specific orchestration and no lower-level package
internals.

Responsibilities remain divided as follows:

- `init-roam` owns Daily file paths, org-roam dailies configuration, and
  date-based file navigation.
- `init-supertag` and `init-pkm` own structured tags, fields, stores, and sync.
- `init-daily` owns the Daily Workspace, date sidebar, capture-ready cursor,
  and daily-buffer minor mode.
- `init-dashboard` owns the read-only Dashboard presentation.
- `init-workspace` owns startup and transitions between persistent sidebars.
- `init-evil` owns global leader bindings.

This avoids a cycle: `init-daily` may consume roam and supertag functions, but
it does not require Dashboard or workspace code. Later modules call its public
commands.

## Public Interface

The Daily module provides these commands and predicates:

- `my/daily-workspace-open`: open today's capture-ready Daily Workspace.
- `my/daily-workspace-open-date`: open a selected date in the workspace.
- `my/daily-new-node`: append or reuse a capture-ready top-level node.
- `my/daily-sidebar-open`: display the managed Daily sidebar idempotently.
- `my/daily-sidebar-refresh`: recompute and redraw date state.
- `my/daily-buffer-p`: return non-nil for files in the configured dailies
  directory.
- `my/daily-workspace-p`: report whether the current frame has the managed
  Daily layout.

User settings are exposed as `defcustom` values:

- `my/daily-sidebar-days`, default `14`;
- `my/daily-sidebar-width`, with a conservative narrow default;
- `my/daily-auto-prepare-today`, default non-nil.

When `my/daily-new-node` is invoked outside a Daily buffer, it first opens
Today's Daily Workspace and then prepares the node.

## Daily File And Node Model

Daily files retain the existing path and header convention:

```org
#+title: 2026-07-14
#+filetags: :daily:

* 09:20
:PROPERTIES:
:ID:       20260714T092000
:END:
Write here.

* 10:30 #meeting
:PROPERTIES:
:ID:       20260714T103000
:END:
```

Each top-level heading is a distinct org node. `my/daily-new-node` inserts a
heading in `* HH:MM` form, calls `org-id-get-create`, places point after the
timestamp, and saves the structural change before editing begins.

A reusable blank capture node is precisely a top-level timestamp heading that
contains only its ID property drawer. Tags, planning data, body text, child
headings, or other properties make it non-blank. Opening today's workspace
reuses the final blank node; otherwise it appends exactly one new node. This
prevents repeated startup from accumulating empty headings.

Behavior differs deliberately by navigation intent:

- opening Today or invoking `my/daily-new-node` is capture-ready;
- opening an existing historical date from the sidebar is browse-only;
- selecting a missing date is an explicit creation action, so it creates the
  file and its first capture node.

## Sidebar Model

`my/daily-sidebar-mode` derives from `special-mode`. It renders exactly the
current date and the preceding 13 calendar dates, newest first.

Date generation uses calendar arithmetic rather than subtracting fixed
24-hour intervals, so daylight-saving transitions cannot duplicate or skip a
displayed date.

Each row is derived from a pure date record containing at least:

- date/time value;
- display label;
- resolved Daily file path;
- whether the file exists;
- whether the date is today;
- the activation command.

Existing files use a filled marker and missing files use a hollow marker.
Rendering checks the filesystem but never creates files or directories.

Sidebar bindings are local and mnemonic:

| Key | Action |
|---|---|
| `RET` | Open the selected date |
| `t` | Open Today capture-ready |
| `g` | Refresh date/file state |
| `c` | Choose another date through the Org calendar |
| `q` | Close only the Daily sidebar |

The sidebar is displayed as a persistent left side window with an org-seq
window parameter. It is not registered as a transient popup. Reopening it
reuses the existing buffer and window. Closing or replacing it affects only
the Daily sidebar owned by org-seq.

## Workspace And Startup Flow

`init-workspace` becomes the final layout owner:

1. `initial-buffer-choice` resolves today's Daily buffer.
2. Startup layout recognizes a Daily buffer and delegates to
   `my/daily-workspace-open`.
3. The Daily command closes a visible Treemacs window in the current frame,
   selects the ordinary editor window, visits the requested Daily file, and
   opens the Daily sidebar.
4. Opening the ordinary workspace closes the Daily sidebar before restoring
   Treemacs and the optional outline.

Both transitions are idempotent. They do not call `delete-other-windows` on
unrelated frames and do not delete unrelated side windows or popup buffers.

## Dashboard Integration

Dashboard remains a read-only secondary home at `SPC l d`. Add a custom Daily
item generator and make it the first item:

```elisp
((daily . 5)
 (recents . 5))
```

The section shows Today followed by recent calendar dates and opens them
through the same Daily Workspace commands. The existing navigator's Today
button also opens the complete workspace. No Dashboard callback edits a Daily
file in place.

## Keybinding Contract

Preserve existing dailies navigation and add only the missing workspace and
append actions:

| Key | Command |
|---|---|
| `SPC n d d` | `my/daily-workspace-open` |
| `SPC n d a` | `my/daily-new-node` |
| `SPC n d y` | Existing yesterday navigation |
| `SPC n d T` | Existing tomorrow navigation |
| `SPC n d f` | Existing date picker |
| `SPC n d p` | Previous existing Daily Note |
| `SPC n d n` | Next existing Daily Note |
| `SPC l d` | Dashboard |
| `SPC l l` | Ordinary Treemacs workspace |

The critical-key registry must include the new Daily workspace and append
bindings so `M-x my/keymap-audit` checks their effective Evil normal-state
resolution.

## Supertag Integration

The current org-supertag sync root already includes `my/roam-dir`, so the
`daily/` subtree remains in scope. Daily nodes use normal Org IDs and existing
commands such as `, # a`, `, # e`, and `, # x`; the Daily module does not write
supertag storage directly.

`my/daily-note-mode` installs a buffer-local after-save hook. When the existing
supertag scheduler is available, the hook requests its debounced incremental
sync. When org-supertag is absent or failed to load, saving remains successful
and the missing integration is left visible through existing diagnostics.

## Error Handling And Mutation Boundaries

- Sidebar rendering and date calculation are read-only.
- Note creation occurs only during startup Today activation, an explicit Today
  action, or activation of a missing date.
- Note files use the centralized dailies path under `my/roam-dir`.
- A missing or non-writable NoteHQ directory produces an actionable user error
  before partial content is written.
- A Daily sidebar failure does not make the Daily Org buffer unusable.
- A supertag scheduling failure is reported without aborting save or startup.
- Repeated workspace commands do not duplicate windows, hooks, IDs, or blank
  capture nodes.
- No command modifies PATH, package state, user schema, or historical note
  contents unrelated to the selected date.

## Test Strategy

Add focused ERT coverage before implementation behavior:

1. recent-date records contain exactly 14 consecutive calendar dates;
2. file existence is classified without creating any path;
3. activating a missing date creates only that date's file;
4. a new capture heading receives an Org ID;
5. a final blank capture node is reused;
6. a non-blank final node causes one new node to be appended;
7. opening an existing historical date does not append a node;
8. repeated workspace opening reuses one sidebar window;
9. ordinary workspace transition removes only the Daily sidebar;
10. saving a Daily buffer requests the existing debounced supertag sync;
11. Dashboard orders Daily before recent files;
12. leader-key audit resolves the Daily workspace and append commands.

All tests use a temporary `ORG_SEQ_NOTE_HOME` or temporary directory and must
leave user notes unchanged. Final validation includes focused ERT, the complete
ERT suite, full repository byte compilation, batch startup, the strict deployed
readiness gate, `git diff --check`, and confirmation that no `.elc` files remain.

## Documentation Changes

Implementation synchronizes:

- `README.md` for the default entry point and keys;
- `doc/WORKFLOW.md`, `doc/GUIDE.md`, and `doc/TUTORIAL.md` for the Daily-first
  mental model and workspace transitions;
- `CONTRIBUTING.md` and `AGENTS.md` for the updated module order;
- `doc/CORE_ARCHITECTURE.md` for the persistent Daily sidebar boundary.

## Completion Criteria

The feature is complete only when:

1. startup opens a capture-ready Today buffer with one Daily sidebar;
2. the sidebar shows 14 natural days and visibly distinguishes missing files;
3. historical browsing does not silently append content;
4. Daily capture nodes receive IDs and accept normal supertag operations;
5. ordinary Treemacs and Dashboard workflows remain available;
6. repeated transitions are idempotent and preserve unrelated windows;
7. automated keymap, Dashboard, filesystem, node, sync, and layout tests pass;
8. full isolated and strict deployed validation pass without generated
   artifacts or user-note changes;
9. documentation and runtime behavior describe the same Daily-first workflow.

## References

- Tana Today: https://tana.inc/learn/features/today
- Tana interface and sidebar: https://tana.inc/learn/features/interface
- Org-roam dailies manual: https://www.orgroam.com/manual.html#Org_002droam-Dailies
- Roam Research: https://roamresearch.com/
