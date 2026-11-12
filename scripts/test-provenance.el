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
                        "design-only"))
      (should (string-match-p (regexp-quote required) contents)))))

;; org-roam is not part of org-seq.  The only text that may still name it
;; is the old database file name (old libraries can still hold one that
;; sync and snapshots must skip) and the one sentence saying where the
;; capture template format comes from.
(defconst my/test-provenance-roam-allowed-lines
  '("org-roam.db" "common subset of the org-roam-capture format")
  "Substrings that excuse a source line from the org-roam residue check.")

(ert-deftest my/runtime-has-no-org-roam-residue ()
  (let ((case-fold-search nil)
        (offenders nil))
    (dolist (dir '("core" "kernel" "modules"))
      (dolist (file (directory-files-recursively
                     (expand-file-name dir my/test-provenance-root) "\\.el\\'"))
        (unless (equal (file-name-nondirectory file) "dashboard-quotes.el")
          (with-temp-buffer
            (insert-file-contents file)
            (let ((n 0))
              (dolist (line (split-string (buffer-string) "\n"))
                (setq n (1+ n))
                (when (and (string-match-p
                            "org-roam-\\|org-node\\|org-mem\\|init-roam" line)
                           (not (seq-some (lambda (ok) (string-search ok line))
                                          my/test-provenance-roam-allowed-lines)))
                  (push (format "%s:%d" (file-relative-name
                                         file my/test-provenance-root)
                                n)
                        offenders))))))))
    (should-not offenders)))

(ert-deftest my/runtime-has-no-eaf-module-or-terminal-residue ()
  (should-not (file-exists-p
               (expand-file-name "modules/tools/init-eaf.el" my/test-provenance-root)))
  (dolist (path '("init.el" "modules/tools/init-terminal.el" "modules/editor/init-evil.el"))
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
  (dolist (file (append
                 (directory-files-recursively
                  (expand-file-name "core" my/test-provenance-root)
                  "\\`init-.*\\.el\\'")
                 (directory-files-recursively
                  (expand-file-name "modules" my/test-provenance-root)
                  "\\`init-.*\\.el\\'")))
    (unless (equal (file-name-nondirectory file) "init-popup.el")
      (should-not
       (string-match-p
        "display-buffer-alist"
        (my/test-provenance--contents
         (file-relative-name file my/test-provenance-root)))))))

(ert-deftest my/daily-module-loads-between-nodes-and-terminal ()
  (let ((modules (my/test-provenance--runtime-modules)))
    (should (equal (seq-filter
                    (lambda (module)
                      (memq module '(init-nodes init-daily init-terminal)))
                    modules)
                   '(init-nodes init-daily init-terminal)))))

(ert-deftest my/dashboard-daily-section-precedes-recents ()
  (let* ((contents (my/test-provenance--contents "modules/ui/init-dashboard.el"))
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
