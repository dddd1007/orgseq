;;; init-update.el --- Periodic silent package auto-update -*- lexical-binding: t; -*-

;; ═══════════════════════════════════════════════════════════════════════════
;; compile-angel: keep .elc / .eln outputs current automatically
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Silently byte-compiles (and native-compiles, when supported) any elisp
;; file whose compiled artifact is missing or older than the source.  Runs
;; before load and on save, so freshly upgraded ELPA packages and user
;; edits alike stay at native-comp speed without manual intervention.
;;
;; Complements the PostToolUse byte-compile hook: that hook covers edits
;; made by Claude Code; compile-angel covers interactive editing and
;; third-party package loads.

(use-package compile-angel
  :demand t
  :custom
  (compile-angel-verbose nil)
  :config
  (compile-angel-on-load-mode)
  (add-hook 'emacs-lisp-mode-hook #'compile-angel-on-save-local-mode))

;; ═══════════════════════════════════════════════════════════════════════════
;; Automatic package updates
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Updates all ELPA and vc-installed packages on a configurable interval.
;; Runs silently in the background after Emacs has been idle, so it never
;; blocks interactive use.  A timestamp file tracks the last update time.
;;
;; Manual trigger: M-x my/package-update-all  (also bound to SPC q u)

(require 'cl-lib)

(defcustom my/update-interval-days 7
  "Minimum number of days between automatic package updates."
  :type 'integer
  :group 'org-seq)

(defcustom my/update-idle-delay 120
  "Seconds of idle time before triggering an automatic update check.
Set high to avoid running during active editing."
  :type 'integer
  :group 'org-seq)

(defvar my/update--timestamp-file
  (expand-file-name ".last-package-update" user-emacs-directory)
  "File storing the epoch of the last successful auto-update.")

;; ---- Timestamp persistence ----

(defun my/update--last-time ()
  "Return the epoch (integer) of the last successful update, or 0."
  (if (file-exists-p my/update--timestamp-file)
      (condition-case nil
          (string-to-number
           (string-trim
            (with-temp-buffer
              (insert-file-contents my/update--timestamp-file)
              (buffer-string))))
        (error 0))
    0))

(defun my/update--save-time ()
  "Write current epoch to the timestamp file."
  (with-temp-file my/update--timestamp-file
    (insert (number-to-string (truncate (float-time))))))

(defun my/update--due-p ()
  "Return non-nil if enough days have passed since the last update."
  (let* ((last (my/update--last-time))
         (now  (truncate (float-time)))
         (elapsed-days (/ (- now last) 86400.0)))
    (>= elapsed-days my/update-interval-days)))

;; ---- Core update logic ----

(defun my/update--do-upgrade ()
  "Refresh archives, upgrade ELPA packages, then upgrade vc packages.
Return a summary string."
  (let ((upgraded-elpa 0)
        (upgraded-vc 0)
        (errors nil))

    ;; 1. Refresh package archives
    (condition-case err
        (package-refresh-contents)
      (error (push (format "archive refresh: %s" err) errors)))

    ;; 2. Upgrade ELPA packages (Emacs 29+)
    (condition-case err
        (let ((before (copy-sequence package-alist)))
          (package-upgrade-all)
          ;; Count how many changed (heuristic: any package whose version differs)
          (setq upgraded-elpa
                (cl-count-if
                 (lambda (entry)
                   (let* ((name (car entry))
                          (old  (cadr (assq name before))))
                     (and old (not (equal (package-desc-version (cadr entry))
                                         (package-desc-version old))))))
                 package-alist)))
      (error (push (format "ELPA upgrade: %s" err) errors)))

    ;; 3. Upgrade vc-installed packages (Emacs 29+)
    (condition-case err
        (progn
          (package-vc-upgrade-all)
          ;; package-vc-upgrade-all does not return a count; just mark as done
          (setq upgraded-vc t))
      (error (push (format "vc upgrade: %s" err) errors)))

    ;; Build summary
    (let ((parts nil))
      (when (> upgraded-elpa 0)
        (push (format "%d ELPA package%s upgraded"
                      upgraded-elpa (if (= upgraded-elpa 1) "" "s"))
              parts))
      (when (and (eq upgraded-vc t) (null errors))
        (push "vc packages checked" parts))
      (when errors
        (push (format "%d error%s: %s"
                      (length errors) (if (= (length errors) 1) "" "s")
                      (string-join errors "; "))
              parts))
      (when (and (= upgraded-elpa 0) (null errors))
        (push "all packages up to date" parts))
      (string-join (nreverse parts) ", "))))

;; ---- Interactive command ----

(defun my/package-update-all ()
  "Refresh archives and upgrade all packages (ELPA + vc).
Shows progress in the echo area."
  (interactive)
  (message "org-seq: updating packages...")
  (let ((summary (my/update--do-upgrade)))
    (my/update--save-time)
    (message "org-seq: %s" summary)))

;; ---- Automatic timer ----

(defvar my/update--timer nil
  "Idle timer for automatic package updates.")

(defun my/update--maybe-run ()
  "Check interval and run update if due.  Called from idle timer."
  (when (my/update--due-p)
    (message "org-seq: auto-updating packages in background...")
    (condition-case err
        (let ((summary (my/update--do-upgrade)))
          (my/update--save-time)
          (message "org-seq: auto-update done -- %s" summary))
      (error
       (message "WARNING org-seq: auto-update failed: %s" err)))))

(defun my/update-enable-auto ()
  "Enable periodic automatic package updates."
  (interactive)
  (when my/update--timer
    (cancel-timer my/update--timer))
  (setq my/update--timer
        (run-with-idle-timer my/update-idle-delay nil
                             #'my/update--maybe-run)))

;; Schedule on startup (one-shot idle timer; re-arms only on next restart)
(add-hook 'emacs-startup-hook #'my/update-enable-auto)

(provide 'init-update)
;;; init-update.el ends here
