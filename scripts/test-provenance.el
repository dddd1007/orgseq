;;; test-provenance.el --- Completion and provenance checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst my/test-provenance-root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory load-file-name))))

(defun my/test-provenance--contents (path)
  "Return repository-relative PATH contents."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path my/test-provenance-root))
    (buffer-string)))

(defun my/test-provenance--runtime-modules ()
  "Read the canonical module list from init.el without loading the config.
The literal list lives in the `my/init-modules-default' defconst;
`my/init-modules' references it."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" my/test-provenance-root))
    (goto-char (point-min))
    (re-search-forward "^(defconst my/init-modules-default")
    (goto-char (match-beginning 0))
    (cadr (nth 2 (read (current-buffer))))))

(ert-deftest my/provenance-records-donor-boundaries ()
  (let ((contents (my/test-provenance--contents "THIRD_PARTY.md")))
    (dolist (required '("Doom Emacs" "MIT"
                        "Spacemacs" "GPL-3.0"
                        "LazyVim" "Apache-2.0"
                        "design-only" "lisp/init-roam.el"))
      (should (string-match-p (regexp-quote required) contents)))))

(ert-deftest my/runtime-has-no-eaf-module-or-terminal-residue ()
  (should-not (file-exists-p
               (expand-file-name "lisp/init-eaf.el" my/test-provenance-root)))
  (dolist (path '("init.el" "lisp/init-terminal.el" "lisp/init-evil.el"))
    (let ((contents (downcase (my/test-provenance--contents path))))
      (should-not (string-match-p "init-eaf\\|pyqterminal" contents)))))

(ert-deftest my/documented-module-order-matches-runtime ()
  (let ((order (mapconcat #'symbol-name
                          (my/test-provenance--runtime-modules)
                          " -> ")))
    (dolist (path '("AGENTS.md" "skills/org-seq-elisp-maintenance/SKILL.md"))
      (should (string-match-p (regexp-quote order)
                              (my/test-provenance--contents path))))))

(ert-deftest my/popup-policy-is-the-only-display-buffer-registry-owner ()
  (dolist (file (directory-files (expand-file-name "lisp" my/test-provenance-root)
                                 t "\\`init-.*\\.el\\'"))
    (unless (equal (file-name-nondirectory file) "init-popup.el")
      (should-not
       (string-match-p
        "display-buffer-alist"
        (my/test-provenance--contents
         (file-relative-name file my/test-provenance-root)))))))

(ert-deftest my/daily-module-loads-between-supertag-and-terminal ()
  (let ((modules (my/test-provenance--runtime-modules)))
    (should (equal (seq-filter
                    (lambda (module)
                      (memq module '(init-supertag init-daily init-terminal)))
                    modules)
                   '(init-supertag init-daily init-terminal)))))

(ert-deftest my/dashboard-daily-section-precedes-recents ()
  (let* ((contents (my/test-provenance--contents "lisp/init-dashboard.el"))
         (daily (string-match "(daily \\. 5)" contents))
         (recents (string-match "(recents \\. 5)" contents))
         (today (string-match "\" Today \"" contents)))
    (should daily)
    (should recents)
    (should (< daily recents))
    (should today)
    (should (string-match-p
             "my/daily-workspace-open"
             (substring contents today (min (length contents)
                                            (+ today 400)))))))

;;; test-provenance.el ends here
