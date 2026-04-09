---
name: weekly-review
description: Summarize recent notes and suggest review actions
user_invocable: true
---

The user wants help with their weekly review — summarizing recent activity and identifying actions.

## Steps

1. Find recent daily notes:
   ```bash
   ls -t Roam/daily/*.org | head -7
   ```

2. Read each daily note from the past week. Extract:
   - Tasks created (TODO/PROJECT/NEXT lines)
   - Tasks completed (DONE lines)
   - Thoughts and observations (timestamped entries)
   - Links to extracted Roam nodes

3. Find recently created Roam notes:
   ```bash
   find Roam/capture/ -name "*.org" -newer Roam/daily/$(date -d '7 days ago' +%Y-%m-%d).org 2>/dev/null | head -20
   ```

4. Read `Roam/supertag-schema.el` to understand the tag system.

5. Generate a review report with these sections:

## Report format

```markdown
## Weekly Review: YYYY-MM-DD to YYYY-MM-DD

### Activity Summary
- X daily notes written
- Y new Roam nodes created
- Z tasks completed / W tasks created

### Key Themes
- Theme 1: brief description
- Theme 2: brief description

### Open Threads
- Tasks still in TODO/NEXT state (list them)
- Ideas mentioned but not yet extracted to Roam nodes

### Suggested Actions
- [ ] Notes that might benefit from supertag fields
- [ ] Notes that should be linked to each other
- [ ] Thoughts worth extracting to standalone Roam nodes
- [ ] Outputs/ projects that may need attention
- [ ] Tags that might be worth defining (if a pattern repeats 5+ times)
```

## Principles

- Report in the user's language (Chinese if their notes are in Chinese)
- Be specific: cite actual note titles and content, not generic advice
- Focus on **connections** the user might have missed
- Respect the "5 times before structuring" rule — don't suggest tags prematurely
- If a dashboard exists at `Roam/dashboards/weekly-review.org`, mention it as the Emacs-native alternative
