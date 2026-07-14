;;; test-init-daily.el --- Tests for Daily Workspace -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(load-file
 (expand-file-name "../lisp/init-daily.el"
                   (file-name-directory load-file-name)))

(defvar my/roam-dir)
(defvar org-roam-dailies-directory)
(defvar org-id-locations-file)
(defvar my/daily--clock)

(ert-deftest my/daily-date-records-use-fourteen-calendar-days ()
  (let* ((root (make-temp-file "org-seq-daily-dates-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (now (encode-time 0 30 12 10 3 2026))
         (records (my/daily-date-records now 14)))
    (unwind-protect
        (progn
          (should (= (length records) 14))
          (should (equal (plist-get (car records) :date) "2026-03-10"))
          (should (equal (plist-get (car (last records)) :date)
                         "2026-02-25"))
          (should (plist-get (car records) :today))
          (should-not (seq-some (lambda (record)
                                  (plist-get record :exists))
                                records))
          (should-not (file-exists-p (expand-file-name "daily" root))))
      (delete-directory root t))))

(ert-deftest my/daily-date-records-classify-existing-files-read-only ()
  (let* ((root (make-temp-file "org-seq-daily-existing-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (now (encode-time 0 0 12 14 7 2026))
         (today (expand-file-name "daily/2026-07-14.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory today) t)
          (write-region "#+title: 2026-07-14\n" nil today nil 'silent)
          (let ((records (my/daily-date-records now 2)))
            (should (plist-get (nth 0 records) :exists))
            (should-not (plist-get (nth 1 records) :exists))))
      (delete-directory root t))))

(ert-deftest my/daily-buffer-p-stays-inside-configured-directory ()
  (let* ((root (make-temp-file "org-seq-daily-buffer-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/"))
    (unwind-protect
        (with-temp-buffer
          (setq buffer-file-name
                (expand-file-name "daily/2026-07-14.org" root))
          (should (my/daily-buffer-p))
          (setq buffer-file-name (expand-file-name "capture/note.org" root))
          (should-not (my/daily-buffer-p)))
      (delete-directory root t))))

(ert-deftest my/daily-prepare-node-creates-id-and-reuses-blank-tail ()
  (let* ((root (make-temp-file "org-seq-daily-node-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (org-id-locations-file (expand-file-name ".org-id-locations" root))
         (file (expand-file-name "daily/2026-07-14.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory file) t)
          (with-current-buffer (find-file-noselect file)
            (erase-buffer)
            (insert "#+title: 2026-07-14\n#+filetags: :daily:\n\n")
            (org-mode)
            (my/daily-note-mode 1)
            (my/daily--prepare-node)
            (let ((first-id (org-entry-get nil "ID")))
              (should first-id)
              (my/daily--prepare-node)
              (should (equal (org-entry-get nil "ID") first-id))
              (should (= (how-many "^\\* " (point-min) (point-max)) 1)))
            (kill-buffer (current-buffer))))
      (delete-directory root t))))

(ert-deftest my/daily-prepare-node-appends-after-content ()
  (let* ((root (make-temp-file "org-seq-daily-content-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (org-id-locations-file (expand-file-name ".org-id-locations" root))
         (file (expand-file-name "daily/2026-07-14.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory file) t)
          (with-current-buffer (find-file-noselect file)
            (erase-buffer)
            (insert "#+title: 2026-07-14\n\n* 09:00 Existing note\n")
            (org-mode)
            (my/daily--prepare-node)
            (should (= (how-many "^\\* " (point-min) (point-max)) 2))
            (should (org-entry-get nil "ID"))
            (kill-buffer (current-buffer))))
      (delete-directory root t))))

(ert-deftest my/daily-save-schedules-supertag-sync ()
  (let (scheduled)
    (cl-letf (((symbol-function 'my/supertag-schedule-sync)
               (lambda () (setq scheduled t))))
      (with-temp-buffer
        (my/daily-note-mode 1)
        (run-hooks 'after-save-hook)
        (should scheduled)))))

(ert-deftest my/daily-sidebar-render-is-read-only-and-actionable ()
  (let* ((root (make-temp-file "org-seq-daily-sidebar-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (my/daily--clock (lambda () (encode-time 0 0 12 14 7 2026))))
    (unwind-protect
        (with-current-buffer (get-buffer-create my/daily-sidebar-buffer-name)
          (my/daily-sidebar-mode)
          (my/daily-sidebar-refresh)
          (goto-char (point-min))
          (search-forward "Today")
          (should (get-text-property (1- (point)) 'my/daily-time))
          (should-not (file-exists-p (expand-file-name "daily" root))))
      (when-let ((buffer (get-buffer my/daily-sidebar-buffer-name)))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest my/daily-sidebar-open-is-idempotent ()
  (let* ((root (make-temp-file "org-seq-daily-window-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/"))
    (unwind-protect
        (save-window-excursion
          (let ((first (my/daily-sidebar-open))
                (second (my/daily-sidebar-open)))
            (should (window-live-p first))
            (should (eq first second))
            (should (window-parameter first 'my/daily-sidebar))))
      (when-let ((buffer (get-buffer my/daily-sidebar-buffer-name)))
        (kill-buffer buffer))
      (delete-directory root t))))

;;; test-init-daily.el ends here
