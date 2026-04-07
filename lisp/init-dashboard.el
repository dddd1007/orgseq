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

  ;; Fixed overhead with compact banner and tighter section spacing.
  (defvar my/dashboard-fixed-lines 11)

  (defun my/dashboard-recents-count ()
    "Compute recent files count based on current frame height."
    (max 5 (min 16 (- (frame-text-lines) my/dashboard-fixed-lines))))

  (setq dashboard-items `((recents . ,(my/dashboard-recents-count))))
  (setq dashboard-item-shortcuts '((recents . "r")))

  ;; Recompute on each dashboard refresh so resized frames get the right count
  (add-hook 'dashboard-before-initialize-hook
            (lambda ()
              (setq dashboard-items
                    `((recents . ,(my/dashboard-recents-count))))))

  ;; Footer: keep one short line so the dashboard stays scannable.
  (setq dashboard-footer-messages
        '("SPC n d today  |  SPC n f find  |  SPC n r review"))
  (setq dashboard-footer-icon
        (my/dashboard-icon "nf-md-keyboard" ""))

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
           " Today " "Open today's daily note  [SPC n d]"
           (lambda (&rest _) (org-roam-dailies-capture-today)))
          (,(my/dashboard-icon "nf-md-magnify")
           " Find " "Find an org-roam note  [SPC n f]"
           (lambda (&rest _) (org-roam-node-find)))
          (,(my/dashboard-icon "nf-md-format_list_checks")
           " Tasks " "Open GTD task dashboard  [SPC n a]"
           (lambda (&rest _) (my/org-open-task-dashboard)))
          (,(my/dashboard-icon "nf-md-calendar_week")
           " Review " "Open weekly review  [SPC n r]"
           (lambda (&rest _) (my/org-open-weekly-review)))
          (,(my/dashboard-icon "nf-md-history")
           " Last File " "Open the most recently edited file"
           (lambda (&rest _) (my/dashboard-open-last-file))))))

  (setq initial-buffer-choice
        (lambda () (get-buffer-create dashboard-buffer-name)))

  (dashboard-setup-startup-hook))

(provide 'init-dashboard)
;;; init-dashboard.el ends here
