---
name: new-dashboard
description: Create a supertag query dashboard in Roam/dashboards/
user_invocable: true
---

The user wants to create a new dashboard — a read-only query view that aggregates notes by supertag.

## Steps

1. Read `Roam/supertag-schema.el` to know which tags and fields exist.
2. Read `Roam/dashboards/` to see existing dashboards and avoid duplication.
3. Ask the user (if not specified):
   - Dashboard name (will become the filename, e.g., `clients.org`)
   - Which tag(s) to query
   - What columns to show
   - Any grouping or filtering (by status, by date, etc.)
4. Create `Roam/dashboards/<name>.org` with appropriate `supertag-query` blocks.
5. Optionally update `Roam/dashboards/index.org` to add a link to the new dashboard.

## Dashboard file format

```org
#+title: Dashboard Name
#+startup: content
#+description: One-line purpose

* Section Name
#+BEGIN: supertag-query :tag tagname :columns (title field1 field2) :sort field1
#+END

* Another Section
#+BEGIN: supertag-query :tag tagname :where (equal status "active") :columns (title field1)
#+END
```

## Query syntax reference

| Parameter | Example | Meaning |
|-----------|---------|---------|
| `:tag` | `:tag reading` | Filter by tag |
| `:columns` | `:columns (title authors year)` | Fields to show |
| `:where` | `:where (equal status "queued")` | Filter condition |
| `:sort` | `:sort year` | Sort by field |
| `:group-by` | `:group-by topic` | Group results |

## Principles

- Dashboards are **query windows only** — never write data into them
- Keep queries simple; start with 1-2 blocks, iterate after a week of use
- Users refresh dashboards in Emacs with `C-c C-x C-u` or by opening via `SPC n v v`
- If a query predicate isn't supported by the current org-supertag version, use the simplest `:tag tagname` and note that manual filtering may be needed
