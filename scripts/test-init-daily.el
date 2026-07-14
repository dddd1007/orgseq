;;; test-init-daily.el --- Tests for Daily Workspace -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(load-file
 (expand-file-name "../lisp/init-daily.el"
                   (file-name-directory load-file-name)))

(defvar my/roam-dir)
(defvar org-roam-dailies-directory)

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

;;; test-init-daily.el ends here
