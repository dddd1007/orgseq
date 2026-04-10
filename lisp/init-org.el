;;; init-org.el --- Org-mode base configuration -*- lexical-binding: t; -*-

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

(defcustom my/note-home (file-truename "~/NoteHQ/")
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

(defcustom my/roam-dir (expand-file-name "Roam/" my/note-home)
  "Atomic-notes layer (org-roam-directory equivalent).
Used by `org-roam-directory', `org-mem-watch-dirs',
`org-supertag-sync-directories', and the AI context files
\(purpose.org, schema.org, overview.org)."
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

  (setq org-startup-folded 'content)
  (setq org-hide-leading-stars t)
  (setq org-ellipsis " ⤵")

  (setq org-return-follows-link t
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-catch-invisible-edits 'show-and-error
        org-pretty-entities t
        org-hide-emphasis-markers t)

  ;; Highlight LaTeX fragments with native fontification
  (setq org-highlight-latex-and-related '(native script entities))

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
        org-modern-table nil)

  ;; Doom fix: default ☑ renders too large on many fonts — use a consistent glyph
  (setf (alist-get ?X org-modern-checkbox) #("□x" 0 2 (composition ((2)))))

  ;; Doom fix: when org-indent-mode is active, org-modern's hidden stars
  ;; make sub-headings look too sunken.  org-hide-leading-stars already
  ;; handles this, so disable org-modern's duplicate hiding.
  (add-hook 'org-modern-mode-hook
            (lambda ()
              (when (bound-and-true-p org-indent-mode)
                (setq-local org-modern-hide-stars nil)))))

;; org-appear: reveal hidden markup (emphasis, links, entities) at cursor
;; Complements org-modern — pretty when reading, transparent when editing.
(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autolinks t)
  (org-appear-autoentities t)
  (org-appear-autosubmarkers t))

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
