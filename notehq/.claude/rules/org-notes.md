---
globs: ["Roam/**/*.org", "Outputs/**/*.org", "Practice/**/*.org"]
---

# Org Note Rules

- Every note in Roam/ must have `:ID:` property — never remove or change it
- Use `[[id:...][title]]` links between notes, not `file:` paths
- Classification by supertag, not directory — do NOT create subdirectories in Roam/
- Captures go to `Roam/capture/` with `YYYYMMDDTHHmmss-slug.org` naming
- Tasks written in daily notes (`Roam/daily/`) are auto-picked up by GTD
- Dashboard files (`Roam/dashboards/`) are query-only — never add data to them
- When creating notes, use Chinese if the user's notes are in Chinese
