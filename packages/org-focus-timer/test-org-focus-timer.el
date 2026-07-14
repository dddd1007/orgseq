;;; test-org-focus-timer.el --- Tests for org-focus-timer -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst org-focus-test--directory
  (file-name-directory load-file-name))

(load-file (expand-file-name "org-focus-timer.el" org-focus-test--directory))

(ert-deftest org-focus-dashboard-start-selects-a-writable-target-buffer ()
  (let ((dashboard (get-buffer-create " *focus-dashboard-test*"))
        (target (get-buffer-create " *focus-target-test*"))
        started-in)
    (unwind-protect
        (progn
          (with-current-buffer dashboard
            (org-focus-dashboard-mode))
          (cl-letf (((symbol-function 'read-buffer)
                     (lambda (&rest _) (buffer-name target)))
                    ((symbol-function 'org-focus-start)
                     (lambda (&optional _)
                       (interactive)
                       (setq started-in (current-buffer)))))
            (with-current-buffer dashboard
              (org-focus-dashboard-start))
            (should (eq started-in target))))
      (kill-buffer dashboard)
      (kill-buffer target))))

(ert-deftest org-focus-package-source-has-no-org-seq-leader-key-reference ()
  (let ((source
         (with-temp-buffer
           (insert-file-contents
            (expand-file-name "org-focus-timer.el" org-focus-test--directory))
           (buffer-string))))
    (should-not (string-match-p "SPC " source))
    (should-not (string-match-p "org-seq" source))))

;;; test-org-focus-timer.el ends here
