;;; init-focus.el --- org-focus-timer integration -*- lexical-binding: t; -*-

;; Requires: init-org (my/orgseq-dir)
(defvar my/orgseq-dir)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Package reference
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; `org-focus-timer' is currently developed as a subproject inside this
;; repository at `packages/org-focus-timer/'.  It may graduate to its own
;; standalone project later, at which point this module will switch to a
;; `:vc' reference.  For now we keep the source inside org-seq so that
;; iteration is fast: edit the file, `M-x eval-buffer', and changes take
;; effect without any re-deploy step.
;;
;; The default path below resolves to `<user-emacs-directory>/packages/
;; org-focus-timer/', which works both when you load this config from the
;; repository directly (deploy-free dev mode) and after `deploy.sh' copies
;; the `packages/' directory into `~/.emacs.d/'.  If you prefer to keep
;; the package elsewhere, override `my/focus-timer-path' via
;; `M-x customize-group RET org-seq'.

(eval-and-compile
  (defcustom my/focus-timer-path
    (expand-file-name "packages/org-focus-timer" user-emacs-directory)
    "Filesystem path to the org-focus-timer package source.
Default resolves to `packages/org-focus-timer/' inside
`user-emacs-directory', which is populated by `deploy.sh' from the
same directory inside the org-seq repository."
    :type 'directory
    :group 'org-seq))

(use-package org-focus-timer
  :if (file-exists-p (expand-file-name "org-focus-timer.el"
                                       my/focus-timer-path))
  :load-path my/focus-timer-path
  :commands (org-focus-start
             org-focus-abort
             org-focus-dashboard)
  :custom
  ;; Persist the focus log inside the per-library .orgseq/ directory so
  ;; it sits next to ai-config.org and capture-templates.el, gets backed
  ;; up together with the rest of the notes, and does not pollute the
  ;; repo-managed ~/.emacs.d/.
  (org-focus-log-file (expand-file-name "focus-log.org" my/orgseq-dir))
  ;; Vitamin-R-style defaults: slices end on a quarter-hour boundary
  ;; between 10 and 30 minutes from now.
  (org-focus-min-duration 10)
  (org-focus-max-duration 30)
  (org-focus-round-to 15)
  ;; Show two weeks of history in the dashboard.
  (org-focus-dashboard-days 14))

;; Warn the user once if the package is not yet on disk.  Deferred via an
;; idle timer so the message appears after the startup banner instead of
;; being buried under package-install output.
(unless (file-exists-p (expand-file-name "org-focus-timer.el"
                                         my/focus-timer-path))
  (run-with-idle-timer
   3 nil
   (lambda ()
     (message "org-seq: org-focus-timer not found at %s. \
Re-run deploy.sh (or deploy.ps1) to copy the bundled package."
              my/focus-timer-path))))

(provide 'init-focus)
;;; init-focus.el ends here
