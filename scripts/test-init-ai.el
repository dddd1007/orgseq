;;; test-init-ai.el --- Tests for AI send boundaries -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'use-package)

(setq my/orgseq-dir user-emacs-directory
      my/roam-dir user-emacs-directory)

(defun my/vc-package-ensure (_package) nil)

(load-file
 (expand-file-name "../lisp/init-ai.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/ai-full-buffer-send-requires-confirmation-by-default ()
  (with-temp-buffer
    (insert "private draft")
    (let ((my/ai-confirm-full-buffer-send t))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (should-error (my/ai--get-text) :type 'user-error)))))

(ert-deftest my/ai-active-region-does-not-prompt-for-full-buffer ()
  (with-temp-buffer
    (insert "keep send-this keep")
    (goto-char 6)
    (push-mark 15 t t)
    (let ((transient-mark-mode t)
          (mark-active t)
          (prompted nil))
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (&rest _)
                   (setq prompted t)
                   nil)))
        (should (equal (my/ai--get-text) "send-this"))
        (should-not prompted)))))

;;; test-init-ai.el ends here
