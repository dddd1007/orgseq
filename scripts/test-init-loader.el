;;; test-init-loader.el --- Tests for org-seq module loading -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defvar my/init-modules)

(let* ((root (file-name-as-directory
              (expand-file-name ".." (file-name-directory load-file-name))))
       (user-emacs-directory root)
       (my/init-modules nil))
  (load-file (expand-file-name "init.el" root)))

(ert-deftest my/init-loader-records-success-and-elapsed-time ()
  (let ((my/--init-errors nil)
        (my/--init-results nil)
        (times '(10.0 10.25)))
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time) (pop times)))
              ((symbol-function 'require)
               (lambda (_module &optional _filename _noerror) t)))
      (should (my/--require-module 'init-test-success)))
    (should-not my/--init-errors)
    (should
     (equal (my/init-results)
            '((:module init-test-success
               :status loaded
               :elapsed 0.25
               :error nil))))))

(ert-deftest my/init-loader-records-failure-with-original-error ()
  (let ((my/--init-errors nil)
        (my/--init-results nil)
        (times '(20.0 20.5)))
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time) (pop times)))
              ((symbol-function 'require)
               (lambda (&rest _arguments) (error "loader boom"))))
      (should-not (my/--require-module 'init-test-failure)))
    (let ((result (car (my/init-results))))
      (should (eq (plist-get result :module) 'init-test-failure))
      (should (eq (plist-get result :status) 'failed))
      (should (= (plist-get result :elapsed) 0.5))
      (should (equal (error-message-string (plist-get result :error))
                     "loader boom")))
    (should (eq (caar my/--init-errors) 'init-test-failure))))

(ert-deftest my/init-results-preserves-module-attempt-order ()
  (let ((my/--init-errors nil)
        (my/--init-results nil))
    (cl-letf (((symbol-function 'require)
               (lambda (_module &optional _filename _noerror) t)))
      (my/--require-module 'init-first)
      (my/--require-module 'init-second))
    (should (equal (mapcar (lambda (result) (plist-get result :module))
                           (my/init-results))
                   '(init-first init-second)))))

;;; test-init-loader.el ends here
