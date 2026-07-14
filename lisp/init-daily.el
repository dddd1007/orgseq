;;; init-daily.el --- Daily-first workspace and navigation -*- lexical-binding: t; -*-

;; Requires: init-roam (my/roam-dir, dailies path helpers)
;; Requires: init-pkm (my/supertag-schedule-sync)

(require 'calendar)
(require 'button)
(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'subr-x)

(defvar my/roam-dir)
(defvar org-roam-dailies-directory)

(declare-function my/org-roam-dailies--file-for-date "init-roam" (time))
(declare-function my/org-roam-dailies-open-date "init-roam" (time))
(declare-function my/supertag-schedule-sync "init-pkm" ())
(declare-function my/daily-workspace-open "init-daily" ())
(declare-function my/daily-workspace-open-date "init-daily" (time))
(declare-function my/daily-workspace-choose-date "init-daily" ())
(declare-function my/workspace-close-treemacs "init-workspace" ())

(defcustom my/daily-sidebar-days 14
  "Number of consecutive calendar days shown in the Daily sidebar."
  :type 'integer
  :group 'org-seq)

(defcustom my/daily-sidebar-width 25
  "Width in columns of the Daily sidebar."
  :type 'integer
  :group 'org-seq)

(defcustom my/daily-auto-prepare-today t
  "When non-nil, opening Today's workspace prepares one capture node."
  :type 'boolean
  :group 'org-seq)

(defun my/daily--directory ()
  "Return the configured org-roam dailies directory."
  (file-name-as-directory
   (expand-file-name (or (and (boundp 'org-roam-dailies-directory)
                              org-roam-dailies-directory)
                         "daily/")
                     my/roam-dir)))

(defun my/daily--file-for-time (time)
  "Return the Daily file path for TIME without creating it."
  (if (fboundp 'my/org-roam-dailies--file-for-date)
      (my/org-roam-dailies--file-for-date time)
    (expand-file-name (format-time-string "%Y-%m-%d.org" time)
                      (my/daily--directory))))

(defun my/daily--gregorian-for-time (time)
  "Return Gregorian (MONTH DAY YEAR) for TIME."
  (let ((decoded (decode-time time)))
    (list (decoded-time-month decoded)
          (decoded-time-day decoded)
          (decoded-time-year decoded))))

(defun my/daily--time-for-absolute-date (absolute)
  "Return local noon for Gregorian ABSOLUTE date."
  (pcase-let ((`(,month ,day ,year)
               (calendar-gregorian-from-absolute absolute)))
    (encode-time 0 0 12 day month year)))

(defun my/daily-date-records (&optional time count)
  "Return COUNT Daily date records ending at TIME, newest first."
  (let* ((time (or time (current-time)))
         (count (or count my/daily-sidebar-days))
         (today (calendar-absolute-from-gregorian
                 (my/daily--gregorian-for-time time))))
    (cl-loop for offset below count
             for item-time = (my/daily--time-for-absolute-date
                              (- today offset))
             for file = (my/daily--file-for-time item-time)
             collect (list :time item-time
                           :date (format-time-string "%Y-%m-%d" item-time)
                           :label (if (zerop offset)
                                      "Today"
                                    (format-time-string "%a %b %d" item-time))
                           :file file
                           :exists (file-exists-p file)
                           :today (zerop offset)))))

(defun my/daily-buffer-p (&optional buffer)
  "Return non-nil when BUFFER visits a file in the dailies directory."
  (with-current-buffer (or buffer (current-buffer))
    (when buffer-file-name
      (let ((file (expand-file-name buffer-file-name))
            (directory (my/daily--directory)))
        (or (file-in-directory-p file directory)
            (and (not (file-exists-p file))
                 (string-prefix-p directory file
                                  (file-name-case-insensitive-p
                                   directory))))))))

(defun my/daily--allowed-blank-property-p (property)
  "Return non-nil when PROPERTY is metadata allowed on a blank node."
  (member (car property) '("ID" "CATEGORY")))

(defun my/daily--blank-node-at-point-p ()
  "Return non-nil when point is on a reusable Daily capture node."
  (and (= (org-outline-level) 1)
       (string-match-p "\\`[0-9][0-9]:[0-9][0-9]\\'"
                       (string-trim (org-get-heading t t t t)))
       (null (org-get-tags nil t))
       (cl-every #'my/daily--allowed-blank-property-p
                 (org-entry-properties nil 'standard))
       (save-excursion
         (org-end-of-meta-data t)
         (let ((begin (point))
               (end (save-excursion (org-end-of-subtree t t))))
           (string-empty-p
            (string-trim (buffer-substring-no-properties begin end)))))))

(defun my/daily--final-blank-node-marker ()
  "Return a marker for the final reusable Daily node, or nil."
  (org-with-wide-buffer
   (goto-char (point-max))
   (when (re-search-backward org-heading-regexp nil t)
     (when (my/daily--blank-node-at-point-p)
       (copy-marker (line-beginning-position))))))

(defun my/daily--insert-node ()
  "Append a top-level timestamp node and return its marker."
  (goto-char (point-max))
  (unless (bolp) (insert "\n"))
  (unless (or (= (point) (point-min))
              (save-excursion (forward-line -1) (looking-at-p "^$")))
    (insert "\n"))
  (insert "* " (format-time-string "%H:%M"))
  (let ((marker (copy-marker (line-beginning-position))))
    (org-id-get-create)
    marker))

(defun my/daily--writable-p ()
  "Return non-nil when the current Daily file can be written."
  (let ((file (or buffer-file-name default-directory)))
    (if (file-exists-p file)
        (file-writable-p file)
      (file-writable-p (file-name-directory file)))))

(defun my/daily--prepare-node ()
  "Reuse or create one capture-ready node and return its marker."
  (unless (my/daily-buffer-p)
    (user-error "Current buffer is not a Daily Note"))
  (unless (my/daily--writable-p)
    (user-error "Daily Note is not writable: %s" buffer-file-name))
  (let ((marker (or (my/daily--final-blank-node-marker)
                    (save-excursion (my/daily--insert-node)))))
    (goto-char marker)
    (org-back-to-heading t)
    (end-of-line)
    (unless (eq (char-before) ?\s) (insert " "))
    (save-buffer)
    marker))

(defun my/daily--schedule-supertag-sync ()
  "Request existing debounced supertag sync without breaking save."
  (when (fboundp 'my/supertag-schedule-sync)
    (condition-case err
        (my/supertag-schedule-sync)
      (error
       (message "WARNING org-seq: Daily supertag sync failed: %s" err)))))

(define-minor-mode my/daily-note-mode
  "Minor mode for org-seq Daily Notes."
  :lighter " Daily"
  (if my/daily-note-mode
      (add-hook 'after-save-hook #'my/daily--schedule-supertag-sync nil t)
    (remove-hook 'after-save-hook #'my/daily--schedule-supertag-sync t)))

(defun my/daily--maybe-enable-note-mode ()
  "Enable `my/daily-note-mode' for files in the dailies directory."
  (when (my/daily-buffer-p)
    (my/daily-note-mode 1)))

(add-hook 'org-mode-hook #'my/daily--maybe-enable-note-mode)

(defconst my/daily-sidebar-buffer-name "*Daily Notes*"
  "Buffer name for the org-seq Daily sidebar.")

(defvar my/daily--clock #'current-time
  "Function returning the current time; rebound by tests.")

(defvar-local my/daily-sidebar-records nil)

(defvar-keymap my/daily-sidebar-mode-map
  :parent special-mode-map
  "RET" #'my/daily-sidebar-open-at-point
  "t" #'my/daily-workspace-open
  "g" #'my/daily-sidebar-refresh
  "c" #'my/daily-workspace-choose-date
  "q" #'my/daily-sidebar-close)

(define-derived-mode my/daily-sidebar-mode special-mode "Daily-Notes"
  "Major mode for recent Daily Note navigation."
  (setq-local truncate-lines t))

(defun my/daily-sidebar--insert-record (record)
  "Insert one actionable sidebar row for RECORD."
  (insert-text-button
   (format "%s %-10s %s"
           (if (plist-get record :exists) "*" ".")
           (plist-get record :label)
           (plist-get record :date))
   'follow-link t
   'my/daily-time (plist-get record :time)
   'action (lambda (button)
             (my/daily-workspace-open-date
              (button-get button 'my/daily-time))))
  (insert "\n"))

(defun my/daily-sidebar-refresh ()
  "Refresh the Daily sidebar without creating note files."
  (interactive)
  (let ((buffer (get-buffer-create my/daily-sidebar-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'my/daily-sidebar-mode)
        (my/daily-sidebar-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Daily Notes\n\n")
        (setq my/daily-sidebar-records
              (my/daily-date-records (funcall my/daily--clock)))
        (dolist (record my/daily-sidebar-records)
          (my/daily-sidebar--insert-record record))
        (insert "\nRET open   t today   c calendar   g refresh\n")
        (goto-char (point-min))))
    buffer))

(defun my/daily-sidebar-window ()
  "Return the live Daily sidebar window in the selected frame."
  (cl-find-if (lambda (window)
                (window-parameter window 'my/daily-sidebar))
              (window-list nil 'no-minibuffer)))

(defun my/daily-sidebar-open ()
  "Open or reuse the persistent Daily sidebar and return its window."
  (interactive)
  (my/daily-sidebar-refresh)
  (or (my/daily-sidebar-window)
      (let ((window
             (display-buffer-in-side-window
              (get-buffer my/daily-sidebar-buffer-name)
              `((side . left) (slot . -2)
                (window-width . ,my/daily-sidebar-width)))))
        (set-window-parameter window 'my/daily-sidebar t)
        (set-window-dedicated-p window t)
        window)))

(defun my/daily-sidebar-close ()
  "Close only the org-seq Daily sidebar in the selected frame."
  (interactive)
  (when-let ((window (my/daily-sidebar-window)))
    (delete-window window)))

(defun my/daily-sidebar-open-at-point ()
  "Open the Daily date represented at point."
  (interactive)
  (if-let ((time (get-text-property (point) 'my/daily-time)))
      (my/daily-workspace-open-date time)
    (user-error "No Daily date at point")))

(defun my/daily--editor-window ()
  "Return a non-side editor window in the selected frame."
  (or (cl-find-if (lambda (window)
                    (not (window-parameter window 'window-side)))
                  (window-list nil 'no-minibuffer))
      (selected-window)))

(defun my/daily--visit-date (time)
  "Visit TIME through the existing org-roam dailies boundary."
  (let ((file (my/daily--file-for-time time)))
    (when (and (not (file-exists-p file))
               (file-exists-p my/roam-dir)
               (not (file-writable-p my/roam-dir)))
      (user-error "Roam directory is not writable: %s" my/roam-dir))
    (my/org-roam-dailies-open-date time)
    (my/daily-note-mode 1)
    (current-buffer)))

(defun my/daily-workspace-open-date (time &optional capture-ready)
  "Open TIME in the Daily Workspace.
Existing history is browse-only unless CAPTURE-READY is non-nil."
  (interactive (list (current-time) current-prefix-arg))
  (let* ((file (my/daily--file-for-time time))
         (missing (not (file-exists-p file))))
    (when (fboundp 'my/workspace-close-treemacs)
      (my/workspace-close-treemacs))
    (select-window (my/daily--editor-window))
    (let ((buffer (my/daily--visit-date time)))
      (switch-to-buffer buffer)
      (when (or capture-ready missing)
        (my/daily--prepare-node))
      (my/daily-sidebar-open)
      (my/daily-sidebar-refresh)
      buffer)))

(defun my/daily-workspace-open ()
  "Open Today's capture-ready Daily Workspace."
  (interactive)
  (my/daily-workspace-open-date
   (current-time) my/daily-auto-prepare-today))

(defun my/daily-workspace-choose-date ()
  "Choose a date and open its Daily Workspace."
  (interactive)
  (my/daily-workspace-open-date (org-read-date nil t)))

(defun my/daily-new-node ()
  "Prepare a node in the current Daily Note, opening Today if needed."
  (interactive)
  (unless (my/daily-buffer-p)
    (my/daily-workspace-open))
  (my/daily--prepare-node))

(defun my/daily-initial-buffer ()
  "Return Today's capture-ready buffer without opening a sidebar."
  (let ((buffer (save-window-excursion
                  (my/daily--visit-date (current-time)))))
    (with-current-buffer buffer
      (when my/daily-auto-prepare-today
        (my/daily--prepare-node)))
    buffer))

(provide 'init-daily)
;;; init-daily.el ends here
