;;; init-dashboard.el --- Startup dashboard -*- lexical-binding: t; -*-

;; Requires: init-roam (org-roam-dailies-capture-today, org-roam-node-find)

(require 'cl-lib)

(defconst my/dashboard-version-file
  (expand-file-name ".org-seq-version" user-emacs-directory)
  "File containing the currently deployed org-seq version string.")

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

;; ---- Quote data (pure data file, sibling of this module) ----
;; Defines `my/dashboard-quotes'.  Keeping the quotes out of this
;; file means edits to the quote list don't churn init-dashboard.el
;; and stale "Tip: SPC ..." references are easier to find in one place.
(require 'dashboard-quotes)

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
  ;; `my/dashboard-quotes' is provided by lisp/dashboard-quotes.el
  ;; (required at the top of this file).

  (defun my/dashboard--wrap-quote (text max-width)
    "Wrap TEXT to MAX-WIDTH at word boundaries, returning a single string."
    (if (<= (length text) max-width)
        text
      (let ((pos max-width))
        (while (and (> pos 0) (not (eq (aref text pos) ?\s)))
          (cl-decf pos))
        (when (= pos 0) (setq pos max-width))
        (concat (substring text 0 pos) "\n"
                (string-trim-left (substring text pos))))))

  (defun my/dashboard--pick-quote ()
    "Pick a random quote and wrap it to fit the dashboard width."
    (let* ((quote (nth (random (length my/dashboard-quotes)) my/dashboard-quotes))
           (width (max 40 (- (min 80 (window-width)) 6))))
      (setq dashboard-footer-messages
            (list (my/dashboard--wrap-quote quote width)))))

  (defun my/dashboard--version-string ()
    "Return a display string for the deployed org-seq version."
    (let ((version
           (when (file-readable-p my/dashboard-version-file)
             (string-trim
              (with-temp-buffer
                (insert-file-contents my/dashboard-version-file)
                (buffer-string))))))
      (format "Version: %s"
              (if (and version (not (string-empty-p version)))
                  version
                "unversioned"))))

  (defun my/dashboard-insert-version ()
    "Insert the deployed org-seq version below the dashboard quote footer."
    (insert "\n")
    (dashboard-insert-center
     ""
     (propertize (my/dashboard--version-string)
                 'face 'font-lock-comment-face)
     "\n"))

  (my/dashboard--pick-quote)
  (setq dashboard-footer-icon
        (my/dashboard-icon "nf-md-format_quote_open" ""))

  (add-hook 'dashboard-before-initialize-hook #'my/dashboard--pick-quote)
  (advice-remove #'dashboard-insert-footer #'my/dashboard-insert-version)
  (advice-add #'dashboard-insert-footer :after #'my/dashboard-insert-version)

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
           " Find " "Search notes with Deft  [SPC n f]"
           (lambda (&rest _) (deft)))
          (,(my/dashboard-icon "nf-md-format_list_checks")
           " Tasks " "Open GTD task dashboard  [SPC a n]"
           (lambda (&rest _) (my/org-open-task-dashboard)))
          (,(my/dashboard-icon "nf-md-calendar_week")
           " Review " "Open weekly review  [SPC a w]"
           (lambda (&rest _) (my/org-open-weekly-review)))
          (,(my/dashboard-icon "nf-md-history")
           " Last File " "Open the most recently edited file"
           (lambda (&rest _) (my/dashboard-open-last-file))))))

  ;; ---- Vertical centering ----

  (defvar-local my/dashboard--content-lines nil
    "Cached line count of dashboard content before padding.")

  (defun my/dashboard-vertically-center ()
    "Pad the top of the dashboard buffer to vertically center content."
    (when-let ((buf (get-buffer dashboard-buffer-name)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          ;; Strip existing top padding
          (goto-char (point-min))
          (while (and (not (eobp)) (looking-at-p "^$"))
            (delete-region (line-beginning-position)
                           (min (1+ (line-end-position)) (point-max))))
          ;; Strip trailing blank lines
          (goto-char (point-max))
          (while (and (> (point) (point-min))
                      (progn (forward-line -1) (looking-at-p "^$")))
            (delete-region (line-beginning-position)
                           (min (1+ (line-end-position)) (point-max))))
          ;; Cache the true content height
          (setq my/dashboard--content-lines
                (count-lines (point-min) (point-max)))
          ;; Insert top padding
          (let* ((win (or (get-buffer-window buf) (selected-window)))
                 (win-height (window-body-height win))
                 (pad (max 0 (/ (- win-height my/dashboard--content-lines) 2))))
            (goto-char (point-min))
            (insert (make-string pad ?\n))
            (goto-char (point-min)))))))

  (add-hook 'dashboard-after-initialize-hook #'my/dashboard-vertically-center)

  (defvar my/dashboard--resize-timer nil
    "Debounce timer for dashboard resize centering.")

  (defun my/dashboard-recenter-on-resize (&optional _frame)
    "Re-center dashboard when window size changes (debounced)."
    (when (and (get-buffer dashboard-buffer-name)
               (get-buffer-window dashboard-buffer-name))
      (when my/dashboard--resize-timer
        (cancel-timer my/dashboard--resize-timer))
      (setq my/dashboard--resize-timer
            (run-with-idle-timer 0.1 nil #'my/dashboard-vertically-center))))

  (add-hook 'window-size-change-functions #'my/dashboard-recenter-on-resize)

  (setq initial-buffer-choice
        (lambda () (get-buffer-create dashboard-buffer-name)))

  (dashboard-setup-startup-hook))

(provide 'init-dashboard)
;;; init-dashboard.el ends here
