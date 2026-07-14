;;; test-init-workspace.el --- Tests for startup workspace routing -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'use-package)

(defun my/daily-initial-buffer ()
  (current-buffer))

(load-file
 (expand-file-name "../lisp/init-workspace.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/workspace-startup-preserves-requested-historical-daily-buffer ()
  (let ((historical (get-buffer-create " *org-seq-historical-daily*"))
        (today-opened nil)
        (sidebar-opened nil)
        (sidebar-refreshed nil))
    (unwind-protect
        (progn
          (switch-to-buffer historical)
          (with-current-buffer historical
            (setq buffer-file-name "C:/NoteHQ/00_Roam/daily/20200101.org"))
          (cl-letf (((symbol-function 'my/workspace--startup-target-buffer)
                     (lambda () historical))
                    ((symbol-function 'my/workspace--main-window)
                     (lambda () (selected-window)))
                    ((symbol-function 'my/daily-buffer-p)
                     (lambda (&optional _) t))
                    ((symbol-function 'my/daily-workspace-open)
                     (lambda () (setq today-opened t)))
                    ((symbol-function 'my/workspace-close-treemacs) #'ignore)
                    ((symbol-function 'my/daily-sidebar-open)
                     (lambda () (setq sidebar-opened t)))
                    ((symbol-function 'my/daily-sidebar-refresh)
                     (lambda () (setq sidebar-refreshed t))))
            (my/workspace-startup)
            (should (eq (window-buffer (selected-window)) historical))
            (should sidebar-opened)
            (should sidebar-refreshed)
            (should-not today-opened)))
      (when (buffer-live-p historical)
        (kill-buffer historical)))))

;;; test-init-workspace.el ends here
