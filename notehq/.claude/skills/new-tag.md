---
name: new-tag
description: Define a new supertag in supertag-schema.el
user_invocable: true
---

The user wants to add a new structured tag (supertag) to their PKM system.

## Steps

1. Read `Roam/supertag-schema.el` to understand existing tags and patterns.
2. Ask the user (if not already specified):
   - Tag name (lowercase, no spaces)
   - Is it an **entity tag** (static object: topic, client, student) or **event tag** (flow entry: reading, session, meeting)?
   - What fields does it need? (Keep to the minimum — only fields the user has repeatedly wanted to query)
   - For event tags: which entity tag should it link to via a `:node` field?
3. Add the new `org-supertag-tag-create` block to `Roam/supertag-schema.el`, following the existing style.
4. If the tag would benefit from a capture template, also offer to run `/new-template`.

## Tag creation format

```elisp
;; ----------------------------------------------------------------
;; ENTITY or EVENT tag
;; tagname — one-line description
;; ----------------------------------------------------------------
(org-supertag-tag-create "tagname"
  :fields '((:name "field1" :type :string)
            (:name "field2" :type :options :options ("opt1" "opt2" "opt3"))
            (:name "related" :type :node :ref-tag "entity-tag")))
```

## Field type reference

| Type | Syntax | Use for |
|------|--------|---------|
| `:string` | `(:name "x" :type :string)` | Free text |
| `:number` | `(:name "x" :type :number)` | Numeric values |
| `:date` | `(:name "x" :type :date)` | Dates |
| `:options` | `(:name "x" :type :options :options ("a" "b"))` | Fixed choices |
| `:node` | `(:name "x" :type :node :ref-tag "tag")` | Link to another tagged node |

## Principles

- Fields should answer questions the user **already repeatedly needs to query** — not hypothetical ones
- Entity tags are relatively static; event tags flow in and link to entities
- Start with 2-3 fields; add more only after using the tag 5+ times
- After editing, remind the user to reload: `SPC n m T` in Emacs
