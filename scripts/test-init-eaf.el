;;; test-init-eaf.el --- Tests for org-seq EAF helpers -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defvar my/eaf-pyqterminal-font-size)
(declare-function my/eaf--terminal-font-size "init-eaf")
(declare-function my/eaf-apply-community-tuning "init-eaf")

(load-file (expand-file-name "../lisp/init-eaf.el" (file-name-directory load-file-name)))

(ert-deftest my/eaf-terminal-font-size-follows-frame-char-height-when-auto ()
  (let ((my/eaf-pyqterminal-font-size nil))
    (cl-letf (((symbol-function 'frame-char-height)
               (lambda (&optional _frame) 23)))
      (should (= (my/eaf--terminal-font-size) 23)))))

(ert-deftest my/eaf-community-tuning-enables-emacs-terminal-colors ()
  (let ((my/eaf-pyqterminal-font-size nil))
    (cl-letf (((symbol-function 'frame-char-height)
               (lambda (&optional _frame) 23)))
      (my/eaf-apply-community-tuning)
      (should (bound-and-true-p eaf-pyqterminal-color-schema-from-emacs)))))

;;; test-init-eaf.el ends here
