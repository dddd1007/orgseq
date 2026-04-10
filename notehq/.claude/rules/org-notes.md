---
globs: ["00_Roam/**/*.org", "10_Outputs/**/*.org", "20_Practice/**/*.org"]
---

# Org Note Rules

- Every note in 00_Roam/ must have `:ID:` property — never remove or change it
- Use `[[id:...][title]]` links between notes, not `file:` paths
- Classification by supertag, not directory — do NOT create subdirectories in 00_Roam/
- Captures go to `00_Roam/capture/` with `YYYYMMDDTHHmmss-slug.org` naming
- Tasks written in daily notes (`00_Roam/daily/`) are auto-picked up by GTD
- Dashboard files (`00_Roam/dashboards/`) are query-only — never add data to them
- When creating notes, use Chinese if the user's notes are in Chinese
