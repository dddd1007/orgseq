;;; test-init-markdown.el --- Tests for Markdown conversion safety -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'use-package)

(load-file
 (expand-file-name "../lisp/init-markdown.el"
                   (file-name-directory load-file-name)))

(defun my/test-markdown--contents (file)
  "Return FILE contents as a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defmacro my/test-markdown--with-files (&rest body)
  "Run BODY with temporary Markdown and Org files."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "org-seq-markdown-" t))
          (md-file (expand-file-name "note.md" root))
          (org-file (expand-file-name "note.org" root)))
     (unwind-protect
         (progn
           (write-region "# Note\n" nil md-file nil 'silent)
           (write-region "original\n" nil org-file nil 'silent)
           ,@body)
       (when-let ((buffer (find-buffer-visiting md-file)))
         (with-current-buffer buffer
           (set-buffer-modified-p nil))
         (kill-buffer buffer))
       (when-let ((buffer (find-buffer-visiting org-file)))
         (with-current-buffer buffer
           (set-buffer-modified-p nil))
         (kill-buffer buffer))
       (delete-directory root t))))

(ert-deftest my/markdown-convert-decline-preserves-existing-org-file ()
  (my/test-markdown--with-files
    (let ((pandoc-called nil))
      (let ((auto-mode-alist nil))
        (with-current-buffer (find-file-noselect md-file)
          (setq major-mode 'markdown-mode)
          (cl-letf (((symbol-function 'executable-find) (lambda (_) "pandoc"))
                    ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
                    ((symbol-function 'call-process)
                     (lambda (&rest _)
                       (setq pandoc-called t)
                       0)))
            (should-error (my/markdown-convert-to-org) :type 'user-error))))
      (should-not pandoc-called)
      (should (equal (my/test-markdown--contents org-file) "original\n")))))

(ert-deftest my/markdown-convert-failure-preserves-existing-org-file ()
  (my/test-markdown--with-files
    (let ((auto-mode-alist nil))
      (with-current-buffer (find-file-noselect md-file)
        (setq major-mode 'markdown-mode)
        (cl-letf (((symbol-function 'executable-find) (lambda (_) "pandoc"))
                  ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                  ((symbol-function 'call-process)
                   (lambda (_program _in _destination _display &rest arguments)
                     (let ((output (cadr (member "-o" arguments))))
                       (write-region "partial\n" nil output nil 'silent))
                     1)))
          (should-error (my/markdown-convert-to-org) :type 'user-error))))
    (should (equal (my/test-markdown--contents org-file) "original\n"))))

(ert-deftest my/markdown-convert-refuses-unsaved-target-buffer ()
  (my/test-markdown--with-files
    (let ((pandoc-called nil)
          (auto-mode-alist nil))
      (with-current-buffer (find-file-noselect org-file)
        (goto-char (point-max))
        (insert "unsaved\n"))
      (with-current-buffer (find-file-noselect md-file)
        (setq major-mode 'markdown-mode)
        (cl-letf (((symbol-function 'executable-find) (lambda (_) "pandoc"))
                  ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                  ((symbol-function 'call-process)
                   (lambda (&rest _)
                     (setq pandoc-called t)
                     0)))
          (should-error (my/markdown-convert-to-org) :type 'user-error)))
      (should-not pandoc-called)
      (should (equal (my/test-markdown--contents org-file) "original\n")))))

;;; test-init-markdown.el ends here
