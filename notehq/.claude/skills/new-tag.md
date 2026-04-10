---
name: new-tag
description: Generate a new org-supertag definition in 00_Roam/supertag-schema.el. Supports named archetypes and Tana/Notion/Obsidian field migration.
user_invocable: true
args: tagspec - "tagname [pattern]" or "from <system>: <description>" or empty for guided mode
---

The user is migrating from prior PKM systems (Tana, Obsidian, Notion, Doom Emacs) and wants to add a new supertag fast. **Speed matters** — they already know what they want; your job is to translate it into the org-supertag schema syntax correctly, not to interview them.

## Invocation modes

### Mode 1 — Direct (fastest)
User types `/new-tag topic entity` or `/new-tag reading event:topic` — generate immediately.

Format: `tagname [pattern]` where pattern is one of:
- `entity` → static object (no `:node` field by default)
- `event:<entity-tag>` → flow entry that links to an entity via `:node`
- `archetype:<name>` → use a named archetype below

### Mode 2 — Migration
User types `/new-tag from tana: ...` or `/new-tag from notion: My Books database with Author, Year, Status fields, Rating 1-5`.

Apply the field translation table (see "Cross-PKM field mapping" below). Generate the closest org-supertag equivalent. Note any fields that lost fidelity (e.g., Notion formula columns become `:string`).

### Mode 3 — Guided
User types `/new-tag` with no args. Read existing schema, show the named archetypes, ask which one fits.

## Steps

1. **Read** `00_Roam/supertag-schema.el` first (it may not exist yet — that's fine, create it with the file header from "Schema file scaffold" below).
2. **Check for collisions**: if the proposed tag name already exists in the file, warn and offer to extend rather than duplicate.
3. **Resolve dependencies**: if generating an event tag with `:node :ref-tag "X"`, check that `X` already exists in the schema. If not, prompt: "X doesn't exist yet. Create it first as an entity tag, or use a placeholder?"
4. **Generate the tag block** using the templates in "Patterns" or "Archetypes" below. Keep field count to 2-4 unless the user explicitly listed more.
5. **Insert at the appropriate location**: entity tags grouped together, event tags grouped together, with section comment headers if the file is being organized for the first time.
6. **Report** what was added, mention `SPC n m T` to reload, and remind the user to `git commit` (the schema is version-controlled with the notes).

## Patterns

### Pattern A — Entity tag (static object)
```elisp
;; ----------------------------------------------------------------
;; ENTITY: <tagname> — <one-line description>
;; ----------------------------------------------------------------
(org-supertag-tag-create "<tagname>"
  :fields '((:name "status"  :type :options :options ("active" "paused" "archived"))
            (:name "started" :type :date)))
```

### Pattern B — Event tag (flow entry)
```elisp
;; ----------------------------------------------------------------
;; EVENT: <tagname> — <one-line description>
;; Links to: <entity-tag>
;; ----------------------------------------------------------------
(org-supertag-tag-create "<tagname>"
  :fields '((:name "<entity-tag>" :type :node :ref-tag "<entity-tag>")
            (:name "date"          :type :date)
            (:name "status"        :type :options :options ("draft" "done"))))
```

## Named archetypes (use these when the user names one)

These are battle-tested across the user's prior PKM platforms. Use them verbatim unless the user adjusts.

### `archetype:topic` — long-running theme
```elisp
(org-supertag-tag-create "topic"
  :fields '((:name "status"   :type :options :options ("active" "paused" "shelved"))
            (:name "started"  :type :date)
            (:name "summary"  :type :string)))
```

### `archetype:reading` — literature note (links to topic)
```elisp
(org-supertag-tag-create "reading"
  :fields '((:name "authors" :type :string)
            (:name "year"    :type :number)
            (:name "topic"   :type :node :ref-tag "topic")
            (:name "status"  :type :options :options ("queued" "reading" "read" "cited"))
            (:name "rating"  :type :options :options ("1" "2" "3" "4" "5"))))
```

### `archetype:person` — contacts / collaborators / students
```elisp
(org-supertag-tag-create "person"
  :fields '((:name "role"     :type :string)
            (:name "context"  :type :options :options ("colleague" "student" "client" "external"))
            (:name "active"   :type :options :options ("yes" "no"))))
```

### `archetype:client` — counseling / therapy / advisory client
```elisp
(org-supertag-tag-create "client"
  :fields '((:name "started"  :type :date)
            (:name "status"   :type :options :options ("intake" "active" "follow-up" "closed"))
            (:name "concerns" :type :string)))
```

### `archetype:session` — meeting / consultation event (links to person/client)
```elisp
(org-supertag-tag-create "session"
  :fields '((:name "client"    :type :node :ref-tag "client")
            (:name "date"      :type :date)
            (:name "modality"  :type :options :options ("in-person" "video" "phone"))
            (:name "followup"  :type :options :options ("none" "task" "next-session"))))
```

### `archetype:project` — bounded deliverable (lighter than 10_Outputs/)
```elisp
(org-supertag-tag-create "project"
  :fields '((:name "deadline" :type :date)
            (:name "status"   :type :options :options ("planning" "active" "blocked" "done"))
            (:name "owner"    :type :node :ref-tag "person")))
```

### `archetype:experiment` — research run (links to topic)
```elisp
(org-supertag-tag-create "experiment"
  :fields '((:name "topic"     :type :node :ref-tag "topic")
            (:name "hypothesis" :type :string)
            (:name "started"   :type :date)
            (:name "status"    :type :options :options ("design" "running" "analysis" "reported"))))
```

### `archetype:course` — taught course (entity)
```elisp
(org-supertag-tag-create "course"
  :fields '((:name "term"     :type :string)
            (:name "audience" :type :string)
            (:name "status"   :type :options :options ("planning" "running" "wrapped"))))
```

### `archetype:lesson` — single class session (links to course)
```elisp
(org-supertag-tag-create "lesson"
  :fields '((:name "course" :type :node :ref-tag "course")
            (:name "date"   :type :date)
            (:name "status" :type :options :options ("draft" "ready" "delivered" "reflected"))))
```

### `archetype:concept` — Zettelkasten atomic concept
```elisp
(org-supertag-tag-create "concept"
  :fields '((:name "domain"    :type :string)
            (:name "maturity"  :type :options :options ("seedling" "budding" "evergreen"))))
```

### `archetype:moc` — Map of Content (Obsidian-style hub note)
```elisp
(org-supertag-tag-create "moc"
  :fields '((:name "scope"   :type :string)
            (:name "status"  :type :options :options ("growing" "stable" "frozen"))))
```

## Cross-PKM field mapping

When the user says "from tana:" / "from notion:" / "from obsidian:", apply this translation:

| Source field type | org-supertag equivalent | Notes |
|---|---|---|
| Tana `field` (text) | `:type :string` | direct |
| Tana `number` | `:type :number` | direct |
| Tana `date` | `:type :date` | direct |
| Tana `instance of` / `:supertag` reference | `:type :node :ref-tag "X"` | the linked-to supertag becomes `:ref-tag` |
| Tana `option` | `:type :options :options (...)` | enumerate the options |
| Tana `checkbox` | `:type :options :options ("yes" "no")` | no native bool |
| Tana `formula` | `:type :string` | manual; org-supertag has no formulas |
| Notion `select` | `:type :options :options (...)` | direct |
| Notion `multi-select` | `:type :string` | enter as `tag1, tag2, tag3`; no native multi |
| Notion `relation` | `:type :node :ref-tag "X"` | single-relation only |
| Notion `rollup` / `formula` | `:type :string` | manual |
| Notion `created time` / `last edited` | omit | use file mtime / org-id timestamp |
| Notion `person` | `:type :node :ref-tag "person"` | requires `person` tag |
| Notion `URL` / `email` / `phone` | `:type :string` | no validation |
| Notion `files & media` | omit | use 30_Library/ + `[[file:...]]` link in note body |
| Notion `rating` | `:type :options :options ("1" "2" "3" "4" "5")` | no native rating |
| Obsidian `dataview field::` | `:type :string` (default) | promote to typed field if usage suggests |
| Obsidian `tag` (`#xxx`) | becomes the supertag itself | not a field |

**Lossy conversions** to flag to the user:
- Multi-select → string (no multi-value field type)
- Formula → string (no computed fields)
- Files → must be moved to 30_Library/ separately
- Created/edited timestamps → not stored as fields; use `org-id` and file metadata

## Schema file scaffold

If `00_Roam/supertag-schema.el` does **not** exist when the skill runs, create it with this header before adding the first tag:

```elisp
;;; supertag-schema.el --- Supertag definitions for NoteHQ -*- lexical-binding: t; -*-
;;
;; Tag patterns:
;;   ENTITY tags — static objects (topic, person, client, course, project)
;;   EVENT tags  — flow entries that link to entities via :node fields
;;
;; Field types: :string :number :date :options :node
;;
;; Reload after editing:  SPC n m T  (my/reload-supertag-schema)
;; Then commit:           git add 00_Roam/supertag-schema.el && git commit
;;
;; Principle: only add a tag after using the default capture template 5+ times
;; for the same kind of note and noticing a shared structure.

(require 'org-supertag)

;; ─────────────────────────────────────────────────────────────────
;; Entity tags
;; ─────────────────────────────────────────────────────────────────



;; ─────────────────────────────────────────────────────────────────
;; Event tags
;; ─────────────────────────────────────────────────────────────────



(provide 'supertag-schema)
;;; supertag-schema.el ends here
```

## Output report format

After writing, report to the user:

```
Added tag: <tagname> (<entity|event>)
File:      00_Roam/supertag-schema.el
Fields:    <comma-separated list>
Links to:  <referenced tag, if event>

Reload in Emacs:  SPC n m T
Commit:           git add 00_Roam/supertag-schema.el && git commit -m "schema: add <tagname>"

Suggested next steps:
- /new-template <key> with filetag :<tagname>: (if you'll capture these often)
- /new-dashboard <name> querying tag <tagname> (after first 3-5 uses)
```

## Principles

- **Trust the user's prior experience**. If they say `archetype:reading` or `from notion: ...`, generate immediately. Don't ask "is this an entity or event tag?" — they already know.
- **Two questions max** in guided mode. More than that wastes their migration energy.
- **Fields ≥ 2, ≤ 5** unless explicitly told otherwise. Easier to add later than to prune.
- **Never speculate**. If a Notion column type maps lossily, say so in the report; don't silently approximate.
- **Match the schema's existing style** if the file already has tag definitions — same comment style, same field order, same naming convention.
