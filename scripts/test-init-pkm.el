;;; test-init-pkm.el --- Tests for governed org-supertag patches -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defmacro use-package (&rest _args) nil)
(defun my/vc-package-ensure (_package) nil)

(load-file
 (expand-file-name "../lisp/init-pkm.el"
                   (file-name-directory load-file-name)))

(defun my/test-supertag--write (file contents)
  (make-directory (file-name-directory file) t)
  (write-region contents nil file nil 'silent))

(defmacro my/test-supertag--with-package (commit &rest body)
  (declare (indent 1) (debug t))
  `(let* ((root (make-temp-file "org-seq-supertag-" t))
          (package-dir (expand-file-name "org-supertag/" root))
          (backup-dir (expand-file-name "backups/" root))
          (main (expand-file-name "org-supertag.el" package-dir))
          (pkg (expand-file-name "org-supertag-pkg.el" package-dir))
          (fixture (expand-file-name "fixture.el" package-dir))
          (old "(mapcar (lambda (t) t) values)\n")
          (new "(mapcar (lambda (value) value) values)\n")
          (load-path (cons package-dir load-path))
          (my/supertag-compat-backup-directory backup-dir)
          (my/supertag--compat-version "5.8.1")
          (my/supertag--compat-commit "abcdef0123456789"))
     (unwind-protect
         (progn
           (my/test-supertag--write
            main ";;; org-supertag.el --- fixture\n;; Version: 5.8.1\n(provide 'org-supertag)\n")
           (my/test-supertag--write
            pkg (format "(define-package \"org-supertag\" \"5.8.1\" \"fixture\" nil :kind 'vc :commit \"%s\")\n"
                        ,commit))
           (my/test-supertag--write fixture old)
           (let ((original-hash (my/supertag--git-blob-sha1 fixture)))
             (my/test-supertag--write fixture new)
             (let ((patched-hash (my/supertag--git-blob-sha1 fixture)))
               (my/test-supertag--write fixture old)
               (let ((my/supertag--compat-specs
                      `((:file "fixture.el"
                         :original-hash ,original-hash
                         :patched-hash ,patched-hash
                         :replacements ((,old . ,new))))))
                 ,@body))))
       (delete-directory root t))))

(ert-deftest my/supertag-compat-patch-is-backed-up-and-reversible ()
  (my/test-supertag--with-package "abcdef0123456789"
    (should (eq (my/supertag-apply-compat-patches) 'patched))
    (should (equal (with-temp-buffer
                     (insert-file-contents fixture)
                     (buffer-string))
                   new))
    (should (= (length (directory-files-recursively backup-dir "\\.el\\'")) 1))
    (should (eq (my/supertag-rollback-compat-patches) 'restored))
    (should (equal (with-temp-buffer
                     (insert-file-contents fixture)
                     (buffer-string))
                   old))))

(ert-deftest my/supertag-compat-patch-reconstructs-backup-for-known-patched-source ()
  (my/test-supertag--with-package "abcdef0123456789"
    (my/test-supertag--write fixture new)
    (should (eq (my/supertag-apply-compat-patches) 'current))
    (should (= (length (directory-files-recursively backup-dir "\\.el\\'")) 1))
    (should (eq (my/supertag-rollback-compat-patches) 'restored))
    (should (equal (with-temp-buffer
                     (insert-file-contents fixture)
                     (buffer-string))
                   old))))

(ert-deftest my/supertag-compat-patch-refuses-drifted-source ()
  (my/test-supertag--with-package "abcdef0123456789"
    (my/test-supertag--write fixture "locally modified\n")
    (should (eq (my/supertag-apply-compat-patches) 'unsupported))
    (should (equal (with-temp-buffer
                     (insert-file-contents fixture)
                     (buffer-string))
                   "locally modified\n"))))

(ert-deftest my/supertag-compat-patch-refuses-unknown-revision ()
  (my/test-supertag--with-package "deadbeef"
    (should (eq (my/supertag-apply-compat-patches) 'unsupported))
    (should (equal (with-temp-buffer
                     (insert-file-contents fixture)
                     (buffer-string))
                   old))
    (should-not (file-exists-p backup-dir))))

;;; test-init-pkm.el ends here
