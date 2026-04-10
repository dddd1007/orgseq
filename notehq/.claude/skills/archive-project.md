---
name: archive-project
description: Move a completed 10_Outputs/ project to 40_Archives/
user_invocable: true
---

The user wants to archive a completed or paused project from 10_Outputs/ to 40_Archives/.

## Steps

1. List current projects:
   ```bash
   ls -d 10_Outputs/*/
   ```

2. Ask the user which project to archive (if not specified).

3. Determine the archive name. Convention: `40_Archives/YYYY-project-name/`
   - Use the current year prefix for dating
   - Keep the original directory name

4. Check for any unresolved tasks in the project:
   ```bash
   grep -rn "^\*.*\(TODO\|NEXT\|IN-PROGRESS\|WAITING\)" 10_Outputs/project-name/ 2>/dev/null
   ```
   If found, warn the user and ask whether to proceed or resolve them first.

5. Move the project:
   ```bash
   mv 10_Outputs/project-name 40_Archives/$(date +%Y)-project-name
   ```

6. Report what was moved and any remaining references:
   ```bash
   grep -rn "project-name" 00_Roam/ --include="*.org" 2>/dev/null | head -10
   ```
   If Roam notes link to files in the old path, note that `id:` links still work (org-roam uses IDs, not file paths), but `file:` links may need updating.

## Principles

- Always check for open tasks before archiving
- Use year prefix for archive directories (`2026-project-name`)
- `id:` links survive moves (they're stored in org-roam DB), but `file:` links break
- After archiving, the project no longer appears in GTD agenda views (40_Archives/ is excluded from agenda scan)
- The user can always un-archive by moving back to 10_Outputs/
