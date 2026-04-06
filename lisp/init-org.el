;;; init-org.el --- Org-mode base configuration -*- lexical-binding: t; -*-

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
        '((sequence "TODO(t)" "IN-PROGRESS(i)" "WAITING(w@/!)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))

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
