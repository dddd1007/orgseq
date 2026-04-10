---
name: new-template
description: Add a capture template to .orgseq/capture-templates.el
user_invocable: true
---

The user wants to add a new org-roam capture template for a specific type of note.

## Steps

1. Read `.orgseq/capture-templates.el` to see existing templates and their key bindings.
2. Read `00_Roam/supertag-schema.el` to check if a corresponding supertag exists.
3. Ask the user (if not specified):
   - Template key (single character, must not conflict with existing: check the file)
   - Description (e.g., "Session", "Student", "Hypothesis")
   - Filetag (e.g., `:session:`, `:student:`)
   - Body structure: what heading skeleton should the template provide?
4. Add the template to the `my/user-capture-templates` list in `.orgseq/capture-templates.el`.
5. If no corresponding supertag exists yet, offer to run `/new-tag`.

## Template format

Templates are added to the list in `.orgseq/capture-templates.el`:

```elisp
("KEY" "Description" plain
 "* Heading 1\n%?\n* Heading 2\n* Heading 3\n"
 :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                    "#+title: ${title}\n#+filetags: :tagname:\n")
 :unnarrowed t)
```

## Body design principles

- Use org headings (`* Heading`) as skeleton — guide the user's thinking
- Put `%?` where the cursor should land after capture
- Keep it minimal: 3-5 headings maximum
- **Headings are for thinking directions; structured data goes in supertag fields**
- Example for a session note:

```elisp
("s" "Session" plain
 "* Basic Info\n- Client: \n- Date: %U\n* Presenting Issue\n%?\n* Session Notes\n* Assessment & Plan\n"
 :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                    "#+title: ${title}\n#+filetags: :session:\n")
 :unnarrowed t)
```

## After editing

Remind the user to reload templates in Emacs: `SPC n m C` (my/reload-capture-templates).
No Emacs restart needed.
