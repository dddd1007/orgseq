# NoteHQ Scaffolding

This file overrides the repo-root `AGENTS.md` for `notehq/`.

## Purpose

`notehq/` is not org-seq runtime code. It is scaffolding that bootstrap scripts copy into a user's `~/NoteHQ/`.

Edit this subtree as an end-user deliverable:

- help the user work inside their note library
- preserve migration-friendly behavior
- avoid leaking org-seq repo-development assumptions into user note instructions

## User Context

- The intended user is migrating gradually from Tana, Doom Emacs, Obsidian, and Notion.
- Do not push a forced Markdown-to-Org migration.
- Legacy Markdown in practice/library areas is intentional.
- New structured atomic notes belong in `00_Roam/`.

## NoteHQ Conventions

- Keep `00_Roam/` flat apart from `daily/`, `capture/`, and `dashboards/`.
- Use `:ID:` properties and `[[id:...][title]]` links for structured Org notes.
- Daily notes are both thought-stream and task-entry points.
- Dashboard files are read-only query views.
- Classification happens via supertags, not nested roam subdirectories.

## Editing Guidance

- When changing this subtree, think in terms of what will be copied into a user's live NoteHQ.
- Keep examples concrete and migration-aware.
- Avoid instructions that assume the user is editing org-seq source code.
- If org-seq behavior changes in a way that affects NoteHQ workflows, keep this subtree in sync.
