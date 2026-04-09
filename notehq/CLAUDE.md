# NoteHQ — Personal Knowledge Management Library

This is a personal knowledge management (PKM) note library managed by **org-seq** (an Emacs configuration). It uses Org-mode, org-roam, and org-supertag.

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

| Skill | Purpose |
|-------|---------|
| `/new-tag` | Define a new supertag in supertag-schema.el |
| `/new-dashboard` | Create a dashboard query file |
| `/new-template` | Add a capture template |
| `/weekly-review` | Summarize recent activity and suggest actions |
| `/archive-project` | Move an Outputs/ project to Archives/ |
