;;; init-daily.el --- Daily-first workspace and navigation -*- lexical-binding: t; -*-

;; Requires: init-roam (my/roam-dir, dailies path helpers)
;; Requires: init-supertag (my/supertag-schedule-sync)

(require 'calendar)
(require 'cl-lib)
(require 'org)
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

(provide 'init-daily)
;;; init-daily.el ends here
