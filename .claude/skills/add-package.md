---
name: add-package
description: Add a new Emacs package to the org-seq configuration with proper use-package declaration
user_invocable: true
args: package_name - the name of the package to add
---

# Add Package

Add a new Emacs package to the org-seq configuration following project conventions.

## Steps

1. Research the package: check its source (GNU ELPA, MELPA, or GitHub), dependencies, and any known Windows issues
2. Determine which module file (`lisp/init-*.el`) it belongs in based on its purpose:
   - `init-evil.el` - keybinding and modal editing related
   - `init-completion.el` - completion and search related
   - `init-org.el` - org-mode base features
   - `init-roam.el` - org-roam and PKM note-taking
   - `init-pkm.el` - extended PKM tools (transclusion, query, tags)
   - `init-ui.el` - visual: fonts, themes, modeline, icons
3. Write a `use-package` declaration following these conventions:
   - Use `:after` for dependencies
   - Use `:hook` for mode activation
   - Use `:custom` for setq where possible
   - Use `:bind` for keybindings
   - Add `:demand t` only if immediate loading is required
   - Prefix custom functions with `my/`
   - Add Windows-specific notes with `;;` comments and ⚠️ marker
4. If the package needs leader key bindings, add them in `init-evil.el` under the appropriate SPC group
5. Run byte-compile check on the modified file
