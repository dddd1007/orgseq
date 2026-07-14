;;; test-init-update.el --- Tests for package update status -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'use-package)

(load-file
 (expand-file-name "../lisp/init-update.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/package-update-failure-is-not-recorded-as-success ()
  (let ((saved nil)
        (package-alist nil))
    (cl-letf (((symbol-function 'my/package-snapshot-create) #'ignore)
              ((symbol-function 'package-refresh-contents)
               (lambda () (error "archive unavailable")))
              ((symbol-function 'package-upgrade-all) #'ignore)
              ((symbol-function 'package-vc-upgrade-all) #'ignore)
              ((symbol-function 'my/update--save-time)
               (lambda () (setq saved t))))
      (should-error (my/package-update-all))
      (should-not saved))))

;;; test-init-update.el ends here
