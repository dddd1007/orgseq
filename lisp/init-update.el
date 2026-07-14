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
  :if (not noninteractive)
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
;; Rollback:       M-x my/package-snapshot-rollback

(require 'cl-lib)

(defvar package-user-dir)
(defvar package-alist)
(declare-function package-desc-version "package" (desc) t)

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

;; ---- Package snapshots: one-command rollback for bad upgrades ----
;;
;; ELPA archives generally serve only the latest version of a package, so a
;; broken upstream release cannot be reverted from the network.  Before every
;; upgrade (manual or automatic), the whole `package-user-dir' is copied to a
;; timestamped directory under `my/update-snapshot-directory'.  If an upgrade
;; breaks the config, `M-x my/package-snapshot-rollback' restores the most
;; recent snapshot (the replaced tree is itself kept as a snapshot, so a
;; rollback can be undone the same way).

(defcustom my/update-snapshot-directory
  (expand-file-name "package-snapshots/" user-emacs-directory)
  "Directory holding pre-update snapshots of `package-user-dir'."
  :type 'directory
  :group 'org-seq)

(defcustom my/update-snapshot-keep 2
  "Number of package snapshots to keep.  Older snapshots are deleted."
  :type 'integer
  :group 'org-seq)

(defconst my/update--snapshot-name-regexp
  "\\`[0-9]\\{8\\}-[0-9]\\{6\\}\\(-replaced\\)?\\'"
  "Pattern for directory names org-seq recognizes (and prunes) as snapshots.")

(defun my/package-snapshot-list ()
  "Return existing snapshot directory names, newest first."
  (when (file-directory-p my/update-snapshot-directory)
    (sort (cl-remove-if-not
           (lambda (name)
             (and (string-match-p my/update--snapshot-name-regexp name)
                  (file-directory-p
                   (expand-file-name name my/update-snapshot-directory))))
           (directory-files my/update-snapshot-directory nil "\\`[^.]"))
          #'string>)))

(defun my/update--prune-snapshots ()
  "Delete snapshots beyond `my/update-snapshot-keep', oldest first."
  (dolist (name (nthcdr (max my/update-snapshot-keep 0)
                        (my/package-snapshot-list)))
    (delete-directory
     (expand-file-name name my/update-snapshot-directory) t)))

(defun my/package-snapshot-create ()
  "Snapshot `package-user-dir' before an upgrade.  Return the snapshot path.
Return nil when there is nothing to snapshot yet (no package directory).
Signal an error when the copy fails, so callers can abort the upgrade."
  (interactive)
  (if (not (file-directory-p package-user-dir))
      (progn
        (message "org-seq: no %s yet; skipping package snapshot" package-user-dir)
        nil)
    (let ((target (expand-file-name (format-time-string "%Y%m%d-%H%M%S")
                                    my/update-snapshot-directory)))
      (make-directory my/update-snapshot-directory t)
      (copy-directory package-user-dir target t t t)
      (my/update--prune-snapshots)
      (message "org-seq: package snapshot saved to %s" target)
      target)))

(defun my/package-snapshot-rollback (&optional name)
  "Restore `package-user-dir' from a snapshot (default: the most recent).
NAME is a directory name from `my/package-snapshot-list'.  The replaced
package tree is preserved as a `-replaced' snapshot so the rollback can
itself be undone.  Restart Emacs after rolling back."
  (interactive
   (let ((snapshots (my/package-snapshot-list)))
     (unless snapshots
       (user-error "org-seq: no package snapshots found in %s"
                   my/update-snapshot-directory))
     (list (completing-read "Restore package snapshot: " snapshots nil t
                            nil nil (car snapshots)))))
  (let* ((snapshots (my/package-snapshot-list))
         (name (or name (car snapshots)))
         (source (and name
                      (expand-file-name name my/update-snapshot-directory))))
    (unless (and source (file-directory-p source))
      (user-error "org-seq: snapshot %s does not exist" name))
    (when (yes-or-no-p
           (format "Replace %s with snapshot %s? " package-user-dir name))
      ;; Preserve the current tree so the rollback is reversible.
      (when (file-directory-p package-user-dir)
        (rename-file (directory-file-name package-user-dir)
                     (expand-file-name
                      (format-time-string "%Y%m%d-%H%M%S-replaced")
                      my/update-snapshot-directory)))
      (copy-directory source (directory-file-name package-user-dir) t t t)
      (my/update--prune-snapshots)
      (message "org-seq: restored package snapshot %s -- restart Emacs now"
               name))))

;; ---- Core update logic ----

(defun my/update--do-upgrade ()
  "Refresh archives, upgrade ELPA packages, then upgrade vc packages.
Return a summary string.  Signals an error (and performs no upgrade)
when the pre-update package snapshot cannot be created."
  (let ((upgraded-elpa 0)
        (upgraded-vc 0)
        (errors nil))

    ;; 0. Snapshot installed packages so a bad upgrade can be rolled back
    ;;    with `my/package-snapshot-rollback'.  A failed snapshot aborts the
    ;;    whole upgrade: no rollback point means no silent upgrades.
    (condition-case err
        (my/package-snapshot-create)
      (error
       (error "org-seq: package snapshot failed (%s); upgrade aborted"
              (error-message-string err))))

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
(unless noninteractive
  (add-hook 'emacs-startup-hook #'my/update-enable-auto))

(provide 'init-update)
;;; init-update.el ends here
