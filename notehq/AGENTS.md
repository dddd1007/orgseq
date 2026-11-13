# NoteHQ Scaffolding

This file overrides the repo-root `AGENTS.md` for `notehq/`.

## Purpose

`notehq/` is not org-seq runtime code. It is scaffolding that bootstrap scripts copy into the user's note library (`notes/` under the Emacs directory by default; formerly `~/NoteHQ/`).

Edit this subtree as an end-user deliverable:

- help the user work inside their note library
- preserve migration-friendly behavior
- avoid leaking org-seq repo-development assumptions into user note instructions

## User Context

- The intended user is migrating gradually from Tana, Doom Emacs, Obsidian, and Notion.
- Do not push a forced Markdown-to-Org migration.
- Legacy Markdown in practice/library areas is intentional.
- New notes and drafts start in `00_Inbox/`, the staging layer; kept material is filed into the PARA layers.

## NoteHQ Conventions

- Keep `00_Inbox/` flat apart from `daily/`, `capture/`, and `dashboards/`.
- Use `:ID:` properties and `[[id:...][title]]` links for structured Org notes.
- Daily notes are both thought-stream and task-entry points.
- Dashboard files are read-only query views built from `orgseq-query` dynamic blocks.
- Classification happens via Org tags and node types, not nested subdirectories.
- Saved views are defined in `.orgseq/views.org` (one level-1 heading per view with `VIEW_TYPE`, `VIEW_LAYOUT`, `VIEW_GROUP`, `VIEW_COLUMNS`, `VIEW_SORT`, `VIEW_FILTER`). A view stores a query, never note data.
- The library is synced between devices as plain files; never write device-specific paths or state into it.
- Node types are defined in `.orgseq/types.org` (one level-1 heading per type with `TYPE_TAG`, `TYPE_KEY`, `TYPE_FIELDS`, and optional `NAME_ALL` properties; the heading body is the capture template). A note has a type when it carries that tag; its fields are ordinary Org properties.

## Editing Guidance

- When changing this subtree, think in terms of what will be copied into a user's live NoteHQ.
- Keep examples concrete and migration-aware.
- Avoid instructions that assume the user is editing org-seq source code.
- If org-seq behavior changes in a way that affects NoteHQ workflows, keep this subtree in sync.
