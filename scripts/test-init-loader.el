;;; test-init-loader.el --- Tests for org-seq module loading -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defvar my/init-modules)
(defvar my/init-modules-default)
(defvar my/init-module-requires)

(defvar my/test-loader--root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory load-file-name)))
  "Repository root for locating module sources.")

(let* ((root my/test-loader--root)
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

(ert-deftest my/init-failed-modules-returns-attempt-order ()
  (let ((my/--init-results
         '((:module init-third :status failed :elapsed 0.3 :error third)
           (:module init-second :status loaded :elapsed 0.2 :error nil)
           (:module init-first :status failed :elapsed 0.1 :error first))))
    (should (equal (my/init-failed-modules)
                   '(init-first init-third)))))

(ert-deftest my/init-module-order-satisfies-declared-dependencies ()
  "The canonical module list must satisfy `my/init-module-requires'."
  (should (null (my/init-check-module-order my/init-modules-default))))

(ert-deftest my/init-module-requires-covers-only-known-modules ()
  "Every module and dependency in the contract must be a real module."
  (dolist (entry my/init-module-requires)
    (should (memq (car entry) my/init-modules-default))
    (dolist (dep (cdr entry))
      (should (memq dep my/init-modules-default)))))

(ert-deftest my/init-check-module-order-detects-inverted-order ()
  (should (equal (my/init-check-module-order
                  '(init-b init-a)
                  '((init-b . (init-a))))
                 '((init-b . "dependency init-a loads after it")))))

(ert-deftest my/init-check-module-order-detects-missing-dependency ()
  (should (equal (my/init-check-module-order
                  '(init-b)
                  '((init-b . (init-a))))
                 '((init-b . "dependency init-a is not in my/init-modules")))))

(ert-deftest my/init-check-module-order-ignores-disabled-modules ()
  "A module removed from the load list is not checked for its own deps."
  (should (null (my/init-check-module-order
                 '(init-a)
                 '((init-b . (init-a)))))))

(defun my/test-loader--declared-requires (module)
  "Return modules named on \"Requires:\" comment lines of MODULE's source."
  (let ((file (expand-file-name (format "lisp/%s.el" module)
                                my/test-loader--root))
        (found nil))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^;; Requires: \\(.*\\)$" nil t)
          (let ((line (match-string 1))
                (start 0))
            (while (string-match "\\binit-[a-z-]+\\b" line start)
              (push (intern (match-string 0 line)) found)
              (setq start (match-end 0)))))))
    (cl-remove-duplicates (nreverse found))))

(ert-deftest my/init-module-requires-matches-source-headers ()
  "`my/init-module-requires' must mirror the module \"Requires:\" headers."
  (dolist (module my/init-modules-default)
    (let ((declared (my/test-loader--declared-requires module))
          (contract (cdr (assq module my/init-module-requires))))
      (should (equal (sort (copy-sequence declared) #'string<)
                     (sort (copy-sequence contract) #'string<))))))

;;; test-init-loader.el ends here
