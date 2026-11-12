;;; test-init-sync.el --- Tests for library storage and sync -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar my/note-home)
(defvar my/note-home-legacy)
(defvar my/snapshot-dir)
(defvar my/roam-dir)
(defvar my/orgseq-dir)
(defvar my/library-dir)
(defvar my/storage-snapshot-keep)
(defvar my/storage-snapshot-auto)
(defvar my/sync-remote)
(defvar my/sync-state-file)
(defvar my/sync-rclone-program)

(let ((dir (file-name-directory load-file-name)))
  (defconst my/test-sync--init-org
    (expand-file-name "../kernel/orgseq-paths.el" dir))
  (setq my/note-home "/nonexistent/" my/note-home-legacy "/nonexistent-legacy/"
        my/snapshot-dir "/nonexistent-snapshots/"
        my/roam-dir "/nonexistent/00_Roam/" my/orgseq-dir "/nonexistent/.orgseq/"
        my/library-dir "/nonexistent/30_Library/")
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
          (my/roam-dir (expand-file-name "00_Roam/" my/note-home))
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
      (my/test-sync--write (expand-file-name "00_Roam/a.org" my/note-home) "new a")
      (should (my/storage--legacy-pending-p))
      (should (= 1 (my/storage-import my/note-home-legacy)))
      (should (equal "new a" (my/test-sync--read
                              (expand-file-name "00_Roam/a.org" my/note-home))))
      (should (equal "old b" (my/test-sync--read
                              (expand-file-name "00_Roam/b.org" my/note-home))))
      (should-not (file-exists-p (expand-file-name "00_Roam/org-roam.db" my/note-home)))
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
                                (expand-file-name "00_Roam/a.org" snapshot))))
        (should-not (file-exists-p (expand-file-name "00_Roam/b.org" snapshot)))))))

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
      (should-error (my/storage-import my/roam-dir) :type 'user-error)
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
      (should-not (file-exists-p (expand-file-name "00_Roam/a.org" my/note-home)))
      (should (my/storage--legacy-pending-p))
      (should (plist-get (my/storage-info) :legacy)))))

(ert-deftest my/storage-snapshots-are-dated-daily-and-pruned ()
  (my/test-sync--with-dirs
    (let ((my/storage-snapshot-keep 2)
          (my/storage-snapshot-auto t)
          (note (expand-file-name "00_Roam/a.org" my/note-home)))
      ;; Nothing to copy yet.
      (should-not (my/storage-snapshot))
      (my/test-sync--write note "one")
      (my/test-sync--write (expand-file-name "00_Roam/org-roam.db" my/note-home) "db")
      (let ((first (my/storage-snapshot)))
        (should (equal "one" (my/test-sync--read
                              (expand-file-name "00_Roam/a.org" first))))
        (should-not (file-exists-p (expand-file-name "00_Roam/org-roam.db" first)))
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
    (my/test-sync--write (expand-file-name "00_Roam/a.org" my/note-home) "a")
    (let ((folder (my/storage-export (expand-file-name "out/" root))))
      (should (equal "a" (my/test-sync--read
                          (expand-file-name "00_Roam/a.org" folder))))
      (should-error (my/storage-export my/roam-dir) :type 'user-error))))

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
      (my/test-sync--write (funcall local "00_Roam/mine.org") "mine")
      (my/test-sync--write (funcall local "00_Roam/org-roam.db") "index")
      (my/test-sync--write (funcall remote "00_Roam/theirs.org") "theirs")
      ;; First run: both sides are merged, nothing is deleted.
      (should (my/sync-run nil nil t))
      (should (equal "theirs" (my/test-sync--read (funcall local "00_Roam/theirs.org"))))
      (should (equal "mine" (my/test-sync--read (funcall remote "00_Roam/mine.org"))))
      (should-not (file-exists-p (funcall remote "00_Roam/org-roam.db")))
      (should-not (my/sync--needs-resync-p))
      ;; Later runs carry edits, new files and deletions both ways.
      (my/test-sync--write (funcall local "00_Roam/mine.org") "mine, edited")
      (my/test-sync--write (funcall remote "10_Outputs/new.org") "new")
      (delete-file (funcall remote "00_Roam/theirs.org"))
      (should (my/sync-run nil nil t))
      (should (equal "mine, edited"
                     (my/test-sync--read (funcall remote "00_Roam/mine.org"))))
      (should (equal "new" (my/test-sync--read (funcall local "10_Outputs/new.org"))))
      (should-not (file-exists-p (funcall local "00_Roam/theirs.org")))
      (should (file-exists-p (funcall local "00_Roam/org-roam.db")))
      ;; Both sides edit one file: the newer wins, the other is kept.
      (my/test-sync--write (funcall remote "00_Roam/mine.org") "remote edit")
      (set-file-times (funcall remote "00_Roam/mine.org")
                      (time-subtract nil 3600))
      (my/test-sync--write (funcall local "00_Roam/mine.org") "local edit, newer")
      (should (my/sync-run nil nil t))
      (should (equal "local edit, newer"
                     (my/test-sync--read (funcall local "00_Roam/mine.org"))))
      (should (equal "local edit, newer"
                     (my/test-sync--read (funcall remote "00_Roam/mine.org"))))
      (let ((conflicts (my/sync-conflict-files)))
        (should (= 1 (length conflicts)))
        (should (equal "remote edit" (my/test-sync--read (car conflicts))))))))

;;; test-init-sync.el ends here
