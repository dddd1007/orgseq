---
globs: ["Roam/supertag-schema.el"]
---

# Supertag Schema Rules

- Tag definitions use `(org-supertag-tag-create "name" :fields '(...))`
- Two tag patterns: entity (static objects) and event (flow entries linked via `:node`)
- Field types: `:string`, `:number`, `:date`, `:options`, `:node`
- Start with 2-3 fields per tag; add more only after 5+ uses
- After editing, user must reload in Emacs: `SPC n m T`
- Schema file is version-controlled — suggest `git commit` after changes
