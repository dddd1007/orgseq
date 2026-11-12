;;; test-orgseq-index.el --- Tests for the kernel node index -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory load-file-name)))
  (add-to-list 'load-path (expand-file-name "../kernel" dir))
  (load-file (expand-file-name "../kernel/orgseq-paths.el" dir))
  (load-file (expand-file-name "../kernel/orgseq-index.el" dir)))

(defun my/test-index--write (file text)
  "Write TEXT to FILE, creating parent directories."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file file (insert text))))

(defmacro my/test-index--with-library (&rest body)
  "Run BODY with a temporary library and index; binds `root'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "org-seq-index-" t)))
          (my/note-home (expand-file-name "library/" root))
          (my/roam-dir (expand-file-name "00_Roam/" my/note-home))
          (my/library-dir (expand-file-name "30_Library/" my/note-home))
          (my/archives-dir (expand-file-name "40_Archives/" my/note-home))
          (my/index-file (expand-file-name "index.db" root))
          (my/index-sync-interval 0)
          (inhibit-message t))
     (unwind-protect
         (progn (make-directory my/roam-dir t) ,@body)
       (my/index-close)
       (delete-directory root t))))

(defconst my/test-index--note
  ":PROPERTIES:
:ID:       file-1
:STATUS:   doing
:END:
#+title: Working memory
#+filetags: :reading:draft:

Intro with [[id:other-1][another note]].

* Plain heading without an id
Text under it links to [[id:other-2]].

* NEXT [#A] Read [[id:other-1][Cowan]] review          :paper:
SCHEDULED: <2026-11-14 Sat>
:PROPERTIES:
:ID:       head-1
:YEAR:     2001
:END:
Capacity is about four chunks.  See [[id:file-1][the file]].

** Nested detail
:PROPERTIES:
:ID:       head-2
:END:
Deep text, 中央执行系统负责分配注意资源.

* DONE Summary
Closing words.
")

(ert-deftest my/index-parses-nodes-tags-properties-and-links ()
  (with-temp-buffer
    (insert my/test-index--note)
    (pcase-let* ((`(,nodes ,links ,texts) (my/index-parse-buffer "/lib/wm.org"))
                 (`(,file ,head ,nested) nodes))
      (should (equal (mapcar (lambda (n) (plist-get n :id)) nodes)
                     '("file-1" "head-1" "head-2")))
      (should (equal (plist-get file :title) "Working memory"))
      (should (equal (plist-get file :tags) '("reading" "draft")))
      (should (equal (cdr (assoc "STATUS" (plist-get file :props))) "doing"))
      (should (= 0 (plist-get file :level)))
      ;; Heading: TODO state, priority, link markup and tags are split off.
      (should (equal (plist-get head :title) "Read Cowan review"))
      (should (equal (plist-get head :todo) "NEXT"))
      (should (equal (plist-get head :priority) "A"))
      (should (equal (plist-get head :tags) '("reading" "draft" "paper")))
      (should (equal (cdr (assoc "YEAR" (plist-get head :props))) "2001"))
      (should (equal (cdr (assoc "SCHEDULED" (plist-get head :props)))
                     "<2026-11-14 Sat>"))
      (should (null (plist-get head :olp)))
      (should (equal (plist-get nested :olp) '("Read Cowan review")))
      (should (equal (plist-get nested :tags) '("reading" "draft" "paper")))
      ;; A link belongs to the innermost node around it; text under a
      ;; heading without an id belongs to the file node.
      (should (equal (sort (copy-sequence links)
                           (lambda (a b) (string< (format "%s" a) (format "%s" b))))
                     '(("file-1" . "other-1") ("file-1" . "other-2")
                       ("head-1" . "file-1") ("head-1" . "other-1"))))
      ;; Own text excludes nested nodes and resumes after them.
      (let ((own (cdr (assoc "file-1" texts))))
        (should (string-match-p "Plain heading" own))
        (should (string-match-p "Closing words" own))
        (should-not (string-match-p "four chunks" own)))
      (should-not (string-match-p "Deep text" (cdr (assoc "head-1" texts))))
      (should (string-match-p "Deep text" (cdr (assoc "head-2" texts)))))))

(ert-deftest my/index-refreshes-incrementally-and-forgets-deleted-files ()
  (my/test-index--with-library
    (let ((note (expand-file-name "wm.org" my/roam-dir))
          (other (expand-file-name "other.org" my/roam-dir)))
      (my/test-index--write note my/test-index--note)
      (my/test-index--write other ":PROPERTIES:\n:ID: other-1\n:END:\n#+title: Other\n")
      ;; Files outside the scope are not nodes.
      (my/test-index--write (expand-file-name "ref.org" my/library-dir)
                            ":PROPERTIES:\n:ID: ref-1\n:END:\n#+title: Ref\n")
      (my/test-index--write (expand-file-name ".orgseq/types.org" my/note-home)
                            "* Type\n:PROPERTIES:\n:ID: type-1\n:END:\n")
      (should (= 2 (my/index-sync)))
      (should (= 0 (my/index-sync)))
      (let ((records (my/index-records)))
        (should (equal (sort (mapcar (lambda (r) (plist-get r :id)) records) #'string<)
                       '("file-1" "head-1" "head-2" "other-1")))
        (let ((head (cl-find "head-1" records :key (lambda (r) (plist-get r :id))
                             :test #'equal)))
          (should (equal (plist-get head :file) note))
          (should (equal (plist-get head :todo) "NEXT"))
          (should (plist-get head :mtime))
          ;; Records are the caller's own copies.
          (plist-put head :title "changed")
          (should (equal (plist-get (my/index-node "head-1") :title)
                         "Read Cowan review"))))
      (should (member '("head-1" "file-1") (my/index-links)))
      ;; An edit is picked up from the file's size and time alone.
      (my/test-index--write other ":PROPERTIES:\n:ID: other-1\n:END:\n#+title: Renamed other\n")
      (should (= 1 (my/index-sync)))
      (should (equal (plist-get (my/index-node "other-1") :title) "Renamed other"))
      ;; A single file can be pushed in directly, and a deleted file goes.
      (my/test-index--write other ":PROPERTIES:\n:ID: other-9\n:END:\n#+title: Nine\n")
      (should (my/index-update-file other))
      (should-not (my/index-node "other-1"))
      (should (my/index-node "other-9"))
      (delete-file note)
      (should (= 1 (my/index-sync)))
      (should-not (my/index-node "file-1"))
      (should (= 1 (plist-get (my/index-stats) :nodes)))
      ;; A rebuild gives the same answer from nothing.
      (should (= 1 (my/index-rebuild)))
      (should (my/index-node "other-9")))))

(ert-deftest my/index-search-finds-substrings-in-any-script ()
  (my/test-index--with-library
    (my/test-index--write (expand-file-name "wm.org" my/roam-dir) my/test-index--note)
    (should (equal (mapcar #'car (my/index-search "注意资源")) '("head-2")))
    (should (equal (mapcar #'car (my/index-search "four CHUNKS")) '("head-1")))
    ;; Titles outrank body text, and short queries still work.
    (should (equal (car (car (my/index-search "memory"))) "file-1"))
    (should (member "head-2" (mapcar #'car (my/index-search "资源"))))
    (should-not (my/index-search "no such text anywhere"))
    (should-not (my/index-search "   "))
;; Characters special to the query syntax are taken literally.
    (should-not (my/index-search "100%\"quoted\""))))

(ert-deftest my/index-is-separate-per-library ()
  (let ((my/index-file nil)
        (my/note-home "/tmp/library-a/"))
    (let ((a (my/index--file)))
      (let ((my/note-home "/tmp/library-b/"))
        (should-not (equal a (my/index--file))))
      (should (string-match-p "/\\.cache/index-[0-9a-f]+\\.db\\'" a)))))

;;; test-orgseq-index.el ends here
