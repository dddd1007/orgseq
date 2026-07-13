;;; test-startup-policy.el --- Tests for startup delay policy -*- lexical-binding: t; -*-

(require 'ert)

(defconst my/test--repo-root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory load-file-name))))

(defun my/test--numeric-defer-sites ()
  "Return numeric :defer sites and nearby source context."
  (let* ((files (directory-files (expand-file-name "lisp" my/test--repo-root)
                                 t "\\`init-.*\\.el\\'"))
         sites)
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward ":defer[ \\t]+[0-9]+" nil t)
          (let* ((line (line-number-at-pos))
                 (end (line-end-position))
                 (start (save-excursion
                          (forward-line -5)
                          (line-beginning-position))))
            (push (list :file file :line line
                        :context (buffer-substring-no-properties start end))
                  sites)))))
    (nreverse sites)))

(ert-deftest my/startup-numeric-defers-have-explicit-rationale ()
  (let ((sites (my/test--numeric-defer-sites)))
    (should (= (length sites) 3))
    (dolist (site sites)
      (should (string-match-p "NOTE(startup):"
                              (plist-get site :context))))))

;;; test-startup-policy.el ends here
