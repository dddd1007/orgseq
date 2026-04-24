;;; init-org.el --- Org-mode base configuration -*- lexical-binding: t; -*-

(defvar org-indent-indentation-per-level)
(defvar org-agenda-prefix-format)
(defvar org-agenda-window-setup)
(defvar pangu-spacing-real-insert-separator)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 0: org-seq customization group
;; ═══════════════════════════════════════════════════════════════════════════

(defgroup org-seq nil
  "org-seq: Modular Emacs PKM configuration."
  :group 'convenience
  :prefix "my/")

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Core PKM directory
;; ═══════════════════════════════════════════════════════════════════════════

(defcustom my/note-home (let ((dir (expand-file-name "NoteHQ/" "~/")))
                          (if (file-directory-p dir) (file-truename dir) dir))
  "Root directory for all PKM content (Roam atomic layer + PARA layers).
Changing this requires restarting Emacs for derived paths
\(`my/roam-dir', `my/orgseq-dir') to take effect."
  :type 'directory
  :group 'org-seq)

(defcustom my/orgseq-dir (expand-file-name ".orgseq/" my/note-home)
  "Per-library personalized configuration directory.
Analogous to .vscode/ or .cursor/ — stores non-sensitive settings
\(AI backends, capture templates) that customize org-seq behavior
per note library.  Distinct from API keys, which stay in `auth-source'."
  :type 'directory
  :group 'org-seq)

(defcustom my/roam-dir (expand-file-name "00_Roam/" my/note-home)
  "Atomic-notes layer (org-roam-directory equivalent).
Used by `org-roam-directory', `org-mem-watch-dirs',
`org-supertag-sync-directories', and the AI context files
\(purpose.org, schema.org, overview.org).

The \"00_\" numeric prefix exists so that the NoteHQ directory
layers sort in workflow priority order (00_Roam first, then
10_Outputs / 20_Practice / 30_Library / 40_Archives) when the
the sidebar displays them alphabetically."
  :type 'directory
  :group 'org-seq)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Org base configuration
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org
  :demand t
  :config
  (setq org-startup-indented t
        org-indent-indentation-per-level 2)

  ;; Visual line wrapping keeps prose buffers readable without hard-wrapping.
  ;; Without this, CJK paragraphs get hard-clipped at the window edge.
  (add-hook 'org-mode-hook #'visual-line-mode)

  (setq org-startup-folded 'content)
  (setq org-hide-leading-stars t)
  ;; Ellipsis: "…" is the community mainstream choice — compact and unobtrusive.
  (setq org-ellipsis " …")

  (setq org-return-follows-link t
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-fold-catch-invisible-edits 'show-and-error
        org-pretty-entities t
        org-hide-emphasis-markers t)

  ;; Highlight LaTeX fragments with native fontification.
  ;; NOTE: `script' renders sub/superscripts as raised/lowered glyphs,
  ;; which breaks valign's pixel-width alignment in tables.  Omitted
  ;; here; once a LaTeX distribution is installed, org-fragtog renders
  ;; full formulae as images (which valign handles correctly).
  (setq org-highlight-latex-and-related '(native entities))

  (setq org-log-done 'time
        org-log-into-drawer t)

  (setq org-todo-keywords
        '((sequence "PROJECT(P)" "TODO(t)" "NEXT(n)" "IN-PROGRESS(i)"
                    "WAITING(w@/!)" "SOMEDAY(s)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))

  (setq org-enforce-todo-dependencies t)

  (setq org-agenda-prefix-format
        '((agenda . " %i %?-12t% s")
          (todo   . " ")
          (tags   . " ")
          (search . " %i %-12:c")))
  (setq org-agenda-window-setup 'current-window)

  ;; Refile
  (setq org-refile-targets '((nil :maxlevel . 3)
                              (org-agenda-files :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

  ;; Tags
  (setq org-auto-align-tags nil
        org-tags-column 0)

  ;; Only inherit @context tags — avoids tag noise in agenda
  (setq org-use-tag-inheritance "^@")

  ;; ---- Babel: enable code execution in org blocks ----
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)
     (python . t)))
  (setq org-confirm-babel-evaluate nil))

;; ---- org-tempo: quick block insertion (<el TAB → src emacs-lisp) ----
(use-package org-tempo
  :ensure nil
  :after org
  :config
  (dolist (item '(("sh"  . "src sh")
                  ("el"  . "src emacs-lisp")
                  ("py"  . "src python")
                  ("yml" . "src yaml")
                  ("js"  . "src javascript")))
    (add-to-list 'org-structure-template-alist item)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Visual enhancement
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq org-modern-star '("◉" "○" "◈" "◇" "⁕")
        org-modern-table nil             ; valign handles table alignment
        org-modern-block-fringe 2        ; subtle fringe marker for src blocks
        org-modern-keyword t             ; prettify #+KEYWORD lines
        org-modern-tag t                 ; badge-style inline tags
        org-modern-label-border 1        ; thin border for tag/priority badges
        org-modern-priority t            ; styled priority cookies
        org-modern-todo t                ; styled TODO keywords
        org-modern-block-name t          ; prettify #+BEGIN_/#+END_ labels
        org-modern-list '((?- . "•")     ; dash → bullet
                          (?+ . "◦")     ; plus → open bullet
                          (?* . "‣"))    ; asterisk → triangle
        org-modern-horizontal-rule t     ; styled -----  separators
        org-modern-progress '("○" "◔" "◑" "◕" "●") ; progress cookies [2/5]
        org-modern-timestamp t)          ; prettify <2025-04-13 Sun> stamps

  ;; Doom fix: default ☑ renders too large on many fonts — use a consistent glyph
  (setf (alist-get ?X org-modern-checkbox) #("□x" 0 2 (composition ((2)))))

  ;; Doom fix: when org-indent-mode is active, org-modern's hidden stars
  ;; make sub-headings look too sunken.  org-hide-leading-stars already
  ;; handles this, so disable org-modern's duplicate hiding.
  (add-hook 'org-modern-mode-hook
            (lambda ()
              (when (bound-and-true-p org-indent-mode)
                (setq-local org-modern-hide-stars nil)))))

;; org-modern-indent: better block/heading indentation under org-indent-mode
;; Enhances how src blocks, drawers, and other multi-line elements render
;; when org-indent-mode adds virtual indentation.
;; NOTE: requires org-indent-mode to be enabled (which we do via org-startup-indented).
(unless (or (package-installed-p 'org-modern-indent)
            (locate-library "org-modern-indent"))
  (if noninteractive
      (message "org-seq: skipping org-modern-indent bootstrap in noninteractive session")
    (condition-case err
        (package-vc-install "https://github.com/jdtsmith/org-modern-indent")
      (error
       (message "WARNING org-seq: failed to install org-modern-indent: %s" err)))))

(use-package org-modern-indent
  :if (locate-library "org-modern-indent")
  :hook (org-indent-mode . org-modern-indent-mode))

;; org-appear: reveal hidden markup (emphasis, links, entities) at cursor
;; Complements org-modern — pretty when reading, transparent when editing.
(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autolinks t)
  (org-appear-autoentities t)
  (org-appear-autosubmarkers t))

;; org-fragtog: auto-toggle LaTeX fragment preview at cursor
;; Requires a LaTeX distribution (MiKTeX or TeX Live) with dvisvgm on PATH.
;; NOTE: table cells don't support image overlays well — fragments inside
;; tables are skipped via `org-fragtog-ignore-predicates'.
(use-package org-fragtog
  :hook (org-mode . org-fragtog-mode)
  :custom
  (org-fragtog-preview-delay 0.2)
  (org-fragtog-ignore-predicates '(org-at-table-p))
  :config
  ;; NOTE(win): MiKTeX bin may not be in PATH when Emacs inherits a stale
  ;; environment (daemon, pinned shortcut).  Ensure exec-path includes it.
  (when (eq system-type 'windows-nt)
    (let ((miktex-bin (expand-file-name
                       "AppData/Local/Programs/MiKTeX/miktex/bin/x64"
                       (getenv "USERPROFILE"))))
      (when (and (file-directory-p miktex-bin)
                 (not (member miktex-bin exec-path)))
        (add-to-list 'exec-path miktex-bin)
        (setenv "PATH" (concat miktex-bin ";" (getenv "PATH"))))))
  (setq org-preview-latex-default-process 'dvisvgm)
  ;; Scale 1.0 matches ~13pt body text; adjust if you change :height in init-ui.
  ;; Foreground 'default inherits the active theme's text color.
  ;; Background "Transparent" tells org NOT to emit \pagecolor in the LaTeX
  ;; preamble, so dvisvgm produces genuinely transparent SVGs — no background
  ;; rectangle at all.  However, Emacs' librsvg renderer still paints a solid
  ;; background behind transparent SVGs (a known limitation on Windows with
  ;; the bundled librsvg); there is no config-level fix for this as of Emacs
  ;; 30.2.  The new org-latex-preview engine (expected in Org 9.8+) handles
  ;; this correctly.  Until then, "Transparent" is the least-bad option: it
  ;; avoids baking a fixed color into the SVG (which would break on theme
  ;; switch) and produces barely-visible artifacts on light themes.
  (plist-put org-format-latex-options :scale 1.0)
  (plist-put org-format-latex-options :foreground 'default)
  (plist-put org-format-latex-options :background "Transparent"))

;; org-cliplink: paste a URL from clipboard and auto-fetch its page title
;; as the link description.  Saves manual [[][title]] typing.
(use-package org-cliplink
  :after org
  :commands org-cliplink)

;; org-download: drag-and-drop (or paste) images into org buffers.
;; Images are stored as org-attach attachments alongside the note.
;; NOTE(win): drag-and-drop from Explorer works; clipboard paste
;; requires ImageMagick convert.exe or PowerShell fallback.
(use-package org-download
  :after org
  :hook (org-mode . org-download-enable)
  :custom
  (org-download-method 'attach)
  (org-download-heading-lvl nil)
  (org-download-timestamp "%Y%m%d%H%M%S-"))

;; pangu-spacing: auto-insert thin space between CJK and Latin characters.
;; Virtual mode (default) — spaces are *displayed* but not saved to file,
;; keeping the source clean.  Essential for CJK mixed-language writing.
;; NOTE: real-insert mode (pangu-spacing-real-insert-separtor t) would
;; break org tables and babel blocks — keep it nil.
(use-package pangu-spacing
  :hook (org-mode . pangu-spacing-mode)
  :config
  (setq pangu-spacing-real-insert-separator nil))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Evil integration for org-mode
;; ═══════════════════════════════════════════════════════════════════════════

(use-package evil-org
  :after (org evil)
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar))
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Local leader keys for Org buffers
;; ═══════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'org-mode-map
   :prefix ","
   :global-prefix "M-,"

   ""   '(nil :wk "org")

   ","  '(my/node-action :wk "Node actions")
   "r"  '(org-refile :wk "Refile")
   "a"  '(org-archive-subtree :wk "Archive")
   "t"  '(org-set-tags-command :wk "Set tags")
   "p"  '(org-set-property :wk "Set property")
   "e"  '(org-set-effort :wk "Set effort")
   "x"  '(org-export-dispatch :wk "Export")
   "l"  '(org-insert-link :wk "Insert link")
   "L"  '(org-store-link :wk "Store link")
   "s"  '(org-schedule :wk "Schedule")
   "d"  '(org-deadline :wk "Deadline")
   "i"  '(org-time-stamp :wk "Timestamp")
   "I"  '(org-time-stamp-inactive :wk "Timestamp (inactive)")
   "n"  '(org-narrow-to-subtree :wk "Narrow to subtree")
   "w"  '(widen :wk "Widen")
   "c"  '(org-toggle-checkbox :wk "Toggle checkbox")
   "q"  '(my/gtd-set-state :wk "State picker")
   "h"  '(my/gtd-toggle-hide-done :wk "Hide/show done")

   ;; , # — SuperTag (quick access from org buffers, mirrors SPC n p)
   "#"  '(:ignore t :wk "supertag")
   "##" '(my/supertag-quick-action :wk "Quick action")
   "#a" '(org-supertag-tag-add-tag :wk "Add tag")
   "#e" '(org-supertag-node-edit-field :wk "Edit field")
   "#x" '(org-supertag-tag-remove :wk "Remove tag")
   "#j" '(org-supertag-node-follow-ref :wk "Jump linked")

   ;; , k — Clock
   "k"  '(:ignore t :wk "clock")
   "ki" '(org-clock-in :wk "Clock in")
   "ko" '(org-clock-out :wk "Clock out")
   "kg" '(org-clock-goto :wk "Goto clock")
   "kr" '(org-clock-report :wk "Report")
   "kc" '(org-clock-cancel :wk "Cancel")

   ;; , b — Babel
   "b"  '(:ignore t :wk "babel")
   "be" '(org-babel-execute-src-block :wk "Execute block")
   "bb" '(org-babel-execute-buffer :wk "Execute buffer")
   "bt" '(org-babel-tangle :wk "Tangle")))

(provide 'init-org)
;;; init-org.el ends here
