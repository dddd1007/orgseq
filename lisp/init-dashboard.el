;;; init-dashboard.el --- Startup dashboard -*- lexical-binding: t; -*-

;; Requires: init-daily (Daily records and workspace commands)
;; Requires: init-roam (org-roam-node-find)

(require 'cl-lib)
(declare-function my/daily-date-records "init-daily" (&optional time count))
(declare-function my/daily-workspace-open "init-daily" ())
(declare-function my/daily-workspace-open-date "init-daily" (time))
(declare-function my/org-open-task-dashboard "init-gtd" ())
(declare-function my/org-open-weekly-review "init-gtd" ())
(declare-function deft "deft" ())

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
;; ---- Dashboard rendering helpers ----
;;
;; These definitions stay at top level on purpose.  Defining them inside
;; `use-package''s :config hides them from the byte compiler, which then
;; cannot see `my/dashboard--content-lines' as buffer-local and cannot
;; check the call sites in this file.  `dashboard-insert-section' is a
;; macro, so the compiler also needs the package loaded to expand it.
(eval-when-compile (require 'dashboard nil t))

(defvar dashboard-buffer-name)
(defvar dashboard-footer-messages)
(defvar dashboard-item-generators)
(declare-function dashboard-get-shortcut "dashboard" (item))
(declare-function dashboard-insert-center "dashboard-widgets" (&rest strings))
(declare-function dashboard-insert-footer "dashboard-widgets" ())
(declare-function dashboard-setup-startup-hook "dashboard" ())
(declare-function nerd-icons-mdicon "nerd-icons" (icon-name &rest args))
;; Helpers injected by the `dashboard-insert-section' macro expansion.
(declare-function dashboard--define-shorcut-key-binding "dashboard-widgets" (section keybinding))
(declare-function dashboard-display-icons-p "dashboard-widgets" ())
(declare-function dashboard-heading-icon "dashboard-widgets" (&rest args))
(declare-function dashboard-icon-for-dir "dashboard-widgets" (dir &rest args))
(declare-function dashboard-icon-for-file "dashboard-widgets" (file &rest args))
(declare-function dashboard-insert-heading "dashboard-widgets" (heading &optional shortcut face))
(declare-function dashboard-subseq "dashboard-widgets" (sequence end))
(declare-function spaces-string "dashboard-widgets" (length))

(defun my/dashboard-insert-dailies (list-size)
  "Insert LIST-SIZE recent calendar dates into Dashboard."
  (let ((items
         (mapcar
          (lambda (record)
            ;; Date first so the column lines up; the weekday (or Today)
            ;; follows instead of repeating the month and day.
            (let ((label (plist-get record :label))
                  (time (plist-get record :time)))
              (propertize
               (format "%s  %s"
                       (plist-get record :date)
                       (if (string-match-p "\\`[[:alpha:]]+\\'" label)
                           label
                         (format-time-string "%A" time)))
               'my/daily-time time)))
          (my/daily-date-records nil list-size))))
    (dashboard-insert-section
     "Daily Notes:" items list-size 'daily
     (dashboard-get-shortcut 'daily)
     `(lambda (&rest _)
        (my/daily-workspace-open-date
         (get-text-property 0 'my/daily-time ,el)))
     el)))

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

(defvar-local my/dashboard--content-lines nil
  "Cached line count of dashboard content before padding.")

(defun my/dashboard-vertically-center ()
  "Pad the top of the dashboard buffer to vertically center content."
  (when-let* ((buf (get-buffer dashboard-buffer-name)))
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

(defvar my/dashboard--resize-timer nil
  "Debounce timer for dashboard resize centering.")

(defun my/dashboard-recenter-on-resize (&optional _frame)
  "Re-center dashboard when window size changes (debounced)."
  (when (and (get-buffer dashboard-buffer-name)
             (get-buffer-window dashboard-buffer-name))
    (when my/dashboard--resize-timer
      (cancel-timer my/dashboard--resize-timer))
    (setq my/dashboard--resize-timer
          (run-with-idle-timer 0.1 nil #'my/dashboard--refit))))

(declare-function dashboard-insert-startupify-lists "dashboard"
                  (&optional force-refresh))
(defvar my/dashboard--layout)

(defun my/dashboard--refit ()
  "Re-render the dashboard when its width class changed, then center it."
  (when-let* ((window (get-buffer-window dashboard-buffer-name)))
    (unless (eq (my/dashboard--layout-class window) my/dashboard--layout)
      (with-selected-window window
        (dashboard-insert-startupify-lists t))))
  (my/dashboard-vertically-center))

(defun my/dashboard--kill-cleanup ()
  "Cancel orphaned resize timer when the dashboard buffer is killed."
  (when (timerp my/dashboard--resize-timer)
    (cancel-timer my/dashboard--resize-timer)
    (setq my/dashboard--resize-timer nil)))

;; ---- Width-aware layout ----
;; The dashboard often shares a half-screen frame with the sidebar, which
;; leaves it 50-60 columns.  The ASCII banner is 60 columns wide and the
;; five navigator buttons need about 70; both were clipped with truncation
;; arrows.  The banner and the navigator rows are therefore chosen from
;; the width of the window that shows the dashboard, and re-chosen when a
;; resize crosses a threshold.
(defconst my/dashboard--lisp-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding the banner files.")

(defvar dashboard-startup-banner)
(defvar dashboard-navigator-buttons)

(defvar my/dashboard--layout nil
  "Layout class the dashboard was last rendered with.")

(defun my/dashboard--window ()
  "Return the window showing the dashboard, or the selected window."
  (or (and (boundp 'dashboard-buffer-name)
           (get-buffer-window dashboard-buffer-name))
      (selected-window)))

(defun my/dashboard--layout-class (&optional window)
  "Return the layout class for WINDOW: `wide', `medium' or `narrow'."
  (let ((width (window-width (or window (my/dashboard--window)))))
    (cond ((>= width 76) 'wide)
          ((>= width 64) 'medium)
          (t 'narrow))))

(defun my/dashboard--navigator-specs ()
  "Return the navigator buttons as a flat list."
  (list
   (list (my/dashboard-icon "nf-md-notebook_edit")
         " Today " "Open today's daily note  [SPC n d d]"
         (lambda (&rest _) (my/daily-workspace-open))
         nil "" "   ")
   (list (my/dashboard-icon "nf-md-magnify")
         " Find " "Search all NoteHQ notes with Deft  [SPC n f]"
         (lambda (&rest _) (deft))
         nil "" "   ")
   (list (my/dashboard-icon "nf-md-format_list_checks")
         " Tasks " "Open GTD task dashboard  [SPC a n]"
         (lambda (&rest _) (my/org-open-task-dashboard))
         nil "" "   ")
   (list (my/dashboard-icon "nf-md-calendar_week")
         " Review " "Open weekly review  [SPC a w]"
         (lambda (&rest _) (my/org-open-weekly-review))
         nil "" "   ")
   (list (my/dashboard-icon "nf-md-history")
         " Last File " "Open the most recently edited file"
         (lambda (&rest _) (my/dashboard-open-last-file))
         nil "" "")))

(defun my/dashboard--apply-layout (&optional class)
  "Choose the banner and navigator rows for layout CLASS."
  (let ((class (or class (my/dashboard--layout-class)))
        (specs (my/dashboard--navigator-specs)))
    (setq my/dashboard--layout class
          dashboard-startup-banner
          (expand-file-name (if (eq class 'narrow)
                                "banner-narrow.txt"
                              "banner-compact.txt")
                            my/dashboard--lisp-dir)
          ;; Empty prefix/suffix drop the default [ ] brackets: the accent
          ;; color already marks the buttons as actions.
          dashboard-navigator-buttons
          (if (eq class 'wide)
              (list specs)
            (list (seq-take specs 3) (seq-drop specs 3))))))

(defun my/dashboard--init-info ()
  "Return a short startup summary that fits a narrow window."
  (format "%d packages, started in %.2f s"
          (length (bound-and-true-p package-activated-list))
          (float-time (time-subtract after-init-time before-init-time))))

(use-package dashboard
  :demand t
  :config
  (my/dashboard--apply-layout)
  (add-hook 'dashboard-before-initialize-hook #'my/dashboard--apply-layout)
  (setq dashboard-init-info #'my/dashboard--init-info)

  (setq dashboard-banner-logo-title nil
        dashboard-center-content t
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-icon-type 'nerd-icons
        dashboard-recentf-show-base t
        dashboard-recentf-item-format "%s")


  (setf (alist-get 'daily dashboard-item-generators)
        #'my/dashboard-insert-dailies)
  (setq dashboard-items '((daily . 5) (recents . 5))
        dashboard-item-shortcuts '((daily . "d") (recents . "r")))

  ;; Footer: random quote, Doom-style
  ;; `my/dashboard-quotes' is provided by lisp/dashboard-quotes.el
  ;; (required at the top of this file).

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
          dashboard-insert-newline
          dashboard-insert-init-info
          dashboard-insert-items
          dashboard-insert-footer))

  ;; ---- Vertical centering ----

  (add-hook 'dashboard-after-initialize-hook #'my/dashboard-vertically-center)

  (add-hook 'window-size-change-functions #'my/dashboard-recenter-on-resize)


  ;; Cancel orphaned resize timer when dashboard buffer is killed
  (add-hook 'dashboard-after-initialize-hook
            (lambda ()
              (with-current-buffer (get-buffer dashboard-buffer-name)
                (remove-hook 'kill-buffer-hook #'my/dashboard--kill-cleanup t)
                (add-hook 'kill-buffer-hook #'my/dashboard--kill-cleanup nil t))))

  (dashboard-setup-startup-hook))

(provide 'init-dashboard)
;;; init-dashboard.el ends here
