;;; init-org.el --- Org-mode base configuration -*- lexical-binding: t; -*-

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Core PKM directory
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/note-home (file-truename "~/NoteHQ/")
  "Root directory for all notes. org-roam lives under Roam/ subdirectory.")

(defvar my/orgseq-dir (expand-file-name ".orgseq/" my/note-home)
  "Directory for org-seq personalized configuration.
Similar to .vscode or .cursor — stores non-sensitive settings
that customize org-seq behavior per note library.")

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
        org-pretty-entities t)

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
        org-tags-column 0))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Visual enhancement
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq org-modern-star '("◉" "○" "◈" "◇" "⁕")
        org-modern-table nil))

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

   ;; , # — SuperTag (quick access from org buffers)
   "#"  '(:ignore t :wk "supertag")
   "#a" '(supertag-add-tag :wk "Add tag")
   "#v" '(supertag-view-node :wk "View node")
   "#s" '(supertag-search :wk "Search")
   "#k" '(supertag-view-kanban :wk "Kanban")
   "#c" '(supertag-capture :wk "Capture")

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
