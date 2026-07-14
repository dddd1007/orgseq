;;; init-daily.el --- Daily-first workspace and navigation -*- lexical-binding: t; -*-

;; Requires: init-roam (my/roam-dir, dailies path helpers)
;; Requires: init-pkm (my/supertag-schedule-sync)

(require 'calendar)
(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'subr-x)

(defvar my/roam-dir)
(defvar org-roam-dailies-directory)

(declare-function my/org-roam-dailies--file-for-date "init-roam" (time))
(declare-function my/supertag-schedule-sync "init-pkm" ())

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

(provide 'init-daily)
;;; init-daily.el ends here
