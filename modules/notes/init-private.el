;;; init-private.el --- Private zone outside the library -*- lexical-binding: t; -*-
;;
;; The private zone (`my/private-dir', private/ under the Emacs directory)
;; holds notes that must not be found by accident: counseling records.
;; It is isolated by where it sits, not by a list of exceptions:
;;
;;   Index     Only files under the library are nodes, so nothing in the
;;             zone appears in views, node search, backlinks, the command
;;             line or MCP.
;;   Sync      rclone syncs the library directory; the zone never leaves
;;             this device.
;;   Search    Text search and the AI command-line tools start at the
;;             library, not at the zone.
;;   AI        The in-buffer AI helpers refuse a buffer in the zone.
;;   Copies    Emacs backup files are switched off in zone buffers (they
;;             would land in backups/ under the Emacs directory) and zone
;;             files stay out of the recent-file list (init-dashboard).  Dated
;;             local copies go to a directory of their own beside the
;;             library snapshots.
;;
;; What it does not do: files are plain text readable by this user account,
;; not encrypted, and a tool given the path can read them.
;;
;; Section 1  Zone directory and status
;; Section 2  Buffers
;; Section 3  Commands
;; Section 4  Local copies

;; Requires: init-org  (library paths)
;; Requires: init-sync (my/storage-copy-missing, snapshot settings)
(defvar my/note-home)
(defvar my/private-dir)
(defvar my/snapshot-dir)
(defvar my/storage-snapshot-keep)
(defvar my/storage-snapshot-auto)
(defvar my/storage--snapshot-name-regexp)

(require 'cl-lib)
(require 'subr-x)

(declare-function my/private-file-p "orgseq-paths" (file))
(declare-function my/private-inside-library-p "orgseq-paths" ())
(declare-function my/note-create "orgseq-note" (&rest keys))
(declare-function my/note-slug "orgseq-note" (title))
(declare-function my/storage-copy-missing "init-sync" (source target))
(declare-function my/storage--files "init-sync" (dir))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Zone directory and status
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/private--dir ()
  "Return the private zone as an absolute directory name."
  (file-name-as-directory (expand-file-name my/private-dir)))

(defun my/private-ensure-dir ()
  "Create the private zone, readable by its owner only; return it."
  (let ((dir (my/private--dir)))
    (unless (file-directory-p dir)
      (with-file-modes #o700 (make-directory dir t)))
    dir))

(defun my/private--files ()
  "Return the files in the private zone."
  (let ((dir (my/private--dir)))
    (and (file-directory-p dir)
         (cl-remove-if #'file-symlink-p
                       (directory-files-recursively dir "" nil)))))

(defun my/private-info ()
  "Return a plist describing the private zone.
Read-only: creates nothing.  Holds counts only, never names or text."
  (let* ((dir (my/private--dir))
         (exists (file-directory-p dir))
         (files (my/private--files))
         (modes (and exists (file-modes dir))))
    (list :dir dir
          :exists exists
          :files (length files)
          :notes (cl-count-if (lambda (file) (string-suffix-p ".org" file)) files)
          :inside-library (my/private-inside-library-p)
          ;; Windows has no owner/group/other bits worth checking.
          :open-to-others (and modes (not (eq system-type 'windows-nt))
                               (/= 0 (logand modes #o077)))
          :snapshot-dir (my/private-snapshot-dir)
          :snapshots (length (my/private-snapshots)))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Buffers
;; ═══════════════════════════════════════════════════════════════════════════

(define-minor-mode my/private-mode
  "Mark a buffer as belonging to the private zone.
Switches off Emacs backup files for the buffer; the mode line shows
\"Private\"."
  :lighter " Private"
  (if my/private-mode
      (setq-local backup-inhibited t)
    (kill-local-variable 'backup-inhibited)))

(defun my/private--find-file ()
  "Turn on `my/private-mode' in a buffer that visits a private file."
  (when (and buffer-file-name (my/private-file-p buffer-file-name))
    (my/private-mode 1)))

(add-hook 'find-file-hook #'my/private--find-file)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Commands
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/private-open ()
  "Open the private zone in Dired, creating it when missing."
  (interactive)
  (dired (my/private-ensure-dir)))

(defun my/private-new-note (title &optional folder)
  "Create a note titled TITLE in the private zone and visit it.
FOLDER is a directory inside the zone (default: its top).  The note is a
plain Org file: it is not indexed, so it has no backlinks and no view
shows it."
  (interactive
   (list (read-string "Private note title: ")
         (let* ((dir (my/private-ensure-dir))
                (folders (cl-remove-if-not
                          (lambda (name)
                            (file-directory-p (expand-file-name name dir)))
                          (directory-files dir nil
                                           directory-files-no-dot-files-regexp)))
                (choice (completing-read "Folder (empty: top of the zone): "
                                         folders nil nil)))
           (and (not (string-empty-p choice)) choice))))
  (my/private-ensure-dir)
  (let ((note (my/note-create
               :title title :private t
               :file (expand-file-name
                      (format "%s-%s.org" (format-time-string "%Y%m%dT%H%M%S")
                              (my/note-slug title))
                      (if folder
                          (expand-file-name folder (my/private--dir))
                        (my/private--dir))))))
    (when (called-interactively-p 'interactive)
      (find-file (plist-get note :file))
      (goto-char (point-max)))
    note))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Local copies
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; The zone is not part of library snapshots (those can be exported and
;; restored into the library).  It gets dated copies of its own in a
;; sibling of the snapshot directory, on this device only.

(defun my/private-snapshot-dir ()
  "Return the directory holding dated copies of the private zone."
  (file-name-as-directory
   (concat (directory-file-name (expand-file-name my/snapshot-dir))
           "-private")))

(defun my/private-snapshots ()
  "Return the private zone copies, newest first."
  (let ((root (my/private-snapshot-dir)))
    (and (file-directory-p root)
         (sort (cl-remove-if-not
                #'file-directory-p
                (directory-files root t my/storage--snapshot-name-regexp))
               (lambda (a b) (string> a b))))))

(defun my/private-snapshot ()
  "Copy the private zone into a new dated folder; return it.
Return nil when the zone holds no files.  Copies beyond
`my/storage-snapshot-keep' are removed, oldest first."
  (interactive)
  (let ((dir (my/private--dir))
        (root (my/private-snapshot-dir)))
    (when (or (file-in-directory-p root dir) (file-in-directory-p dir root))
      (user-error "The private zone and its copies overlap: %s" root))
    (if (null (my/private--files))
        (progn
          (when (called-interactively-p 'interactive)
            (message "org-seq: the private zone is empty; nothing to copy"))
          nil)
      (let* ((name (format-time-string "%Y%m%d-%H%M%S"))
             (target (expand-file-name name root))
             (n 0))
        (while (file-exists-p target)
          (setq n (1+ n)
                target (expand-file-name (format "%s-%d" name n) root)))
        (with-file-modes #o700
          (make-directory root t)
          (my/storage-copy-missing dir target))
        (dolist (old (nthcdr (max 1 my/storage-snapshot-keep)
                             (my/private-snapshots)))
          (delete-directory old t))
        (when (called-interactively-p 'interactive)
          (message "org-seq: private zone copied to %s"
                   (abbreviate-file-name target)))
        (file-name-as-directory target)))))

(defun my/private-snapshot-maybe ()
  "Take the daily copy of the private zone when one is due.
Due means: none exists yet, or the newest is from an earlier day and a
file in the zone changed since."
  (when my/storage-snapshot-auto
    (condition-case err
        (let* ((latest (car (my/private-snapshots)))
               (since (and latest (file-attribute-modification-time
                                   (file-attributes latest)))))
          (when (or (null latest)
                    (and (not (string-prefix-p
                               (format-time-string "%Y%m%d")
                               (file-name-nondirectory latest)))
                         (cl-some
                          (lambda (file)
                            (time-less-p since
                                         (file-attribute-modification-time
                                          (file-attributes file))))
                          (my/private--files))))
            (my/private-snapshot)))
      (error (message "org-seq: private zone copy failed: %s"
                      (error-message-string err))))))

(unless noninteractive
  (add-hook 'emacs-startup-hook
            (lambda ()
              (run-with-idle-timer 5 nil #'my/private-snapshot-maybe))))

(provide 'init-private)
;;; init-private.el ends here
