---
globs: ["Roam/supertag-schema.el"]
---

# Supertag Schema Rules

## Format
- Tag definitions use `(org-supertag-tag-create "name" :fields '(...))`
- File starts with `(require 'org-supertag)` and ends with `(provide 'supertag-schema)`
- Lexical binding header: `;;; supertag-schema.el --- ... -*- lexical-binding: t; -*-`

## Tag patterns
- **Entity tags**: static objects (topic, person, client, course, project) — usually no `:node` field
- **Event tags**: flow entries that link to entities (reading, session, lesson, experiment) — should have at least one `:node :ref-tag "<entity>"` field
- Group entity tags together, event tags together, with `;; ─── Entity tags ───` / `;; ─── Event tags ───` section comments

## Field types
- `:string` — free text
- `:number` — numeric
- `:date` — single date
- `:options` with `:options ("a" "b" ...)` — fixed enumeration
- `:node` with `:ref-tag "X"` — single reference to another tagged node
- **No** multi-value, formula, or computed field types — these are migration losses from Tana/Notion (see `/new-tag` skill for the mapping table)

## Naming
- Tag names: lowercase, singular, no spaces (`reading`, not `Readings` or `reading_list`)
- Field names: lowercase, snake_case if multi-word
- Match the user's prior PKM vocabulary when migrating (if their Notion db was "Reading List", use `reading` and note in a comment that it came from "Reading List")

## Migration awareness
- The user is migrating from Tana / Notion / Obsidian / Doom Emacs. When extending the schema, **honor the source vocabulary** rather than imposing org conventions.
- If a field type is lossy (multi-select → string, formula → string), add an inline comment: `;; was Notion multi-select`
- Reference field (`:node :ref-tag "X"`) requires X to exist first — check before generating

## Discipline
- Start with 2-3 fields per tag; add more only after 5+ uses confirm the pattern
- Don't speculatively add tags — the user's schema grows as their re-encountered patterns from prior systems demand it
- Don't delete tags without confirming with the user (existing notes may reference them)

## After editing
- Reload in Emacs: `SPC n m T` (`my/reload-supertag-schema`)
- Commit: `git add Roam/supertag-schema.el && git commit -m "schema: ..."`
- The schema file is version-controlled with the notes — every change should be a git commit so the schema's evolution mirrors the notes' evolution
