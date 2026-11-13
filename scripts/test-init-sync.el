;;; test-init-sync.el --- Tests for library storage and sync -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar my/note-home)
(defvar my/note-home-legacy)
(defvar my/snapshot-dir)
(defvar my/inbox-dir)
(defvar my/orgseq-dir)
(defvar my/library-dir)
(defvar my/storage-snapshot-keep)
(defvar my/storage-snapshot-auto)
(defvar my/sync-remote)
(defvar my/ai-dir)
(defvar my/dashboards-dir)
(defvar my/sync-state-file)
(defvar my/sync-rclone-program)

(let ((dir (file-name-directory load-file-name)))
  (defconst my/test-sync--init-org
    (expand-file-name "../kernel/orgseq-paths.el" dir))
  (setq my/note-home "/nonexistent/" my/note-home-legacy "/nonexistent-legacy/"
        my/snapshot-dir "/nonexistent-snapshots/"
        my/inbox-dir "/nonexistent/00_Inbox/" my/orgseq-dir "/nonexistent/.orgseq/"
        my/library-dir "/nonexistent/30_Library/"
        my/ai-dir "/nonexistent/50_AI/"
        my/dashboards-dir "/nonexistent/00_Inbox/dashboards/")
  ;; The path definitions keep the values set above and add the layout
  ;; helpers the storage commands call.
  (load-file my/test-sync--init-org)
  (load-file (expand-file-name "../modules/notes/init-sync.el" dir)))

(defun my/test-sync--write (file text)
  "Write TEXT to FILE, creating parent directories."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text)))

(defun my/test-sync--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro my/test-sync--with-dirs (&rest body)
  "Run BODY with temporary library, remote and state locations bound.
Binds `root', `my/note-home' with its layer paths, `my/snapshot-dir',
`my/sync-remote' and `my/sync-state-file'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "org-seq-sync-" t)))
          (my/note-home (expand-file-name "library/" root))
          (my/inbox-dir (expand-file-name "00_Inbox/" my/note-home))
          (my/orgseq-dir (expand-file-name ".orgseq/" my/note-home))
          (my/library-dir (expand-file-name "30_Library/" my/note-home))
          (my/snapshot-dir (expand-file-name "snapshots/" root))
          (my/sync-remote (expand-file-name "remote" root))
          (my/sync-state-file (expand-file-name "state/sync-state.eld" root))
          (inhibit-message t))
     (unwind-protect
         (progn (make-directory my/note-home t)
                (make-directory my/sync-remote t)
                ,@body)
       (delete-directory root t))))

(ert-deftest my/note-home-defaults-under-emacs-directory ()
  "The library needs no chosen folder; ORG_SEQ_NOTE_HOME still overrides."
  (let ((source (my/test-sync--read my/test-sync--init-org)))
    (should (string-match-p
             "(expand-file-name \"notes/\" user-emacs-directory)" source))
    (should (string-match-p "ORG_SEQ_NOTE_HOME" source))))

(ert-deftest my/storage-import-copies-missing-files-only ()
  (my/test-sync--with-dirs
    (let ((my/note-home-legacy (expand-file-name "legacy/" root)))
      (my/test-sync--write (expand-file-name "00_Roam/a.org" my/note-home-legacy) "old a")
      (my/test-sync--write (expand-file-name "00_Roam/b.org" my/note-home-legacy) "old b")
      (my/test-sync--write (expand-file-name "00_Roam/org-roam.db" my/note-home-legacy) "db")
      (my/test-sync--write (expand-file-name ".git/config" my/note-home-legacy) "git")
      (my/test-sync--write (expand-file-name "00_Inbox/a.org" my/note-home) "new a")
      (should (my/storage--legacy-pending-p))
      (should (= 1 (my/storage-import my/note-home-legacy)))
      (should (equal "new a" (my/test-sync--read
                              (expand-file-name "00_Inbox/a.org" my/note-home))))
      (should (equal "old b" (my/test-sync--read
                              (expand-file-name "00_Inbox/b.org" my/note-home))))
      (should-not (file-exists-p (expand-file-name "00_Inbox/org-roam.db" my/note-home)))
      (should-not (file-exists-p (expand-file-name ".git" my/note-home)))
      ;; The legacy library is left exactly as it was.
      (should (equal "old a" (my/test-sync--read
                              (expand-file-name "00_Roam/a.org" my/note-home-legacy))))
      (should (eq 'done (plist-get (my/sync--state) :legacy-import)))
      (should-not (my/storage--legacy-pending-p))
      ;; The library as it was before the import is kept as a snapshot.
      (let ((snapshot (car (my/storage-snapshots))))
        (should snapshot)
        (should (equal "new a" (my/test-sync--read
                                (expand-file-name "00_Inbox/a.org" snapshot))))
        (should-not (file-exists-p (expand-file-name "00_Inbox/b.org" snapshot)))))))

(ert-deftest my/storage-import-files-a-plain-folder-under-the-reference-layer ()
  (my/test-sync--with-dirs
    (let ((plain (expand-file-name "papers/" root)))
      (my/test-sync--write (expand-file-name "x.org" plain) "x")
      (my/test-sync--write (expand-file-name "sub/y.md" plain) "y")
      (should (= 2 (my/storage-import plain)))
      (should (equal "x" (my/test-sync--read
                          (expand-file-name "papers/x.org" my/library-dir))))
      (should (equal "y" (my/test-sync--read
                          (expand-file-name "papers/sub/y.md" my/library-dir))))
      (should-not (file-exists-p (expand-file-name "x.org" my/note-home)))
      ;; Folders overlapping the library are refused.
      (should-error (my/storage-import my/inbox-dir) :type 'user-error)
      (should-error (my/storage-import root) :type 'user-error))))

(ert-deftest my/storage-startup-never-asks ()
  "An unimported legacy library is mentioned once and never prompted for."
  (my/test-sync--with-dirs
    (let ((my/note-home-legacy (expand-file-name "legacy/" root))
          (my/storage-snapshot-auto nil))
      (my/test-sync--write (expand-file-name "00_Roam/a.org" my/note-home-legacy) "a")
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (&rest _) (error "Startup must not ask")))
                ((symbol-function 'y-or-n-p)
                 (lambda (&rest _) (error "Startup must not ask"))))
        (my/storage--startup)
        (should (eq 'noticed (plist-get (my/sync--state) :legacy-import)))
        (my/storage--startup))
      (should-not (file-exists-p (expand-file-name "00_Inbox/a.org" my/note-home)))
      (should (my/storage--legacy-pending-p))
      (should (plist-get (my/storage-info) :legacy)))))

(ert-deftest my/storage-snapshots-are-dated-daily-and-pruned ()
  (my/test-sync--with-dirs
    (let ((my/storage-snapshot-keep 2)
          (my/storage-snapshot-auto t)
          (note (expand-file-name "00_Inbox/a.org" my/note-home)))
      ;; Nothing to copy yet.
      (should-not (my/storage-snapshot))
      (my/test-sync--write note "one")
      (my/test-sync--write (expand-file-name "00_Inbox/org-roam.db" my/note-home) "db")
      (let ((first (my/storage-snapshot)))
        (should (equal "one" (my/test-sync--read
                              (expand-file-name "00_Inbox/a.org" first))))
        (should-not (file-exists-p (expand-file-name "00_Inbox/org-roam.db" first)))
        ;; A snapshot from today is enough for today.
        (my/storage-snapshot-maybe)
        (should (= 1 (length (my/storage-snapshots))))
        ;; An older snapshot and a changed library make one due.
        (let ((old (expand-file-name "20200101-000000" my/snapshot-dir)))
          (rename-file (directory-file-name first) old)
          (set-file-times old (time-subtract nil 86400))
          (my/storage-snapshot-maybe)
          (should (= 2 (length (my/storage-snapshots))))
          ;; Only the newest `my/storage-snapshot-keep' survive.
          (my/storage-snapshot)
          (should (= 2 (length (my/storage-snapshots))))
          (should-not (file-exists-p old))))
      (let ((info (my/storage-info)))
        (should (= 1 (plist-get info :notes)))
        (should (= 1 (plist-get info :files)))
        (should (= 2 (plist-get info :snapshots)))))))

(ert-deftest my/storage-export-copies-the-library-out ()
  (my/test-sync--with-dirs
    (my/test-sync--write (expand-file-name "00_Inbox/a.org" my/note-home) "a")
    (let ((folder (my/storage-export (expand-file-name "out/" root))))
      (should (equal "a" (my/test-sync--read
                          (expand-file-name "00_Inbox/a.org" folder))))
      (should-error (my/storage-export my/inbox-dir) :type 'user-error))))

(ert-deftest my/sync-first-run-is-a-non-destructive-merge ()
  (my/test-sync--with-dirs
    (should (my/sync--needs-resync-p))
    (should (member "--resync" (my/sync--arguments t)))
    (should-not (member "--resync" (my/sync--arguments nil)))
    (should (member "--dry-run" (my/sync--arguments nil t)))
    (should-error (let ((my/sync-remote nil)) (my/sync-run)) :type 'user-error)))

(ert-deftest my/sync-round-trip-with-rclone ()
  "Two-way sync against a local directory standing in for the cloud."
  (skip-unless (executable-find my/sync-rclone-program))
  (my/test-sync--with-dirs
    (let ((local (lambda (name) (expand-file-name name my/note-home)))
          (remote (lambda (name) (expand-file-name name my/sync-remote))))
      (my/test-sync--write (funcall local "00_Inbox/mine.org") "mine")
      (my/test-sync--write (funcall local "00_Inbox/org-roam.db") "index")
      (my/test-sync--write (funcall remote "00_Inbox/theirs.org") "theirs")
      ;; First run: both sides are merged, nothing is deleted.
      (should (my/sync-run nil nil t))
      (should (equal "theirs" (my/test-sync--read (funcall local "00_Inbox/theirs.org"))))
      (should (equal "mine" (my/test-sync--read (funcall remote "00_Inbox/mine.org"))))
      (should-not (file-exists-p (funcall remote "00_Inbox/org-roam.db")))
      (should-not (my/sync--needs-resync-p))
      ;; Later runs carry edits, new files and deletions both ways.
      (my/test-sync--write (funcall local "00_Inbox/mine.org") "mine, edited")
      (my/test-sync--write (funcall remote "10_Outputs/new.org") "new")
      (delete-file (funcall remote "00_Inbox/theirs.org"))
      (should (my/sync-run nil nil t))
      (should (equal "mine, edited"
                     (my/test-sync--read (funcall remote "00_Inbox/mine.org"))))
      (should (equal "new" (my/test-sync--read (funcall local "10_Outputs/new.org"))))
      (should-not (file-exists-p (funcall local "00_Inbox/theirs.org")))
      (should (file-exists-p (funcall local "00_Inbox/org-roam.db")))
      ;; Both sides edit one file: the newer wins, the other is kept.
      (my/test-sync--write (funcall remote "00_Inbox/mine.org") "remote edit")
      (set-file-times (funcall remote "00_Inbox/mine.org")
                      (time-subtract nil 3600))
      (my/test-sync--write (funcall local "00_Inbox/mine.org") "local edit, newer")
      (should (my/sync-run nil nil t))
      (should (equal "local edit, newer"
                     (my/test-sync--read (funcall local "00_Inbox/mine.org"))))
      (should (equal "local edit, newer"
                     (my/test-sync--read (funcall remote "00_Inbox/mine.org"))))
      (let ((conflicts (my/sync-conflict-files)))
        (should (= 1 (length conflicts)))
        (should (equal "remote edit" (my/test-sync--read (car conflicts))))))))

;; -- Restore --

(defun my/test-sync--tree (dir)
  "Return an alist of (relative-name . contents) for the library files in DIR."
  (sort (mapcar (lambda (file)
                  (cons (file-relative-name file dir) (my/test-sync--read file)))
                (my/storage--files dir))
        (lambda (a b) (string< (car a) (car b)))))

(defun my/test-sync--seed-library ()
  "Create a small library and return its snapshot."
  (my/test-sync--write (expand-file-name "00_Inbox/a.org" my/note-home) "a one")
  (my/test-sync--write (expand-file-name "00_Inbox/b.org" my/note-home) "b one")
  (my/test-sync--write (expand-file-name "10_Outputs/deep/c.org" my/note-home) "c one")
  (my/test-sync--write (expand-file-name "00_Inbox/org-roam.db" my/note-home) "index")
  (my/test-sync--write (expand-file-name ".git/HEAD" my/note-home) "ref")
  (my/storage-snapshot))

(ert-deftest my/storage-restore-brings-back-the-snapshot-state ()
  (my/test-sync--with-dirs
    (let* ((snapshot (my/test-sync--seed-library))
           (expected (my/test-sync--tree snapshot))
           (result nil))
      (delete-file (expand-file-name "00_Inbox/a.org" my/note-home))
      (my/test-sync--write (expand-file-name "00_Inbox/b.org" my/note-home) "b edited")
      (my/test-sync--write (expand-file-name "00_Inbox/new.org" my/note-home) "new")
      (my/test-sync--write (expand-file-name "20_Practice/x/y.org" my/note-home) "y")
      (delete-file (expand-file-name "10_Outputs/deep/c.org" my/note-home))
      (my/test-sync--write (expand-file-name "00_Inbox/org-roam.db" my/note-home) "newer index")
      (my/test-sync--write (expand-file-name ".git/HEAD" my/note-home) "newer ref")
      (setq result (my/storage-restore (file-name-nondirectory
                                        (directory-file-name snapshot))))
      (should (equal expected (my/test-sync--tree my/note-home)))
      (should (= 2 (plist-get result :deleted)))
      (should (= 3 (plist-get result :restored)))
      ;; Directories left empty by the deletions are gone; others stay.
      (should-not (file-exists-p (expand-file-name "20_Practice" my/note-home)))
      (should (file-directory-p (expand-file-name "10_Outputs/deep" my/note-home)))
      ;; Files outside the snapshot scope are untouched.
      (should (equal "newer index"
                     (my/test-sync--read (expand-file-name "00_Inbox/org-roam.db"
                                                           my/note-home))))
      (should (equal "newer ref"
                     (my/test-sync--read (expand-file-name ".git/HEAD" my/note-home)))))))

(ert-deftest my/storage-restore-accepts-a-snapshot-path ()
  (my/test-sync--with-dirs
    (let ((snapshot (my/test-sync--seed-library)))
      (delete-file (expand-file-name "00_Inbox/a.org" my/note-home))
      (my/storage-restore snapshot)
      (should (equal "a one" (my/test-sync--read
                              (expand-file-name "00_Inbox/a.org" my/note-home)))))))

(ert-deftest my/storage-restore-gives-restored-files-fresh-mtimes ()
  (my/test-sync--with-dirs
    (let ((snapshot (my/test-sync--seed-library))
          (start (current-time)))
      (dolist (file (my/storage--files snapshot))
        (set-file-times file (time-subtract nil (* 30 86400))))
      (my/storage-restore snapshot)
      (dolist (file (my/storage--files my/note-home))
        (should-not (time-less-p (file-attribute-modification-time
                                  (file-attributes file))
                                 (time-subtract start 5)))))))

(ert-deftest my/storage-restore-can-be-undone ()
  (my/test-sync--with-dirs
    (let* ((snapshot (my/test-sync--seed-library))
           (name (file-name-nondirectory (directory-file-name snapshot))))
      (delete-file (expand-file-name "00_Inbox/a.org" my/note-home))
      (my/test-sync--write (expand-file-name "00_Inbox/b.org" my/note-home) "b edited")
      (my/test-sync--write (expand-file-name "00_Inbox/new.org" my/note-home) "new")
      (let ((before (my/test-sync--tree my/note-home))
            (result (my/storage-restore name)))
        (let ((undo (plist-get result :undo-snapshot)))
          (should undo)
          (should-not (equal name (file-name-nondirectory undo)))
          (should (member undo (mapcar #'directory-file-name (my/storage-snapshots))))
          (should (equal before (my/test-sync--tree undo)))
          (should-not (equal before (my/test-sync--tree my/note-home)))
          ;; Restoring the undo snapshot returns the earlier state.
          (my/storage-restore undo)
          (should (equal before (my/test-sync--tree my/note-home))))))))

(ert-deftest my/storage-restore-refuses-unknown-snapshots ()
  (my/test-sync--with-dirs
    (my/test-sync--seed-library)
    (let ((before (my/test-sync--tree my/note-home))
          (outside (expand-file-name "other/" root)))
      (my/test-sync--write (expand-file-name "00_Inbox/z.org" outside) "z")
      (dolist (bad (list "20000101-000000" "" "../library" outside
                         my/note-home my/snapshot-dir nil))
        (should-error (my/storage-restore bad) :type 'user-error))
      (should (equal before (my/test-sync--tree my/note-home)))
      (should (= 1 (length (my/storage-snapshots)))))))

(ert-deftest my/storage-restore-refuses-overlapping-snapshot-dir ()
  (my/test-sync--with-dirs
    (let ((snapshot (my/test-sync--seed-library)))
      (let ((my/snapshot-dir (expand-file-name "inside/" my/note-home)))
        (should-error (my/storage-restore snapshot) :type 'user-error)))))

(ert-deftest my/storage-restore-survives-a-small-keep-limit ()
  "The snapshot being restored and the undo snapshot outlive pruning."
  (my/test-sync--with-dirs
    (let* ((my/storage-snapshot-keep 1)
           (snapshot (my/test-sync--seed-library))
           (name (file-name-nondirectory (directory-file-name snapshot))))
      (delete-file (expand-file-name "00_Inbox/a.org" my/note-home))
      (let* ((result (my/storage-restore name))
             (undo (plist-get result :undo-snapshot)))
        (should (equal "a one" (my/test-sync--read
                                (expand-file-name "00_Inbox/a.org" my/note-home))))
        (should (file-directory-p undo))
        (should (file-directory-p snapshot))
        (should-not (file-exists-p (expand-file-name "00_Inbox/a.org" undo)))
        ;; The next ordinary snapshot prunes back to the limit.
        (my/storage-snapshot)
        (should (= 1 (length (my/storage-snapshots))))))))

(ert-deftest my/storage-restore-aborts-when-the-undo-snapshot-fails ()
  (my/test-sync--with-dirs
    (let ((snapshot (my/test-sync--seed-library)))
      (delete-file (expand-file-name "00_Inbox/a.org" my/note-home))
      (let ((before (my/test-sync--tree my/note-home)))
        (cl-letf (((symbol-function 'my/storage-snapshot) (lambda () nil)))
          (should-error (my/storage-restore snapshot) :type 'user-error))
        (should (equal before (my/test-sync--tree my/note-home)))))))

(ert-deftest my/storage-restore-reverts-and-reports-buffers ()
  (my/test-sync--with-dirs
    (let* ((snapshot (my/test-sync--seed-library))
           (a (expand-file-name "00_Inbox/a.org" my/note-home))
           (extra (expand-file-name "00_Inbox/extra.org" my/note-home))
           (messages nil))
      (my/test-sync--write extra "extra")
      (my/test-sync--write a "a edited")
      (let ((buffer-a (find-file-noselect a))
            (buffer-extra (find-file-noselect extra)))
        (unwind-protect
            (progn
              (with-current-buffer buffer-a
                (goto-char (point-max)) (insert " unsaved"))
              (cl-letf (((symbol-function 'message)
                         (lambda (fmt &rest args)
                           (push (apply #'format fmt args) messages))))
                (my/storage-restore snapshot))
              ;; Unsaved edits are saved before the restore, then reverted.
              (with-current-buffer buffer-a
                (should-not (buffer-modified-p))
                (should (equal "a one" (buffer-string))))
              (should (buffer-live-p buffer-extra))
              (should (cl-some (lambda (m) (string-match-p "extra.org was deleted" m))
                               messages)))
          (kill-buffer buffer-a)
          (kill-buffer buffer-extra))))))

(ert-deftest my/storage-restore-mentions-the-remote ()
  (my/test-sync--with-dirs
    (let ((snapshot (my/test-sync--seed-library))
          (messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (my/storage-restore snapshot)
        (should (cl-some (lambda (m) (string-match-p "my/sync-preview" m)) messages))
        (setq messages nil)
        (let ((my/sync-remote nil))
          (my/storage-restore snapshot))
        (should-not (cl-some (lambda (m) (string-match-p "my/sync-preview" m))
                             messages))))))

(ert-deftest my/storage-restore-recreates-a-missing-library ()
  "Losing the whole library directory is what a restore is for."
  (my/test-sync--with-dirs
    (my/test-sync--write (expand-file-name "00_Inbox/a.org" my/note-home) "a")
    (let ((snapshot (my/storage-snapshot)))
      (delete-directory my/note-home t)
      (let ((result (my/storage-restore snapshot)))
        (should (= 1 (plist-get result :restored)))
        (should (equal "a" (my/test-sync--read
                            (expand-file-name "00_Inbox/a.org" my/note-home))))))))

(ert-deftest my/storage-import-maps-an-old-layout-onto-the-current-one ()
  (my/test-sync--with-dirs
    (let ((my/note-home-legacy (expand-file-name "old/" root))
          (my/ai-dir (expand-file-name "50_AI/" my/note-home)))
      (make-directory my/inbox-dir t)
      (my/test-sync--write (expand-file-name "00_Roam/daily/d.org" my/note-home-legacy) "d")
      (my/test-sync--write (expand-file-name "00_Roam/purpose.org" my/note-home-legacy) "p")
      (my/test-sync--write (expand-file-name "10_Outputs/o.org" my/note-home-legacy) "o")
      (should (= 3 (my/storage-import my/note-home-legacy)))
      (should (file-exists-p (expand-file-name "daily/d.org" my/inbox-dir)))
      (should (file-exists-p (expand-file-name "purpose.org" my/ai-dir)))
      (should (file-exists-p (expand-file-name "10_Outputs/o.org" my/note-home)))
      (should-not (file-exists-p (expand-file-name "00_Roam" my/note-home))))))

(ert-deftest my/storage-migrate-layout-renames-the-inbox-and-keeps-a-snapshot ()
  (my/test-sync--with-dirs
    (let* ((my/sync-remote nil)
           (my/inbox-dir (expand-file-name "00_Roam/" my/note-home))
           (my/dashboards-dir (expand-file-name "dashboards/" my/inbox-dir))
           (my/ai-dir (expand-file-name "50_AI/" my/note-home)))
      (my/test-sync--write (expand-file-name "daily/d.org" my/inbox-dir) "d")
      (my/test-sync--write (expand-file-name "capture/c.org" my/inbox-dir) "c")
      (my/test-sync--write (expand-file-name "schema.org" my/inbox-dir) "s")
      (my/test-sync--write (expand-file-name "10_Outputs/o.org" my/note-home) "o")
      (should (my/storage--legacy-layout-p))
      (should (equal (my/storage-layout-plan)
                     '(("00_Roam/capture/c.org" . "00_Inbox/capture/c.org")
                       ("00_Roam/daily/d.org" . "00_Inbox/daily/d.org")
                       ("00_Roam/schema.org" . "50_AI/schema.org"))))
      (let ((result (my/storage-migrate-layout)))
        (should (= 3 (plist-get result :moved)))
        (should (= 0 (plist-get result :skipped)))
        (should (file-exists-p (expand-file-name
                                "00_Roam/daily/d.org"
                                (plist-get result :snapshot)))))
      (should-not (file-exists-p (expand-file-name "00_Roam" my/note-home)))
      (should (equal (my/test-sync--read
                      (expand-file-name "00_Inbox/daily/d.org" my/note-home))
                     "d"))
      (should (file-exists-p (expand-file-name "50_AI/schema.org" my/note-home)))
      (should (file-exists-p (expand-file-name "10_Outputs/o.org" my/note-home)))
      (should (equal (file-name-as-directory my/inbox-dir)
                     (expand-file-name "00_Inbox/" my/note-home)))
      (should (equal my/dashboards-dir
                     (expand-file-name "00_Inbox/dashboards/" my/note-home)))
      (should-not (my/storage-layout-plan))
      (should-not (my/storage-migrate-layout)))))

(ert-deftest my/storage-migrate-layout-never-overwrites ()
  (my/test-sync--with-dirs
    (let* ((my/sync-remote nil)
           (my/inbox-dir (expand-file-name "00_Roam/" my/note-home))
           (my/ai-dir (expand-file-name "50_AI/" my/note-home)))
      (my/test-sync--write (expand-file-name "a.org" my/inbox-dir) "old")
      (my/test-sync--write (expand-file-name "00_Inbox/a.org" my/note-home) "new")
      (let ((result (my/storage-migrate-layout)))
        (should (= 0 (plist-get result :moved)))
        (should (= 1 (plist-get result :skipped))))
      (should (equal (my/test-sync--read
                      (expand-file-name "00_Inbox/a.org" my/note-home))
                     "new"))
      (should (equal (my/test-sync--read
                      (expand-file-name "00_Roam/a.org" my/note-home))
                     "old")))))

;;; test-init-sync.el ends here
