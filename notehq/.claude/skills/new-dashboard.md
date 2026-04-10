---
name: new-dashboard
description: Generate a supertag query dashboard in 00_Roam/dashboards/. Supports named archetypes (kanban, queue, MOC, weekly-pulse) and Notion view translation.
user_invocable: true
args: dashspec - "name [archetype] [tag]" or "from notion: <view description>" or empty for guided mode
---

The user is migrating from PKM systems where they had carefully designed views (Tana queries, Notion databases, Obsidian Dataview tables, Doom Emacs custom agenda commands). They want fast translation into the org-supertag dynamic-block format. **Don't over-question** — show them archetypes and let them pick.

## Invocation modes

### Mode 1 — Direct
- `/new-dashboard reading-queue queue reading` → archetype "queue" applied to tag "reading"
- `/new-dashboard active-clients by-status client` → archetype "by-status" applied to tag "client"
- `/new-dashboard ml-papers moc concept` → MOC index for concept tag with grouping by topic

Format: `name <archetype> <tag>` where archetype is one of: `queue`, `kanban`, `by-status`, `by-date`, `moc`, `weekly-pulse`, `index`, `tagless` (see below).

### Mode 2 — Notion view translation
- `/new-dashboard from notion: my Reading database with Status as kanban grouped by status, sorted by date added`

Map Notion view types to dashboard archetypes (table → simple query, board → kanban, calendar → by-date, gallery → moc, timeline → by-date with start/end columns).

### Mode 3 — Guided
- `/new-dashboard` (no args) → list existing dashboards, list available tags from schema, show archetypes, ask which fits.

## Steps

1. **Read** `00_Roam/supertag-schema.el` to know which tags and fields actually exist. **Never** invent fields that aren't in the schema.
2. **Read** `00_Roam/dashboards/` directory to see existing dashboards and avoid duplicates / naming conflicts.
3. **Resolve the tag**: if user-specified, verify it exists in the schema. If not, prompt: "Tag X doesn't exist yet. Run /new-tag X first, or proceed with placeholder?"
4. **Pick the archetype** (from args or by asking).
5. **Render the dashboard file** at `00_Roam/dashboards/<name>.org` using the archetype template, substituting the actual fields from the schema.
6. **Update `dashboards/index.org`** — append a link to the new dashboard. Create `index.org` if it doesn't exist.
7. **Report** the created file, the queries it contains, and how to refresh in Emacs.

## Archetype templates

All archetypes start with this header:

```org
#+title: <Dashboard Name>
#+startup: content
#+description: <one-line purpose>
#+filetags: :dashboard:
```

> **Note**: `:dashboard:` filetag lets you exclude these from agenda scans if needed and find them with `SPC n /` filtered by tag.

### `queue` — pipeline by status (Kanban-as-list)

Best for: reading lists, task queues, anything with a workflow status.

```org
#+title: <Tag> Queue
#+startup: content
#+description: <Tag> items grouped by workflow status
#+filetags: :dashboard:

* Queued
#+BEGIN: supertag-query :tag <tag> :where (equal status "queued") :columns (title <key-field-1> <key-field-2>) :sort <date-field>
#+END

* In progress
#+BEGIN: supertag-query :tag <tag> :where (equal status "<active-state>") :columns (title <key-field-1> <key-field-2>)
#+END

* Done (last 30 days)
#+BEGIN: supertag-query :tag <tag> :where (and (equal status "<done-state>") (within-days <date-field> 30)) :columns (title <date-field>)
#+END
```

### `kanban` — column board (the closest org-supertag analog to Notion's board view)

Best for: visualization-heavy workflows. **Note**: `org-supertag` has a built-in `supertag-view-kanban` command (`SPC n p k`) that may be a better fit than a static dashboard. Suggest both.

```org
#+title: <Tag> Board
#+startup: content
#+description: Status board for <tag>
#+filetags: :dashboard:

* Tip
For a live interactive kanban, use ~M-x supertag-view-kanban~ instead. This file is the static fallback.

* By status
#+BEGIN: supertag-query :tag <tag> :group-by status :columns (title <key-field>)
#+END
```

### `by-status` — single grouped query

Best for: project trackers, client lists, anything where status is the primary axis.

```org
#+title: <Tag> by Status
#+startup: content
#+description: All <tag> entries grouped by status
#+filetags: :dashboard:

* All entries
#+BEGIN: supertag-query :tag <tag> :group-by status :columns (title <key-field-1> <key-field-2>) :sort <date-field>
#+END
```

### `by-date` — time-grouped (Notion calendar/timeline equivalent)

Best for: events, sessions, lessons, deadlines.

```org
#+title: <Tag> Calendar
#+startup: content
#+description: <Tag> entries by date
#+filetags: :dashboard:

* This week
#+BEGIN: supertag-query :tag <tag> :where (within-days <date-field> 7) :columns (title <date-field> <key-field>) :sort <date-field>
#+END

* Upcoming (next 30 days)
#+BEGIN: supertag-query :tag <tag> :where (and (after <date-field> today) (within-days <date-field> 30)) :columns (title <date-field>) :sort <date-field>
#+END

* Recent past (last 30 days)
#+BEGIN: supertag-query :tag <tag> :where (and (before <date-field> today) (within-days <date-field> 30)) :columns (title <date-field>) :sort <date-field>
#+END
```

### `moc` — Map of Content (Obsidian-style hub)

Best for: a curated index of related concept notes, organized by sub-theme. The user manually adds links over time; the supertag-query provides discovery for orphans.

```org
#+title: <Topic> MOC
#+startup: content
#+description: Map of content for <topic>. Curated above; auto-discovered below.
#+filetags: :dashboard: :moc:

* Curated index
  Add links manually as the area matures:
  - [[id:...][Note 1]]
  - [[id:...][Note 2]]

* Sub-themes
** Theme 1
** Theme 2

* Auto-discovered (untriaged <tag> notes)
#+BEGIN: supertag-query :tag <tag> :where (equal triaged "no") :columns (title)
#+END

* All <tag> notes (for completeness)
#+BEGIN: supertag-query :tag <tag> :columns (title <key-field>) :sort title
#+END
```

### `weekly-pulse` — recent-activity dashboard

Best for: a single "what happened this week" pane that aggregates across multiple tags.

```org
#+title: Weekly Pulse
#+startup: content
#+description: Recent activity across all major tags
#+filetags: :dashboard:

* This week's new notes
#+BEGIN: supertag-query :where (within-days created 7) :columns (title tags created) :sort created
#+END

* This week's <tag-1>
#+BEGIN: supertag-query :tag <tag-1> :where (within-days created 7) :columns (title <key-field>)
#+END

* This week's <tag-2>
#+BEGIN: supertag-query :tag <tag-2> :where (within-days created 7) :columns (title <key-field>)
#+END

* Open threads (drafts older than 7 days)
#+BEGIN: supertag-query :tag draft :where (older-than created 7) :columns (title created)
#+END
```

### `index` — dashboard of dashboards

Special case: this is `dashboards/index.org`. Create / update it whenever a new dashboard is added.

```org
#+title: Dashboards Index
#+startup: showall
#+description: Entry point to all NoteHQ dashboards
#+filetags: :dashboard:

* Dashboards
  - [[file:weekly-review.org][Weekly Review]] — what to look at every Sunday
  - [[file:weekly-pulse.org][Weekly Pulse]] — automated activity digest
  - [[file:reading-queue.org][Reading Queue]] — literature pipeline
  ;; ... auto-appended by /new-dashboard ...

* Quick keys
  - ~SPC n v v~  open this index
  - ~SPC n m d~  create a new dashboard
  - ~C-c C-x C-u~  refresh current dashboard's queries
  - ~SPC n p k~  live kanban view (alternative to static board dashboards)

* How to add a dashboard
  Run ~/new-dashboard <name> <archetype> <tag>~ from Claude Code in this directory.
```

### `tagless` — pure org-ql query (no supertag dependency)

Best for: queries that don't depend on any supertag — e.g., "all notes mentioning 'transformer'", "all notes I edited this week", "all notes with broken links".

```org
#+title: <Name>
#+startup: content
#+description: <purpose>
#+filetags: :dashboard:

* Description
This dashboard uses ~org-ql~ instead of supertag queries because it doesn't depend on tag fields.

To run the queries below in Emacs: place cursor in the SRC block and ~C-c C-c~,
or use ~SPC n q s~ (org-ql-search) interactively.

* All notes mentioning <pattern>
#+begin_src elisp :results output
(org-ql-select '("00_Roam/")
  '(regexp "<pattern>")
  :action '(format "- [[id:%s][%s]]" (org-id-get) (org-get-heading t t t t)))
#+end_src
```

## Notion view → archetype mapping

When the user says "from notion: ...", apply this:

| Notion view type | Archetype | Notes |
|---|---|---|
| Table | `by-status` or `tagless` | direct |
| Board (Kanban) | `kanban` (suggest live `supertag-view-kanban` first) | |
| Calendar | `by-date` | |
| Timeline / Gantt | `by-date` | no Gantt rendering; just date-grouped lists |
| Gallery | `moc` | gallery's "card" abstraction maps best to MOC entries |
| List | `queue` or `by-status` | depends on whether items have a workflow |

When the user says "from tana: live search ...", treat the search predicates as the `:where` clause and ask which tag scope.

## Field substitution rules

When generating from an archetype, replace the placeholders by **reading the schema**:

- `<tag>` — provided by user or asked
- `<key-field-1>`, `<key-field-2>` — pick the **first 2 non-status, non-date fields** from the tag definition
- `<date-field>` — pick the field with `:type :date`; if none, use `created` (file mtime fallback)
- `<active-state>` / `<done-state>` — read the `status` field's `:options` list; pick the most "in progress" sounding one and the most "done" sounding one
- If a placeholder cannot be resolved (e.g. tag has no date field but archetype needs one), **omit that section** rather than guessing, and add a comment: `;; (no :date field on <tag> — section omitted)`

## Index update logic

After creating any non-index dashboard:

1. Check if `00_Roam/dashboards/index.org` exists.
2. If yes, find the `* Dashboards` heading and append a new bullet: `  - [[file:<name>.org][<Title>]] — <description>`.
3. If no, create `index.org` from the `index` archetype and add the new dashboard's bullet.

## Output report format

```
Created dashboard: <name>
File:        00_Roam/dashboards/<name>.org
Archetype:   <archetype-name>
Tag scope:   <tag>
Queries:     <count> supertag-query block(s)
Index:       <updated|created>

Open in Emacs:  SPC n v v  (then pick "<name>")
Refresh:        C-c C-x C-u  (org-update-all-dblocks)
Commit:         git add 00_Roam/dashboards/<name>.org 00_Roam/dashboards/index.org && git commit -m "dashboard: add <name>"

If a query block returns nothing, check:
- the tag actually has notes (try SPC n p s to search the supertag DB)
- the field names in :columns match the schema exactly
- the :where predicate is supported by your org-supertag version (try removing it first)
```

## Principles

- **Read the schema first, always**. Never invent field names.
- **Prefer existing supertag-query syntax over custom org-ql** unless the archetype is `tagless`.
- **Suggest the live alternative** when one exists (e.g., `supertag-view-kanban` for kanban dashboards).
- **Iterate over perfection**: dashboards are cheap to create and adjust. The first version should display *something* even if the predicates are simplified.
- **One archetype per dashboard**: don't combine 4 archetypes into one mega-file. Composition happens via `dashboards/index.org`.
- **Honor the user's PKM vocabulary**: if they say "kanban", give them kanban — don't substitute `by-status` because it's "more org-native".
