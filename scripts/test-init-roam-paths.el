;;; test-init-roam-paths.el --- Tests for centralized roam paths -*- lexical-binding: t; -*-

(require 'ert)

(defconst my/test-init-roam--source-file
  (expand-file-name "../lisp/init-roam.el"
                    (file-name-directory load-file-name)))

(ert-deftest my/init-roam-consumes-central-para-paths ()
  "Keep org-mem watch roots owned by init-org instead of rebuilding strings."
  (let ((source
         (with-temp-buffer
           (insert-file-contents my/test-init-roam--source-file)
           (buffer-string))))
    (should-not (string-match-p "10_Outputs/" source))
    (should-not (string-match-p "20_Practice/" source))
    (should (string-match-p "my/outputs-dir" source))
    (should (string-match-p "my/practice-dir" source))))

;;; test-init-roam-paths.el ends here
