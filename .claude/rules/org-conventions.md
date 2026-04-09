---
globs: ["notehq/**/*.org", "**/*.org"]
---

# Org File Conventions

## Note Structure
- Every Roam note must have a `:PROPERTIES:` drawer with `:ID:` (timestamp format `YYYYMMDDTHHmmss`)
- File header: `#+title:` is mandatory; `#+filetags:` for classification
- Captures land in `Roam/capture/` with timestamp-prefixed filenames
- Daily notes in `Roam/daily/YYYY-MM-DD.org` with `#+filetags: :daily:`

## Linking
- Use `[[id:...][title]]` for inter-note links (not `file:` links)
- Never remove or change existing `:ID:` properties — this breaks all references

## Classification
- Tags via supertag, not directories — Roam/ is flat
- Tag definitions in `Roam/supertag-schema.el`, not in org files
- Only add a new tag after using default template 5+ times for the same pattern

## Dashboards
- Location: `Roam/dashboards/*.org`
- Read-only query views only — never write data into dashboard files
- Use `#+BEGIN: supertag-query` dynamic blocks for live queries

## TODO Keywords
- Sequence: `PROJECT(P) TODO(t) NEXT(n) IN-PROGRESS(i) WAITING(w@/!) SOMEDAY(s) | DONE(d!) CANCELLED(c@)`
- Tasks in daily notes are auto-scanned by GTD agenda
