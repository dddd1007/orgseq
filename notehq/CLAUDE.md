# NoteHQ — Personal Knowledge Management Library

This is a personal knowledge management (PKM) note library managed by **org-seq** (an Emacs configuration). It uses Org-mode, org-roam, and org-supertag.

## User context (read this first)

The user is **migrating from prior PKM systems** — Tana, Doom Emacs, Obsidian, and Notion — into this org-seq + NoteHQ setup. They are an experienced PKM practitioner, not a beginner.

What this means for you (Claude Code):

- **Honor existing patterns**. If the user mentions a Tana supertag, an Obsidian dataview, or a Notion database, translate it faithfully — don't reinvent.
- **Speed > interrogation**. Two questions max before generating something. The user already knows what they want; they just need the syntax translated.
- **Markdown shadow library is intentional**. Files under `Practice/`, `Assets/`, and elsewhere may be `.md` rather than `.org`. These are **historical work from prior systems** — do **not** suggest converting them en masse. Treat them as archives that the user reads but doesn't actively maintain in the org-roam graph.
- **Migration is gradual**. New atomic notes go into `Roam/capture/` as `.org`; legacy work stays where it is. Don't pressure the user to "complete the migration" — they decide the pace.
- **Schema is empty by design (initially)**. `Roam/supertag-schema.el` may not exist yet. The user will add tags as they re-encounter patterns from their prior systems. The `/new-tag` skill is the primary entry point and supports `archetype:` and `from <system>:` modes for fast translation.

## Directory Structure

```
~/NoteHQ/
├── Roam/                    ← Atomic notes layer (org-roam indexed)
│   ├── daily/               ← Daily notes: thought stream + task entry
│   ├── capture/             ← All captured notes (flat, timestamp-prefixed)
│   ├── dashboards/          ← Query-only dashboard files (read-only views)
│   └── supertag-schema.el   ← Tag definitions (entity/event tags with typed fields)
├── Outputs/                 ← Deliverable projects (bounded lifetime)
├── Practice/                ← Long-term responsibility domains
├── Library/                 ← Reference materials (PDFs, datasets, snippets)
│   ├── bibliography/
│   ├── datasets/
│   ├── snippets/
│   ├── references/
│   └── pdfs/
├── Archives/                ← Completed or paused work
└── .orgseq/                 ← Configuration
    ├── ai-config.org        ← AI backend/model settings
    └── capture-templates.el ← User-defined capture templates
```

## Key Conventions

### Org File Format
- All structured notes use `.org` format (not Markdown)
- Every Roam note has a unique `:ID:` property (timestamp format `YYYYMMDDTHHmmss`)
- File naming: `YYYYMMDDTHHmmss-slug.org` in `Roam/capture/`
- Links between notes use `[[id:...][title]]` format

### Classification: Tags, Not Directories
- **Roam/ is flat** — no subdirectories for categories
- Classification is done via **supertag** (structured tags with typed fields)
- Tag definitions live in `Roam/supertag-schema.el`
- Two tag patterns:
  - **Entity tags** (static objects): topic, client, student...
  - **Event tags** (flow entries, linked to entities via `:node` fields): reading, session, meeting...

### Daily Notes
- Path: `Roam/daily/YYYY-MM-DD.org`
- Serve as **thought stream** (timestamped entries) AND **task entry point** (TODO/PROJECT items)
- Tasks written in daily notes are automatically picked up by the GTD system
- Valuable thoughts are extracted to standalone Roam nodes via `id:` links

### PARA Layers
| Layer | Purpose | Lifetime |
|-------|---------|----------|
| `Outputs/` | Deliverable projects (papers, courses, grants) | Weeks to months |
| `Practice/` | Long-term roles and responsibilities | Years |
| `Library/` | Consumed materials (not actively maintained) | Long-term |
| `Archives/` | Completed or paused work | Permanent |

### Dashboards
- Location: `Roam/dashboards/*.org`
- **Read-only query windows** — never write data directly into dashboards
- Use `#+BEGIN: supertag-query` dynamic blocks for live queries
- Refresh with `C-c C-x C-u` (org-update-all-dblocks)

## Important Rules

### DO
- Keep Roam/ flat (daily/, capture/, dashboards/ only)
- Use `id:` links to connect notes across layers
- Use supertag fields for structured data (not ad-hoc properties)
- Write tasks in daily notes (they auto-appear in GTD views)
- Archive completed Outputs projects to Archives/

### DO NOT
- Create new subdirectories inside Roam/ (use tags instead)
- Edit dashboard files to add data (they are query views only)
- Remove or change `:ID:` properties (breaks all links)
- Put binary files in Roam/ (use Library/ instead)
- Modify `.orgseq/` files without understanding the format

## Supertag Schema

Tag definitions in `Roam/supertag-schema.el` use this pattern:

```elisp
(org-supertag-tag-create "tagname"
  :fields '((:name "field1" :type :string)
            (:name "field2" :type :options :options ("opt1" "opt2"))
            (:name "related" :type :node :ref-tag "other-tag")))
```

Field types: `:string`, `:number`, `:date`, `:options`, `:node` (reference to another tagged node).

**When to add a new tag**: You've used the default template 5+ times for the same type of note and notice a common structure. Do NOT pre-create tags speculatively.

## Capture Templates

User-defined templates in `.orgseq/capture-templates.el` set the variable `my/user-capture-templates`. Format:

```elisp
(setq my/user-capture-templates
      '(("KEY" "Description" plain "BODY-TEMPLATE"
         :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: :tagname:\n")
         :unnarrowed t)))
```

## Useful Skills

| Skill | Purpose | Fast invocation example |
|-------|---------|-------------------------|
| `/new-tag` | Generate a supertag definition. Supports archetypes and Tana/Notion/Obsidian field migration. | `/new-tag reading event:topic` or `/new-tag from notion: my Books database with Author, Year, Status` or `/new-tag archetype:client` |
| `/new-dashboard` | Create a dashboard query file. Supports kanban / queue / by-status / by-date / MOC / weekly-pulse archetypes and Notion view translation. | `/new-dashboard reading-queue queue reading` or `/new-dashboard from notion: client board grouped by status` |
| `/new-template` | Add an org-roam capture template to `.orgseq/capture-templates.el`. | `/new-template r reading` |
| `/weekly-review` | Summarize recent daily notes and suggest review actions. | `/weekly-review` |
| `/archive-project` | Move a completed `Outputs/` project to `Archives/YYYY-name/`. | `/archive-project grant-2026` |

**Tip for the migration phase**: when re-creating a tag, dashboard, or template that you used in a prior PKM system, tell the skill the source format directly (`/new-tag from tana: ...`). Faster than describing it from scratch.
