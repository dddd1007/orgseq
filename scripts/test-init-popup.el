;;; test-init-popup.el --- Tests for org-seq popup policy -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(load-file
 (expand-file-name "../lisp/init-popup.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/popup-register-rules-preserves-user-rules-and-is-idempotent ()
  (let ((display-buffer-alist
         '(("\\`\\*user-owned\\*\\'" display-buffer-same-window)))
        (my/popup-rules
         '((:id test :matcher "\\`\\*org-seq-test\\*\\'"
            :side bottom :slot 2 :height 0.25 :select t))))
    (my/popup-register-rules)
    (my/popup-register-rules)
    (should (= (length display-buffer-alist) 2))
    (should (equal (caar display-buffer-alist)
                   "\\`\\*user-owned\\*\\'"))
    (should (eq (cdr (assq 'my/popup-rule-id
                           (cdr (cadr display-buffer-alist))))
                'test))))

(ert-deftest my/popup-rule-builds-side-window-action ()
  (let* ((spec '(:id test :matcher "test" :side right :slot 3
                 :width 0.4 :select nil :dedicated t))
         (rule (my/popup--build-rule spec)))
    (should (equal (car rule) "test"))
    (should (memq 'display-buffer-in-side-window (cadr rule)))
    (should (eq (cdr (assq 'side (cddr rule))) 'right))
    (should (= (cdr (assq 'slot (cddr rule))) 3))
    (should (= (cdr (assq 'window-width (cddr rule))) 0.4))
    (should (eq (cdr (assq 'dedicated (cddr rule))) t))))

(ert-deftest my/popup-display-buffer-selects-registered-popup ()
  (let ((my/popup-rules
         '((:id test :matcher "\\`\\*org-seq-popup\\*\\'"
            :side bottom :height 0.3 :select t)))
        (buffer (get-buffer-create "*org-seq-popup*"))
        captured-action
        selected)
    (unwind-protect
        (cl-letf (((symbol-function 'display-buffer)
                   (lambda (_buffer action)
                     (setq captured-action action)
                     'test-window))
                  ((symbol-function 'select-window)
                   (lambda (window &optional _norecord)
                     (setq selected window))))
          (should (eq (my/popup-display-buffer buffer) 'test-window))
          (should (eq selected 'test-window))
          (should (= (cdr (assq 'window-height (cdr captured-action)))
                     0.3)))
      (kill-buffer buffer))))

(ert-deftest my/popup-display-buffer-applies-call-site-overrides ()
  (let ((my/popup-rules
         '((:id test :matcher "\\`\\*override\\*\\'"
            :side bottom :height 0.3 :select nil)))
        (buffer (get-buffer-create "*override*"))
        captured-action)
    (unwind-protect
        (cl-letf (((symbol-function 'display-buffer)
                   (lambda (_buffer action)
                     (setq captured-action action)
                     'test-window)))
          (my/popup-display-buffer buffer '(:height 0.6 :select nil))
          (should (= (cdr (assq 'window-height (cdr captured-action)))
                     0.6)))
      (kill-buffer buffer))))

;;; test-init-popup.el ends here
