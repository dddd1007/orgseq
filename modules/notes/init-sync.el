;;; init-sync.el --- Library storage and cloud sync -*- lexical-binding: t; -*-
;;
;; The library is a plain directory, `my/note-home', kept under the Emacs
;; directory so nothing has to be chosen or mounted.  Devices share it
;; through a cloud remote:
;;
;;   Engine    rclone bisync, a two-way file sync.  One engine covers
;;             WebDAV (Nextcloud, Jianguoyun, ...), OneDrive and Google
;;             Drive; account credentials stay in rclone's own config and
;;             never enter this repository or custom.el.
;;   Unit      Whole Org files.  When both sides changed the same file the
;;             newer one wins and the other is kept beside it with a
;;             ".conflict" suffix; `my/sync-conflicts' lists those copies.
;;   Index     The org-roam database is a local index and is not synced;
;;             it is refreshed after a sync brings changes in.
;;   Import    `my/storage-import' copies notes in from any folder (the old
;;             ~/NoteHQ/ included) and `my/storage-export' copies the
;;             library out.  Neither modifies its source, and no question
;;             is asked at startup.
;;   Snapshot  Dated copies of the library in `my/snapshot-dir', outside
;;             the Emacs directory: one a day when the library changed,
;;             and before imports and full comparisons.  `my/storage-restore'
;;             goes back to the full state of one of them.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │ Section 1  Device-local state                                    │
;; │ Section 2  Import, export and snapshots                          │
;; │ Section 3  rclone invocation                                     │
;; │ Section 4  Sync commands                                         │
;; │ Section 5  Remote setup                                          │
;; │ Section 6  Automatic sync                                        │
;; └─────────────────────────────────────────────────────────────────┘

;; Requires: init-org (my/note-home, my/note-home-legacy, my/snapshot-dir)
(defvar my/note-home)
(defvar my/note-home-legacy)
(defvar my/snapshot-dir)
(defvar my/roam-dir)
(defvar my/orgseq-dir)
(defvar my/library-dir)
(defvar my/sync-remote)

(require 'cl-lib)
(require 'subr-x)

(declare-function org-mem-reset "org-mem" (&optional takeover msg called-interactively))
(declare-function org-roam-db-sync "org-roam-db" (&optional force))
(declare-function my/node-types-reload "init-nodes" ())

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Device-local state
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; What this device has done (first sync with a remote, the import notice)
;; must not travel with the library, so it lives in the Emacs directory.

(defcustom my/sync-state-file
  (expand-file-name ".cache/sync-state.eld" user-emacs-directory)
  "File recording this device's sync and import state."
  :type 'file
  :group 'org-seq)

(defun my/sync--state ()
  "Return the device-local state plist."
  (when (file-readable-p my/sync-state-file)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents my/sync-state-file)
        (read (current-buffer))))))

(defun my/sync--state-put (&rest changes)
  "Merge plist CHANGES into the device-local state file."
  (let ((state (my/sync--state)))
    (while changes
      (setq state (plist-put state (pop changes) (pop changes))))
    (make-directory (file-name-directory my/sync-state-file) t)
    (with-temp-file my/sync-state-file
      (let ((print-length nil) (print-level nil))
        (prin1 state (current-buffer))))
    state))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Import, export and snapshots
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; The library has one fixed place.  Notes enter it by import, leave it
;; by export, and are protected on this device by dated snapshots kept
;; outside the Emacs directory.  None of these ever modifies its source.

(defconst my/storage--skip-regexp
  "\\`org-roam\\.db\\|\\.elc\\'\\|\\`\\.#\\|~\\'"
  "File names never copied or synced: local index, bytecode, lock and backup files.")

(defun my/storage-copy-missing (source target)
  "Copy files under SOURCE that do not exist under TARGET.
Existing files in TARGET are never overwritten and SOURCE is never
modified.  Return the number of files copied."
  (let ((count 0))
    (make-directory target t)
    (dolist (entry (directory-files source nil directory-files-no-dot-files-regexp))
      (let ((from (expand-file-name entry source))
            (to (expand-file-name entry target)))
        (cond
         ((string-match-p my/storage--skip-regexp entry))
         ((equal entry ".git"))
         ((file-symlink-p from))
         ((file-directory-p from)
          (cl-incf count (my/storage-copy-missing from to)))
         ((not (file-exists-p to))
          (copy-file from to nil t)
          (cl-incf count)))))
    count))

(defun my/storage--dir (dir)
  "Return DIR as an absolute directory name."
  (file-name-as-directory (expand-file-name dir)))

(defun my/storage--files (dir)
  "Return the files under DIR that belong to a library copy."
  (when (file-directory-p dir)
    (cl-remove-if
     (lambda (file)
       (or (file-symlink-p file)
           (string-match-p my/storage--skip-regexp
                           (file-name-nondirectory file))))
     (directory-files-recursively
      dir "" nil
      (lambda (sub) (not (equal (file-name-nondirectory sub) ".git")))))))

;; -- Snapshots --

(defcustom my/storage-snapshot-keep 10
  "Number of library snapshots kept in `my/snapshot-dir'; older ones are removed."
  :type 'integer
  :group 'org-seq)

(defcustom my/storage-snapshot-auto t
  "Non-nil takes one snapshot a day, on a day when the library has changed.
A snapshot is also taken before an import and before a sync that
compares both sides in full, whatever this is set to."
  :type 'boolean
  :group 'org-seq)

(defconst my/storage--snapshot-name-regexp
  "\\`[0-9]\\{8\\}-[0-9]\\{6\\}\\(-[0-9]+\\)?\\'"
  "Names of snapshot directories; nothing else in `my/snapshot-dir' is touched.")

(defun my/storage-snapshots ()
  "Return the snapshot directories, newest first."
  (when (file-directory-p my/snapshot-dir)
    (sort (cl-remove-if-not
           #'file-directory-p
           (directory-files my/snapshot-dir t my/storage--snapshot-name-regexp))
          (lambda (a b) (string> a b)))))

(defun my/storage--prune-snapshots (&optional protect)
  "Remove snapshots beyond `my/storage-snapshot-keep'.
PROTECT is a list of snapshot directories that are kept regardless."
  (let ((protect (mapcar #'my/storage--dir (delq nil protect))))
    (dolist (old (nthcdr (max 1 my/storage-snapshot-keep) (my/storage-snapshots)))
      (unless (member (my/storage--dir old) protect)
        (delete-directory old t)))))

(defun my/storage--check-overlap ()
  "Signal a user error when the snapshot directory and the library overlap."
  (let ((home (my/storage--dir my/note-home))
        (root (my/storage--dir my/snapshot-dir)))
    (when (or (file-in-directory-p root home) (file-in-directory-p home root))
      (user-error "Snapshot directory %s overlaps the library" root))))

(defun my/storage-snapshot ()
  "Copy the library into a new dated folder under `my/snapshot-dir'.
Return the folder, or nil when the library holds no files yet."
  (interactive)
  (let ((home (my/storage--dir my/note-home))
        (root (my/storage--dir my/snapshot-dir)))
    (my/storage--check-overlap)
    (if (null (my/storage--files home))
        (progn
          (when (called-interactively-p 'interactive)
            (message "org-seq: the library is empty; nothing to snapshot"))
          nil)
      (let* ((name (format-time-string "%Y%m%d-%H%M%S"))
             (target (expand-file-name name root))
             (n 0))
        (while (file-exists-p target)
          (setq n (1+ n)
                target (expand-file-name (format "%s-%d" name n) root)))
        (my/sync--save-note-buffers)
        (let ((count (my/storage-copy-missing home target)))
          (my/storage--prune-snapshots)
          (when (called-interactively-p 'interactive)
            (message "org-seq: snapshot of %d files in %s"
                     count (abbreviate-file-name target))))
        (file-name-as-directory target)))))

(defun my/storage--changed-since-p (time)
  "Return non-nil when a library file was modified after TIME."
  (cl-some (lambda (file)
             (time-less-p time (file-attribute-modification-time
                                (file-attributes file))))
           (my/storage--files my/note-home)))

(defun my/storage-snapshot-maybe ()
  "Take the daily snapshot when one is due.
Due means: none exists yet, or the newest is from an earlier day and
the library has changed since it was taken."
  (when my/storage-snapshot-auto
    (condition-case err
        (let ((latest (car (my/storage-snapshots))))
          (when (or (null latest)
                    (and (not (string-prefix-p
                               (format-time-string "%Y%m%d")
                               (file-name-nondirectory latest)))
                         (my/storage--changed-since-p
                          (file-attribute-modification-time
                           (file-attributes latest)))))
            (my/storage-snapshot)))
      (error (message "org-seq: snapshot failed: %s"
                      (error-message-string err))))))

(defun my/storage-browse-snapshots ()
  "Open the snapshot directory.
A snapshot is a plain copy of the library; `my/storage-restore' returns
the library to one and `my/storage-import' copies missing files back
from one."
  (interactive)
  (if (file-directory-p my/snapshot-dir)
      (dired my/snapshot-dir)
    (message "org-seq: no snapshots yet in %s"
             (abbreviate-file-name my/snapshot-dir))))

;; -- Import and export --

(defun my/storage--legacy-dir ()
  "Return the legacy library directory when it exists and is not the library."
  (let ((legacy (my/storage--dir my/note-home-legacy)))
    (and (file-directory-p legacy)
         (not (file-equal-p legacy my/note-home))
         legacy)))

(defun my/storage--legacy-pending-p ()
  "Return non-nil when the legacy library exists and was never imported."
  (and (my/storage--legacy-dir)
       (not (eq (plist-get (my/sync--state) :legacy-import) 'done))))

(defun my/storage--library-shaped-p (dir)
  "Return non-nil when DIR is laid out like an org-seq library."
  (cl-some (lambda (layer)
             (file-directory-p
              (expand-file-name
               (file-name-nondirectory (directory-file-name layer)) dir)))
           (list my/roam-dir my/orgseq-dir)))

(defun my/storage-import (dir)
  "Copy notes from folder DIR into the library.
A folder laid out like an org-seq library (it has the Roam layer or
.orgseq/) is merged layer by layer.  Any other folder is copied as one
subfolder of the reference layer (`my/library-dir').  Only files missing
from the library are copied, nothing is overwritten, and DIR is never
modified.  A snapshot of the library is taken first.  Return the number
of files copied."
  (interactive
   (list (read-directory-name "Import notes from folder: "
                              (or (my/storage--legacy-dir) "~/") nil t)))
  (let ((source (my/storage--dir dir))
        (home (my/storage--dir my/note-home)))
    (unless (file-directory-p source)
      (user-error "No such folder: %s" source))
    (when (or (file-in-directory-p source home) (file-in-directory-p home source))
      (user-error "%s overlaps the library; choose a folder outside it" source))
    (my/storage-snapshot)
    (let* ((target (if (my/storage--library-shaped-p source)
                       home
                     (expand-file-name
                      (file-name-nondirectory (directory-file-name source))
                      my/library-dir)))
           (count (my/storage-copy-missing source target)))
      (when (and (my/storage--legacy-dir)
                 (file-equal-p source (my/storage--legacy-dir)))
        (my/sync--state-put :legacy-import 'done))
      (my/sync--refresh-index)
      (message "org-seq: copied %d files from %s to %s (the source is untouched)"
               count (abbreviate-file-name source) (abbreviate-file-name target))
      count)))

(defun my/storage-export (dir)
  "Copy the whole library into a new dated folder inside DIR.
Return that folder.  The library itself is not changed."
  (interactive (list (read-directory-name "Export the library into folder: " "~/")))
  (let* ((home (my/storage--dir my/note-home))
         (parent (my/storage--dir dir))
         (target (expand-file-name
                  (format-time-string "org-seq-notes-%Y%m%d-%H%M%S") parent)))
    (when (file-in-directory-p parent home)
      (user-error "Choose a folder outside the library"))
    (when (file-exists-p target)
      (user-error "%s already exists" target))
    (my/sync--save-note-buffers)
    (let ((count (my/storage-copy-missing home target)))
      (message "org-seq: exported %d files to %s"
               count (abbreviate-file-name target)))
    (file-name-as-directory target)))

;; -- Restore --

(defun my/storage--snapshot-label (snapshot)
  "Return a one-line description of SNAPSHOT: name, date and file count."
  (let ((name (file-name-nondirectory (directory-file-name snapshot))))
    (format "%s  %s  %d files"
            name
            (if (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)" name)
                (format "%s-%s-%s %s:%s:%s"
                        (match-string 1 name) (match-string 2 name)
                        (match-string 3 name) (match-string 4 name)
                        (match-string 5 name) (match-string 6 name))
              "")
            (length (my/storage--files snapshot)))))

(defun my/storage--resolve-snapshot (snapshot)
  "Return the entry of `my/storage-snapshots' that SNAPSHOT names.
SNAPSHOT is a snapshot directory or its bare name such as
\"20261112-191216\".  Anything else is refused."
  (let* ((text (and (stringp snapshot) (directory-file-name snapshot)))
         (bare (and text (not (file-name-directory text))))
         (found (and text
                     (cl-find-if
                      (lambda (entry)
                        (if bare
                            (equal (file-name-nondirectory entry) text)
                          (file-equal-p entry text)))
                      (my/storage-snapshots)))))
    (or found (user-error "%s is not one of the snapshots in %s"
                          snapshot (abbreviate-file-name my/snapshot-dir)))))

(defun my/storage-restore-plan (snapshot)
  "Return a plist describing what restoring SNAPSHOT would do.
:snapshot is the snapshot directory, :copy the relative names of the
files that are written, :delete those removed from the library because
the snapshot does not have them.  Nothing is changed."
  (let* ((snap (my/storage--dir (my/storage--resolve-snapshot snapshot)))
         (home (my/storage--dir my/note-home))
         (wanted (make-hash-table :test 'equal))
         copy delete)
    (dolist (file (my/storage--files snap))
      (let ((rel (file-relative-name file snap)))
        (puthash rel t wanted)
        (push rel copy)))
    (dolist (file (my/storage--files home))
      (let ((rel (file-relative-name file home)))
        (unless (gethash rel wanted)
          (push rel delete))))
    (list :snapshot snap :copy (nreverse copy) :delete (nreverse delete))))

(defun my/storage--read-restore-target ()
  "Ask for a snapshot and confirm the restore; return the snapshot."
  (let* ((snapshots (or (my/storage-snapshots)
                        (user-error "There are no snapshots in %s"
                                    (abbreviate-file-name my/snapshot-dir))))
         (labels (mapcar (lambda (dir) (cons (my/storage--snapshot-label dir) dir))
                         snapshots))
         (choice (completing-read
                  "Restore the library to snapshot: "
                  (lambda (string predicate action)
                    (if (eq action 'metadata)
                        '(metadata (display-sort-function . identity)
                                   (cycle-sort-function . identity))
                      (complete-with-action action (mapcar #'car labels)
                                            string predicate)))
                  nil t))
         (snapshot (or (cdr (assoc choice labels))
                       (user-error "No snapshot chosen")))
         (plan (my/storage-restore-plan snapshot)))
    (unless (yes-or-no-p
             (format "Restore the library to snapshot %s?  %d files will be overwritten or recreated and %d library files the snapshot does not have will be deleted.  A snapshot of the current library is taken first so this can be undone.  Continue? "
                     (file-name-nondirectory (directory-file-name snapshot))
                     (length (plist-get plan :copy))
                     (length (plist-get plan :delete))))
      (user-error "Restore cancelled"))
    snapshot))

(defun my/storage--remove-empty-parents (file home)
  "Remove the directories above FILE that are empty, stopping at HOME."
  (let ((dir (file-name-directory file)))
    (while (and dir
                (not (file-equal-p dir home))
                (file-in-directory-p dir home)
                (file-directory-p dir)
                (null (directory-files dir nil directory-files-no-dot-files-regexp)))
      (delete-directory dir)
      (setq dir (file-name-directory (directory-file-name dir))))))

(defun my/storage--restore-buffers (home)
  "Return an alist of (BUFFER . FILE) for buffers visiting files under HOME."
  (delq nil
        (mapcar (lambda (buffer)
                  (let ((file (buffer-local-value 'buffer-file-name buffer)))
                    (and file (file-in-directory-p file home)
                         (cons buffer file))))
                (buffer-list))))

(defun my/storage--refresh-buffers (visiting)
  "Revert or report the buffers in VISITING after a restore.
Unmodified buffers whose file changed are reverted; buffers whose file
was deleted are left alone and named in a message."
  (dolist (entry visiting)
    (let ((buffer (car entry)) (file (cdr entry)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (cond
           ((not (file-exists-p file))
            (message "org-seq: %s was deleted by the restore; its buffer is kept"
                     (abbreviate-file-name file)))
           ((buffer-modified-p)
            (message "org-seq: buffer %s has unsaved changes and was not reverted"
                     (buffer-name)))
           ((not (verify-visited-file-modtime buffer))
            (revert-buffer t t t))))))))

(defun my/storage-restore (snapshot)
  "Make the library equal to SNAPSHOT, a folder of `my/storage-snapshots'.
Interactively, choose the snapshot (newest first) and confirm.  From
Lisp, SNAPSHOT is the snapshot directory or its name such as
\"20261112-191216\"; anything else is refused.

The library is first copied into a new snapshot, and the restore stops
before changing anything when that fails.  Then every file of SNAPSHOT is
copied over the library, library files that SNAPSHOT lacks are deleted,
and directories left empty are removed.  Only files that snapshots cover
are touched: `org-roam.db', bytecode, lock and backup files, symbolic
links and `.git' are neither read nor changed.  Return a plist with
:restored, :deleted, :snapshot and :undo-snapshot."
  (interactive (list (my/storage--read-restore-target)))
  (my/storage--check-overlap)
  (let* ((source (my/storage--dir (my/storage--resolve-snapshot snapshot)))
         (home (my/storage--dir my/note-home))
         (restored 0) (deleted 0) undo visiting)
    (when (file-equal-p source home)
      (user-error "The snapshot is the library itself"))
    ;; A library directory that is gone altogether is the case a restore
    ;; matters most for; the containment checks below need it to exist.
    (make-directory home t)
    (my/sync--save-note-buffers)
    (let ((plan (my/storage-restore-plan source))
          (before (my/storage--files home)))
      ;; The undo snapshot comes first.  Pruning is switched off for it so
      ;; the snapshot being restored survives until it has been read.
      (setq undo (let ((my/storage-snapshot-keep most-positive-fixnum))
                   (my/storage-snapshot)))
      (when before
        (unless (and undo
                     (= (length (my/storage--files undo)) (length before)))
          (user-error "Could not snapshot the current library; nothing was changed")))
      (setq visiting (my/storage--restore-buffers home))
      (condition-case err
          (progn
            ;; Delete only regular files that the snapshot enumeration
            ;; also reports, and only inside the library.
            (dolist (rel (plist-get plan :delete))
              (let ((file (expand-file-name rel home)))
                (when (and (file-in-directory-p file home)
                           (file-regular-p file)
                           (not (file-symlink-p file)))
                  (delete-file file)
                  (cl-incf deleted)
                  (my/storage--remove-empty-parents file home))))
            ;; Written with the current time, not the snapshot's: sync
            ;; resolves a conflict by letting the newer file win, so a
            ;; restored file that kept its old time would be overwritten
            ;; by the remote copy at the next sync.
            (dolist (rel (plist-get plan :copy))
              (let ((from (expand-file-name rel source))
                    (to (expand-file-name rel home)))
                (unless (file-in-directory-p to home)
                  (error "Refusing to write outside the library: %s" to))
                (make-directory (file-name-directory to) t)
                (copy-file from to t nil)
                (cl-incf restored))))
        (error
         (my/storage--refresh-buffers visiting)
         (error "Restore stopped (%s); the library before it is in %s"
                (error-message-string err) (or undo "no snapshot (it was empty)")))))
    (my/storage--refresh-buffers visiting)
    (my/storage--prune-snapshots (list source undo))
    (my/sync--refresh-index)
    (when (fboundp 'my/index-sync)
      (my/index-sync 'check))
    (message "org-seq: restored %d files and deleted %d from the library; the state before is in %s%s"
             restored deleted (if undo (abbreviate-file-name undo) "no snapshot (it was empty)")
             (if my/sync-remote
                 ".  The next sync will carry this state, deletions included, to the remote; run M-x my/sync-preview first to see what it would change"
               ""))
    (list :restored restored :deleted deleted
          :snapshot (directory-file-name source)
          :undo-snapshot (and undo (directory-file-name undo)))))

;; -- Status --

(defun my/storage-info ()
  "Return a plist describing where the library is and how it is protected.
Read-only: creates no file or directory."
  (let* ((files (my/storage--files my/note-home))
         (snapshots (my/storage-snapshots)))
    (list :library (my/storage--dir my/note-home)
          :files (length files)
          :notes (cl-count-if (lambda (file) (string-suffix-p ".org" file)) files)
          :bytes (apply #'+ (mapcar (lambda (file)
                                      (or (file-attribute-size (file-attributes file)) 0))
                                    files))
          :sync (my/sync-status)
          :snapshot-dir (my/storage--dir my/snapshot-dir)
          :snapshots (length snapshots)
          :last-snapshot (and snapshots (file-name-nondirectory (car snapshots)))
          :legacy (and (my/storage--legacy-pending-p) (my/storage--legacy-dir)))))

(defun my/storage-status ()
  "Show where the library lives, its size, sync state and snapshots."
  (interactive)
  (let ((info (my/storage-info)))
    (with-current-buffer (get-buffer-create "*org-seq storage*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert
         (format "Library    %s\n" (abbreviate-file-name (plist-get info :library)))
         (format "Contents   %d Org files, %d files in all, %s\n"
                 (plist-get info :notes) (plist-get info :files)
                 (file-size-human-readable (plist-get info :bytes)))
         (format "Sync       %s\n" (plist-get info :sync))
         (format "Snapshots  %d in %s%s\n"
                 (plist-get info :snapshots)
                 (abbreviate-file-name (plist-get info :snapshot-dir))
                 (if (plist-get info :last-snapshot)
                     (format ", newest %s" (plist-get info :last-snapshot))
                   ""))
         (if (plist-get info :legacy)
             (format "Old library %s has not been imported (M-x my/storage-import)\n"
                     (abbreviate-file-name (plist-get info :legacy)))
           "")
         "\nCommands   my/storage-import   my/storage-export   my/storage-snapshot\n"
         "           my/storage-restore  my/sync-setup       my/sync-now\n"
         "           my/storage-browse-snapshots\n"))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))
    info))

(defun my/storage--startup ()
  "Run the storage housekeeping of an interactive session.
Never asks a question: an unimported legacy library is mentioned once
in the echo area and stays visible in `my/storage-status'."
  (when (and (my/storage--legacy-pending-p)
             (not (plist-get (my/sync--state) :legacy-import)))
    (my/sync--state-put :legacy-import 'noticed)
    (message "org-seq: notes live in %s; M-x my/storage-import copies %s in"
             (abbreviate-file-name my/note-home)
             (abbreviate-file-name (my/storage--legacy-dir))))
  (my/storage-snapshot-maybe))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: rclone invocation
;; ═══════════════════════════════════════════════════════════════════════════

(defcustom my/sync-rclone-program "rclone"
  "Name or path of the rclone executable."
  :type 'string
  :group 'org-seq)

(defcustom my/sync-remote nil
  "Where the library syncs to, as an rclone path such as \"onedrive:org-seq\".
Nil means sync is off.  Set it with `my/sync-setup'; the remote's
credentials are stored by rclone, not here."
  :type '(choice (const :tag "Sync off" nil) (string :tag "rclone path"))
  :group 'org-seq)

(defcustom my/sync-filters
  '("- org-roam.db*"
    "- *.elc"
    "- .git/**"
    "- .#*"
    "- *~"
    "- .DS_Store"
    "- Thumbs.db"
    "- .obsidian/workspace*")
  "rclone filter rules for the library; excluded files stay on this device.
Changing the rules makes the next sync a full comparison of both sides."
  :type '(repeat string)
  :group 'org-seq)

(defconst my/sync--buffer "*org-seq sync*"
  "Buffer holding the output of sync runs.")

(defvar my/sync--process nil
  "The running sync process, or nil.")

(defun my/sync--rclone ()
  "Return the rclone executable or signal a user error."
  (or (executable-find my/sync-rclone-program)
      (user-error "rclone not found; install it (pacman/apt/brew/winget install rclone)")))

(defun my/sync--filters-file ()
  "Write the filter rules to a device-local file and return its path."
  (let ((file (expand-file-name "sync-filters.txt"
                                (file-name-directory my/sync-state-file))))
    (make-directory (file-name-directory file) t)
    (let ((content (concat (string-join my/sync-filters "\n") "\n")))
      (unless (and (file-exists-p file)
                   (equal content (with-temp-buffer
                                    (insert-file-contents file)
                                    (buffer-string))))
        (with-temp-file file (insert content))))
    file))

(defun my/sync--local ()
  "Return the library directory as rclone expects it."
  (directory-file-name (expand-file-name my/note-home)))

(defun my/sync--needs-resync-p ()
  "Return non-nil when this device has no baseline for the current pair.
That is the first sync, or a changed remote, library path or filter set."
  (let ((state (my/sync--state)))
    (not (and (equal (plist-get state :remote) my/sync-remote)
              (equal (plist-get state :local) (my/sync--local))
              (equal (plist-get state :filters) my/sync-filters)))))

(defun my/sync--arguments (&optional resync dry-run)
  "Return the rclone arguments for one sync run.
RESYNC merges both sides without deleting anything (first run, or after
the baseline was lost); DRY-RUN only reports what would change."
  (append
   (list "bisync" (my/sync--local) my/sync-remote
         "--filters-file" (my/sync--filters-file)
         "--workdir" (expand-file-name "bisync/"
                                       (file-name-directory my/sync-state-file))
         "--create-empty-src-dirs"
         "--conflict-resolve" "newer"
         "--conflict-loser" "num"
         "--conflict-suffix" "conflict"
         "--resilient" "--recover"
         "--max-lock" "2m"
         "--color" "NEVER"
         "--verbose")
   (and resync (list "--resync" "--resync-mode" "newer"))
   (and dry-run (list "--dry-run"))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Sync commands
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/sync--save-note-buffers ()
  "Save modified buffers visiting files in the library."
  (let ((root (file-name-as-directory (expand-file-name my/note-home))))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and buffer-file-name (buffer-modified-p)
                   (file-in-directory-p buffer-file-name root))
          (save-buffer))))))

(defun my/sync--refresh-index ()
  "Bring the node index and the type registry in line with the files."
  (cond
   ((and (fboundp 'org-mem-reset) (bound-and-true-p org-mem-updater-mode))
    (org-mem-reset))
   ((featurep 'org-roam)
    (org-roam-db-sync)))
  (when (fboundp 'my/node-types-reload)
    (my/node-types-reload)))

(defun my/sync--output-changed-p (output)
  "Return non-nil when rclone OUTPUT reports copied or deleted files."
  (and (string-match-p
        "Copied (\\|Deleted\\|Renamed\\|Do queued \\|Queue copy\\|Queue delete"
        output)
       t))

(defun my/sync--finish (status output resync dry-run callback)
  "Handle the end of a sync run with exit STATUS and OUTPUT.
RESYNC and DRY-RUN describe the run; CALLBACK receives t or nil."
  (let ((ok (eq status 0)))
    (cond
     ((and ok dry-run)
      (message "org-seq sync: preview finished; see %s" my/sync--buffer))
     (ok
      (my/sync--state-put :remote my/sync-remote
                          :local (my/sync--local)
                          :filters my/sync-filters
                          :last-success (format-time-string "%F %T"))
      (when (or resync (my/sync--output-changed-p output))
        (my/sync--refresh-index))
      (let ((conflicts (my/sync-conflict-files)))
        (message "org-seq sync: done%s"
                 (if conflicts
                     (format "; %d conflict copies, see M-x my/sync-conflicts"
                             (length conflicts))
                   ""))))
     ((string-match-p "must run --resync\\|Must run --resync\\|--resync to recover"
                      output)
      (my/sync--state-put :remote nil)
      (message "org-seq sync: baseline lost; the next sync compares both sides in full"))
     (t
      (message "org-seq sync: failed (exit %s); see %s" status my/sync--buffer)))
    (when callback (funcall callback ok))))

(defun my/sync-run (&optional dry-run callback synchronous)
  "Sync the library with `my/sync-remote'.
DRY-RUN only reports what would change.  CALLBACK, when non-nil, is
called with t on success and nil on failure.  SYNCHRONOUS waits for the
run to finish and returns non-nil on success (command line and MCP use)."
  (unless my/sync-remote
    (user-error "Sync is not set up; run M-x my/sync-setup"))
  (when (process-live-p my/sync--process)
    (user-error "A sync is already running; see %s" my/sync--buffer))
  (let* ((program (my/sync--rclone))
         (resync (my/sync--needs-resync-p))
         (arguments (my/sync--arguments resync dry-run))
         (buffer (get-buffer-create my/sync--buffer)))
    (make-directory my/note-home t)
    (my/sync--save-note-buffers)
    ;; A full comparison merges two sides that share no baseline; keep a
    ;; local copy of the library as it was before the merge.
    (when (and resync (not dry-run))
      (my/storage-snapshot))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "\n== %s  %s%s%s\n"
                        (format-time-string "%F %T") my/sync-remote
                        (if resync "  (full comparison)" "")
                        (if dry-run "  (preview)" "")))))
    (if synchronous
        (let* ((start (with-current-buffer buffer (point-max)))
               (status (with-current-buffer buffer
                         (let ((inhibit-read-only t))
                           (goto-char (point-max))
                           (apply #'call-process program nil t nil arguments))))
               (output (with-current-buffer buffer
                         (buffer-substring-no-properties start (point-max)))))
          (my/sync--finish status output resync dry-run callback)
          (eq status 0))
      (message "org-seq sync: started")
      (let ((start (with-current-buffer buffer (point-max))))
        (setq my/sync--process
              (make-process
               :name "org-seq-sync"
               :buffer buffer
               :command (cons program arguments)
               :noquery t
               :sentinel
               (lambda (process _event)
                 (unless (process-live-p process)
                   (setq my/sync--process nil)
                   (my/sync--finish
                    (process-exit-status process)
                    (if (buffer-live-p buffer)
                        (with-current-buffer buffer
                          (buffer-substring-no-properties start (point-max)))
                      "")
                    resync dry-run callback)))))))))

(defun my/sync-now ()
  "Sync the library with the configured remote now."
  (interactive)
  (my/sync-run))

(defun my/sync-preview ()
  "Show what a sync would change without changing anything."
  (interactive)
  (my/sync-run t (lambda (_ok) (display-buffer my/sync--buffer))))

(defun my/sync-log ()
  "Show the output of sync runs."
  (interactive)
  (display-buffer (get-buffer-create my/sync--buffer)))

(defun my/sync-reset ()
  "Forget this device's sync baseline.
The next sync compares both sides in full and merges them; nothing is
deleted on either side."
  (interactive)
  (my/sync--state-put :remote nil)
  (message "org-seq sync: the next sync will compare both sides in full"))

(defun my/sync-conflict-files ()
  "Return files in the library left behind by sync conflicts."
  (when (file-directory-p my/note-home)
    (directory-files-recursively my/note-home "\\.conflict[0-9]*\\'")))

(defun my/sync-conflicts ()
  "List conflict copies; each sits beside the version that won.
Compare the two (for example with `ediff-files'), keep what is needed,
and delete the conflict copy."
  (interactive)
  (let ((files (my/sync-conflict-files)))
    (if (null files)
        (message "org-seq sync: no conflict copies")
      (with-current-buffer (get-buffer-create "*org-seq sync conflicts*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Conflict copies (RET opens; the file without the suffix won):\n\n")
          (dolist (file files)
            (insert-text-button (abbreviate-file-name file)
                                'action (lambda (_) (find-file file))
                                'follow-link t)
            (insert "\n")))
        (special-mode)
        (goto-char (point-min))
        (pop-to-buffer (current-buffer))))))

(defun my/sync-status ()
  "Return a one-line description of the sync setup, and show it."
  (interactive)
  (let* ((state (my/sync--state))
         (text (cond
                ((null my/sync-remote) "sync off (M-x my/sync-setup)")
                (t (format "remote %s, last success %s%s"
                           my/sync-remote
                           (or (plist-get state :last-success) "never")
                           (if (my/sync--needs-resync-p)
                               ", next run compares both sides in full"
                             ""))))))
    (when (called-interactively-p 'interactive)
      (message "org-seq sync: %s" text))
    text))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Remote setup
;; ═══════════════════════════════════════════════════════════════════════════

(defconst my/sync-providers
  '(("WebDAV (Nextcloud, Jianguoyun, ownCloud, ...)" . "webdav")
    ("OneDrive" . "onedrive")
    ("Google Drive" . "drive")
    ("A remote already configured in rclone" . nil))
  "Storage providers offered by `my/sync-setup', with their rclone type.")

(defun my/sync--remotes ()
  "Return the names of the remotes configured in rclone."
  (mapcar (lambda (line) (string-remove-suffix ":" line))
          (ignore-errors (process-lines (my/sync--rclone) "listremotes"))))

(defun my/sync--obscure (password)
  "Return PASSWORD in rclone's obscured form, read through standard input."
  (with-temp-buffer
    (insert password)
    (unless (eq 0 (call-process-region (point-min) (point-max)
                                       (my/sync--rclone) t t nil "obscure" "-"))
      (error "rclone could not encode the password"))
    (string-trim (buffer-string))))

(defun my/sync--create-remote (name type &rest options)
  "Create rclone remote NAME of TYPE with OPTIONS (\"key=value\" strings).
OAuth providers open a browser window for sign-in.  Return non-nil on
success."
  (let ((buffer (get-buffer-create "*org-seq sync setup*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)) (erase-buffer)))
    (display-buffer buffer)
    (message "org-seq sync: creating remote %s (finish sign-in in the browser if one opens)"
             name)
    (eq 0 (apply #'call-process (my/sync--rclone) nil buffer t
                 "config" "create" name type
                 (append options (list "--no-obscure"))))))

(defun my/sync-setup ()
  "Choose where the library syncs to and run the first sync.
Asks for a provider (WebDAV, OneDrive, Google Drive or an existing rclone
remote) and a folder on it.  Credentials are handed to rclone and stored
in its config file only."
  (interactive)
  (my/sync--rclone)
  (let* ((choice (completing-read "Sync the library with: "
                                  (mapcar #'car my/sync-providers) nil t))
         (type (cdr (assoc choice my/sync-providers)))
         (name
          (if (null type)
              (completing-read "rclone remote: "
                               (or (my/sync--remotes)
                                   (user-error "rclone has no remotes yet"))
                               nil t)
            (let ((name (read-string "Name for this remote: "
                                     (concat "orgseq-" type))))
              (when (and (member name (my/sync--remotes))
                         (not (y-or-n-p (format "Remote %s exists.  Reconfigure it? "
                                                name))))
                (user-error "Setup cancelled"))
              (unless
                  (pcase type
                    ("webdav"
                     (let* ((url (read-string "WebDAV URL: "))
                            (vendor (completing-read
                                     "Server kind: "
                                     '("other" "nextcloud" "owncloud" "sharepoint"
                                       "fastmail")
                                     nil t nil nil "other"))
                            (user (read-string "User: "))
                            (pass (read-passwd "Password or app password: ")))
                       (my/sync--create-remote
                        name type (concat "url=" url) (concat "vendor=" vendor)
                        (concat "user=" user)
                        (concat "pass=" (my/sync--obscure pass)))))
                    (_ (my/sync--create-remote name type)))
                (user-error "rclone could not create the remote; see *org-seq sync setup*"))
              name)))
         (folder (read-string "Folder on the remote: " "org-seq-notes"))
         (remote (format "%s:%s" name folder)))
    (customize-save-variable 'my/sync-remote remote)
    (message "org-seq sync: remote set to %s" remote)
    (when (y-or-n-p "Run the first sync now (merges both sides, deletes nothing)? ")
      (my/sync-run))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: Automatic sync
;; ═══════════════════════════════════════════════════════════════════════════

(defcustom my/sync-auto-interval 15
  "Minutes between automatic syncs while Emacs is running; nil disables.
A sync also runs shortly after startup.  Automatic runs wait until Emacs
has been idle for a few seconds and never overlap."
  :type '(choice (const :tag "Manual only" nil) (integer :tag "Minutes"))
  :group 'org-seq)

(defvar my/sync--timer nil
  "Timer driving automatic syncs.")

(defun my/sync--auto-run ()
  "Run an automatic sync when one is configured and none is running."
  (when (and my/sync-remote
             (not (process-live-p my/sync--process))
             (executable-find my/sync-rclone-program))
    (run-with-idle-timer
     5 nil
     (lambda ()
       (condition-case err
           (unless (process-live-p my/sync--process)
             (my/sync-run))
         (error (message "org-seq sync: %s" (error-message-string err))))))))

(defun my/sync-auto-enable ()
  "Start automatic syncs according to `my/sync-auto-interval'."
  (when (timerp my/sync--timer)
    (cancel-timer my/sync--timer))
  (setq my/sync--timer
        (and my/sync-auto-interval
             (run-with-timer 20 (* 60 my/sync-auto-interval)
                             #'my/sync--auto-run))))

(unless noninteractive
  (add-hook 'emacs-startup-hook
            (lambda ()
              (run-with-idle-timer 3 nil #'my/storage--startup)
              (my/sync-auto-enable))))

(provide 'init-sync)
;;; init-sync.el ends here
