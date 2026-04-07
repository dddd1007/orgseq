;;; init-org.el --- Org-mode base configuration -*- lexical-binding: t; -*-

(defun my/org-roam-root-directory ()
  "Return the org-roam root directory, with fallback."
  (file-truename
   (if (boundp 'org-roam-directory)
       org-roam-directory
     "~/org-roam/")))

(defun my/org-roam-agenda-files ()
  "Return all agenda candidate files under org-roam."
  (let ((root (my/org-roam-root-directory)))
    (if (file-directory-p root)
        (directory-files-recursively root "\\.org\\'")
      nil)))

(defun my/org-refresh-agenda-files ()
  "Refresh `org-agenda-files' from org-roam files."
  (setq org-agenda-files (my/org-roam-agenda-files)))

(defun my/org-open-task-dashboard ()
  "Open unified task dashboard from all org-roam notes."
  (interactive)
  (my/org-refresh-agenda-files)
  (org-agenda nil "n"))

(defun my/org-open-project-dashboard ()
  "Open GTD project dashboard from all org-roam notes."
  (interactive)
  (my/org-refresh-agenda-files)
  (org-agenda nil "p"))

(defun my/org-open-weekly-review ()
  "Open GTD weekly review dashboard from all org-roam notes."
  (interactive)
  (my/org-refresh-agenda-files)
  (org-agenda nil "w"))

(defun my/org--subtree-has-todo-state-p (todo-keyword)
  "Return non-nil when current subtree has TODO-KEYWORD child."
  (save-excursion
    (let ((subtree-end (save-excursion (org-end-of-subtree t)))
          (matched nil))
      (forward-line 1)
      (while (and (not matched)
                  (< (point) subtree-end)
                  (re-search-forward org-heading-regexp subtree-end t))
        (when (string= (org-get-todo-state) todo-keyword)
          (setq matched t)))
      matched)))

(defun my/org-project-p ()
  "Return non-nil when current heading is a project."
  (and (member (org-get-todo-state) org-not-done-keywords)
       (save-excursion
         (let ((subtree-end (save-excursion (org-end-of-subtree t)))
               (has-child-task nil))
           (forward-line 1)
           (while (and (not has-child-task)
                       (< (point) subtree-end)
                       (re-search-forward org-heading-regexp subtree-end t))
             (when (member (org-get-todo-state) org-not-done-keywords)
               (setq has-child-task t)))
           has-child-task))))

(defun my/org-stuck-project-p ()
  "Return non-nil when project has no NEXT child task."
  (and (my/org-project-p)
       (not (my/org--subtree-has-todo-state-p "NEXT"))))

(defun my/org-skip-non-projects ()
  "Skip entries that are not projects."
  (unless (my/org-project-p)
    (or (outline-next-heading) (point-max))))

(defun my/org-skip-non-stuck-projects ()
  "Skip entries that are not stuck projects."
  (unless (my/org-stuck-project-p)
    (or (outline-next-heading) (point-max))))

(use-package org
  :ensure nil  ; built-in
  :demand t
  :config
  ;; Visual indentation (display only, does not modify files)
  (setq org-startup-indented t
        org-indent-indentation-per-level 2)

  ;; Show up to level 2 headings on startup
  (setq org-startup-folded 'content)

  ;; Hide leading stars
  (setq org-hide-leading-stars t)

  ;; Fold indicator
  (setq org-ellipsis " ⤵")

  ;; Editing behavior
  (setq org-return-follows-link t
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-catch-invisible-edits 'show-and-error
        org-pretty-entities t)

  ;; Logging: record timestamp on task completion
  (setq org-log-done 'time
        org-log-into-drawer t)

  ;; TODO keywords
  (setq org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "IN-PROGRESS(i)" "WAITING(w@/!)" "SOMEDAY(s)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))

  ;; GTD behavior: honor TODO dependencies in agenda and state changes
  (setq org-enforce-todo-dependencies t)

  ;; GTD dashboard across all org-roam notes
  (setq org-agenda-custom-commands
        '(("n" "Roam GTD dashboard"
           ((agenda "" ((org-agenda-span 1)
                        (org-agenda-overriding-header "Today")))
            (todo "IN-PROGRESS"
                  ((org-agenda-overriding-header "In Progress")))
            (todo "NEXT"
                  ((org-agenda-overriding-header "Next Actions")))
            (todo "TODO"
                  ((org-agenda-overriding-header "Inbox (Unscheduled)")
                   (org-agenda-skip-function
                    '(org-agenda-skip-entry-if 'scheduled 'deadline))))
            (todo "WAITING"
                  ((org-agenda-overriding-header "Waiting")))
            (tags-todo "DEADLINE<=\"<today>\"|SCHEDULED<=\"<today>\""
                       ((org-agenda-overriding-header "Overdue / Due Today")
                        (org-agenda-skip-function
                         '(org-agenda-skip-entry-if 'todo 'done))))
            (todo "SOMEDAY"
                  ((org-agenda-overriding-header "Someday / Maybe")))))
          ("p" "Roam GTD projects"
           ((alltodo "" ((org-agenda-overriding-header "Active projects")
                         (org-agenda-skip-function #'my/org-skip-non-projects)))
            (alltodo "" ((org-agenda-overriding-header "Stuck projects (no NEXT)")
                         (org-agenda-skip-function #'my/org-skip-non-stuck-projects)))))
          ("w" "Roam GTD weekly review"
           ((agenda "" ((org-agenda-span 7)
                        (org-agenda-start-day "-3d")
                        (org-agenda-start-on-weekday nil)
                        (org-agenda-overriding-header "Weekly horizon (-3d to +3d)")))
            (todo "IN-PROGRESS|NEXT|WAITING"
                  ((org-agenda-overriding-header "Committed actions")))
            (alltodo "" ((org-agenda-overriding-header "Stuck projects (needs NEXT)")
                         (org-agenda-skip-function #'my/org-skip-non-stuck-projects)))
            (todo "SOMEDAY"
                  ((org-agenda-overriding-header "Someday / Maybe review")))))))

  (my/org-refresh-agenda-files)
  (add-hook 'org-capture-after-finalize-hook #'my/org-refresh-agenda-files)

  ;; Refile: move headings across files
  (setq org-refile-targets '((nil :maxlevel . 3)
                              (org-agenda-files :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

  ;; Tags: no column alignment (works better with org-modern)
  (setq org-auto-align-tags nil
        org-tags-column 0))

;; ---- org-modern: visual enhancement ----
(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq org-modern-star '("◉" "○" "◈" "◇" "⁕")
        org-modern-table nil))  ; disable if using valign

;; ---- evil-org: Evil keybindings for org-mode ----
(use-package evil-org
  :after (org evil)
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar))
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

(provide 'init-org)
;;; init-org.el ends here
