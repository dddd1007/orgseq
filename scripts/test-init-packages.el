;;; test-init-packages.el --- Tests for VC package governance -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(load-file
 (expand-file-name "../lisp/init-packages.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/vc-package-specs-have-unique-complete-records ()
  (let ((packages nil))
    (dolist (spec my/vc-package-specs)
      (dolist (key '(:package :library :url :owner :purpose))
        (should (plist-get spec key)))
      (push (plist-get spec :package) packages))
    (should (= (length packages)
               (length (delete-dups packages))))))

(ert-deftest my/vc-package-inventory-covers-current-git-sources ()
  (should (equal (mapcar (lambda (spec) (plist-get spec :package))
                         my/vc-package-specs)
                 '(modusregel org-modern-indent org-supertag
                   ob-gptel claude-code))))

(ert-deftest my/vc-package-ensure-never-installs-noninteractively ()
  (let ((noninteractive t)
        installed)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (_package) nil))
              ((symbol-function 'locate-library)
               (lambda (_library) nil))
              ((symbol-function 'package-vc-install)
               (lambda (&rest _arguments) (setq installed t))))
      (should (eq (my/vc-package-ensure 'modusregel) 'skipped))
      (should-not installed))))

(ert-deftest my/vc-package-ensure-installs-from-registered-url ()
  (let ((noninteractive nil)
        installed-url)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (_package) nil))
              ((symbol-function 'locate-library)
               (lambda (_library) nil))
              ((symbol-function 'package-vc-install)
               (lambda (url &rest _arguments)
                 (setq installed-url url))))
      (should (eq (my/vc-package-ensure 'modusregel) 'installed))
      (should (equal installed-url
                     "https://codeberg.org/jjba23/modusregel.git")))))

(ert-deftest my/vc-package-ensure-rejects-unregistered-packages ()
  (should-error (my/vc-package-ensure 'unregistered-package)
                :type 'user-error))

(ert-deftest my/vc-package-statuses-are-read-only ()
  (let (installed)
    (cl-letf (((symbol-function 'package-installed-p)
               (lambda (_package) nil))
              ((symbol-function 'locate-library)
               (lambda (_library) nil))
              ((symbol-function 'package-vc-install)
               (lambda (&rest _arguments) (setq installed t))))
      (let ((statuses (my/vc-package-statuses)))
        (should (= (length statuses) (length my/vc-package-specs)))
        (should (cl-every (lambda (status)
                            (eq (plist-get status :status) 'missing))
                          statuses)))
      (should-not installed))))

;;; test-init-packages.el ends here
