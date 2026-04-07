;;; init-dashboard.el --- Startup dashboard -*- lexical-binding: t; -*-

;; ---- recentf: track recently opened files ----
(require 'recentf)
(setq recentf-max-saved-items 30
      recentf-exclude '("\\.git/" "COMMIT_EDITMSG" "/tmp/" "/ssh:"
                        ".*-autoloads\\.el\\'" "[/\\\\]elpa/"
                        "\\.emacs\\.d/"))
(recentf-mode 1)

(defun my/dashboard-open-last-file ()
  "Open the most recently edited file."
  (interactive)
  (if recentf-list
      (find-file (car recentf-list))
    (message "No recent files found")))

(defun my/dashboard-icon (name &optional fallback)
  "Return nerd-icon for NAME, or FALLBACK string on error."
  (condition-case nil
      (nerd-icons-mdicon name)
    (error (or fallback ">"))))

;; ---- dashboard: Doom-style startup screen ----
(use-package dashboard
  :demand t
  :config
  (setq dashboard-startup-banner
        (expand-file-name "banner-compact.txt"
                          (file-name-directory
                           (or load-file-name buffer-file-name))))

  (setq dashboard-banner-logo-title nil
        dashboard-center-content t
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-icon-type 'nerd-icons
        dashboard-recentf-show-base t
        dashboard-recentf-item-format "%s")

  (setq dashboard-items '((recents . 5)))
  (setq dashboard-item-shortcuts '((recents . "r")))

  ;; Footer: random quote, Doom-style
  (defvar my/dashboard-quotes
    '("The only way to do great work is to love what you do. — Steve Jobs"
      "Simplicity is the ultimate sophistication. — Leonardo da Vinci"
      "The mind is not a vessel to be filled, but a fire to be kindled. — Plutarch"
      "We are what we repeatedly do. Excellence is not an act, but a habit. — Aristotle"
      "In the middle of difficulty lies opportunity. — Albert Einstein"
      "The unexamined life is not worth living. — Socrates"
      "Knowing is not enough; we must apply. — Goethe"
      "First, solve the problem. Then, write the code. — John Johnson"
      "Emacs is a great operating system, lacking only a decent editor. — Ancient Proverb"
      "Org-mode is for keeping notes, maintaining TODO lists, and project planning. — Carsten Dominik"
      "Your mind is for having ideas, not holding them. — David Allen"
      "A complex system that works evolved from a simple system that worked. — John Gall"
      "Programs must be written for people to read. — Harold Abelson"
      "Talk is cheap. Show me the code. — Linus Torvalds"
      "Any sufficiently advanced technology is indistinguishable from magic. — Arthur C. Clarke"
      "The best time to plant a tree was 20 years ago. The second best time is now. — Chinese Proverb"
      "Zettelkasten is not a method of storage, but a method of thinking. — Niklas Luhmann"
      "Make it work, make it right, make it fast. — Kent Beck"
      "Perfection is achieved not when there is nothing more to add, but nothing left to take away. — Saint-Exupery"
      "The tools we use have a profound effect on our thinking habits. — Edsger Dijkstra"))

  (setq dashboard-footer-messages
        (list (nth (random (length my/dashboard-quotes)) my/dashboard-quotes)))
  (setq dashboard-footer-icon
        (my/dashboard-icon "nf-md-format_quote_open" ""))

  ;; Pick a fresh quote on each dashboard refresh
  (add-hook 'dashboard-before-initialize-hook
            (lambda ()
              (setq dashboard-footer-messages
                    (list (nth (random (length my/dashboard-quotes))
                               my/dashboard-quotes)))))

  ;; Compact component ordering (fewer blank lines)
  (setq dashboard-startupify-list
        '(dashboard-insert-banner
          dashboard-insert-navigator
          dashboard-insert-init-info
          dashboard-insert-items
          dashboard-insert-footer))

  ;; Quick action buttons — horizontal row
  (setq dashboard-navigator-buttons
        `(((,(my/dashboard-icon "nf-md-notebook_edit")
           " Today " "Open today's daily note  [SPC n d d]"
           (lambda (&rest _) (org-roam-dailies-capture-today)))
          (,(my/dashboard-icon "nf-md-magnify")
           " Find " "Find an org-roam note  [SPC n f]"
           (lambda (&rest _) (org-roam-node-find)))
          (,(my/dashboard-icon "nf-md-format_list_checks")
           " Tasks " "Open GTD task dashboard  [SPC a n]"
           (lambda (&rest _) (my/org-open-task-dashboard)))
          (,(my/dashboard-icon "nf-md-calendar_week")
           " Review " "Open weekly review  [SPC a w]"
           (lambda (&rest _) (my/org-open-weekly-review)))
          (,(my/dashboard-icon "nf-md-history")
           " Last File " "Open the most recently edited file"
           (lambda (&rest _) (my/dashboard-open-last-file))))))

  (setq initial-buffer-choice
        (lambda () (get-buffer-create dashboard-buffer-name)))

  (dashboard-setup-startup-hook))

(provide 'init-dashboard)
;;; init-dashboard.el ends here
