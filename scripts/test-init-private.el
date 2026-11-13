;;; test-init-private.el --- Tests for the private zone -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar my/note-home)
(defvar my/inbox-dir)
(defvar my/private-dir)
(defvar my/snapshot-dir)
(defvar my/index-file)
(defvar my/index-sync-interval)
(defvar my/storage-snapshot-keep)
(defvar my/ai-confirm-full-buffer-send)

(let ((dir (file-name-directory load-file-name)))
  (dolist (sub '("../kernel"))
    (add-to-list 'load-path (expand-file-name sub dir)))
  (load-file (expand-file-name "../kernel/orgseq-paths.el" dir))
  (load-file (expand-file-name "../kernel/orgseq-index.el" dir))
  (load-file (expand-file-name "../kernel/orgseq-note.el" dir))
  (load-file (expand-file-name "../modules/notes/init-sync.el" dir))
  (load-file (expand-file-name "../modules/notes/init-private.el" dir))
  (defconst my/test-private--ai-source
    (expand-file-name "../modules/tools/init-ai.el" dir)))

(defmacro my/test-private--with-dirs (&rest body)
  "Run BODY with a temporary library, private zone and snapshot directory."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "org-seq-private-" t)))
          (my/note-home (expand-file-name "library/" root))
          (my/inbox-dir (expand-file-name "00_Inbox/" my/note-home))
          (my/private-dir (expand-file-name "private/" root))
          (my/snapshot-dir (expand-file-name "snapshots/" root))
          (my/index-file (expand-file-name "index.db" root))
          (my/index-sync-interval 0)
          (inhibit-message t))
     (unwind-protect
         (progn (make-directory my/inbox-dir t) ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (string-prefix-p root (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (my/index-close)
       (delete-directory root t))))

(ert-deftest my/private-dir-defaults-outside-the-library ()
  "The zone is a sibling of the library, never a directory inside it."
  (let ((process-environment (copy-sequence process-environment))
        (user-emacs-directory "/tmp/org-seq-emacs/"))
    (setenv "ORG_SEQ_PRIVATE_DIR" nil)
    (setenv "ORG_SEQ_NOTE_HOME" nil)
    (should (equal (my/private-dir--resolve-default)
                   "/tmp/org-seq-emacs/private/"))
    (setenv "ORG_SEQ_NOTE_HOME" "/tmp/org-seq-lib/notes")
    (should (equal (my/private-dir--resolve-default)
                   "/tmp/org-seq-lib/notes.private/"))
    (setenv "ORG_SEQ_PRIVATE_DIR" "/tmp/elsewhere")
    (should (equal (my/private-dir--resolve-default) "/tmp/elsewhere/"))))

(ert-deftest my/private-note-is-written-outside-the-index ()
  (my/test-private--with-dirs
    (let* ((note (my/note-create :title "Session one" :private t
                                 :body "Confidential text.\n"))
           (file (plist-get note :file)))
      (should (my/private-file-p file))
      (should (file-exists-p file))
      (should-not (my/index-file-p file))
      (should-not (my/index-node (plist-get note :id)))
      (should-not (my/index-search "Confidential"))
      (should-not (cl-find file (my/index-records)
                           :key (lambda (r) (plist-get r :file)) :test #'equal))
      (unless (eq system-type 'windows-nt)
        (should (= (logand (file-modes file) #o077) 0))
        (should (= (logand (file-modes my/private-dir) #o077) 0))))))

(ert-deftest my/private-note-cannot-leave-the-zone ()
  (my/test-private--with-dirs
    (should-error (my/note-create :title "Escape" :private t
                                  :file "../library/00_Inbox/escape.org")
                  :type 'user-error)
    (should-not (file-exists-p (expand-file-name "escape.org" my/inbox-dir)))))

(ert-deftest my/private-zone-inside-the-library-is-still-not-indexed ()
  "A misconfigured zone is reported and its files do not become nodes."
  (my/test-private--with-dirs
    (let ((my/private-dir (expand-file-name "90_Private/" my/note-home)))
      (should (my/private-inside-library-p))
      (should (plist-get (my/private-info) :inside-library))
      (let ((file (plist-get (my/note-create :title "Inside" :private t)
                             :file)))
        (should-not (my/index-file-p file))
        (my/index-sync t)
        (should-not (my/index-records)))
      ;; A library note may not be written into the zone.
      (should-error (my/note-create
                     :title "Leak"
                     :file (expand-file-name "leak.org" my/private-dir))
                    :type 'user-error))))

(ert-deftest my/private-info-reports-counts-only ()
  (my/test-private--with-dirs
    (should-not (plist-get (my/private-info) :exists))
    (should-not (file-directory-p my/private-dir))
    (my/note-create :title "Client A" :private t)
    (let ((info (my/private-info)))
      (should (plist-get info :exists))
      (should (= (plist-get info :files) 1))
      (should (= (plist-get info :notes) 1))
      (should-not (plist-get info :inside-library))
      (should-not (plist-get info :open-to-others))
      (should-not (string-match-p "Client" (format "%S" info))))))

(ert-deftest my/private-mode-switches-off-backups ()
  (my/test-private--with-dirs
    (let ((private (plist-get (my/note-create :title "P" :private t) :file))
          (public (plist-get (my/note-create :title "Q") :file)))
      (with-current-buffer (find-file-noselect private)
        (should my/private-mode)
        (should backup-inhibited))
      (with-current-buffer (find-file-noselect public)
        (should-not my/private-mode)))))

(ert-deftest my/private-snapshot-copies-and-prunes ()
  (my/test-private--with-dirs
    (should-not (my/private-snapshot))
    (my/note-create :title "One" :private t :body "one\n")
    (let ((my/storage-snapshot-keep 2)
          (copies nil))
      (dotimes (_ 3) (push (my/private-snapshot) copies))
      (should (= (length (my/private-snapshots)) 2))
      (should (string-prefix-p (my/private-snapshot-dir) (car copies)))
      (should (= (length (directory-files-recursively (car copies) "\\.org\\'"))
                 1))
      ;; Library snapshots never contain the zone.
      (my/note-create :title "Public")
      (let ((snapshot (my/storage-snapshot)))
        (should snapshot)
        (should-not (cl-some (lambda (file) (string-match-p "one" file))
                             (directory-files-recursively snapshot "")))
        (should (= (length (directory-files-recursively snapshot "\\.org\\'"))
                   1))))))

(ert-deftest my/ai-get-text-refuses-the-private-zone ()
  "The in-buffer AI helpers check the zone before anything else."
  (let ((source (with-temp-buffer
                  (insert-file-contents my/test-private--ai-source)
                  (buffer-string))))
    (should (string-match
             "(defun my/ai--get-text ()\\(?:.\\|\n\\)*?my/private-file-p buffer-file-name\\(?:.\\|\n\\)*?(if (use-region-p)"
             source))))

(provide 'test-init-private)
;;; test-init-private.el ends here
