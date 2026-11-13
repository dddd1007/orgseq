;;; test-init-import.el --- Tests for the Notion and Tana imports -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar my/note-home)
(defvar my/inbox-dir)
(defvar my/outputs-dir)
(defvar my/practice-dir)
(defvar my/library-dir)
(defvar my/archives-dir)
(defvar my/ai-dir)
(defvar my/private-dir)
(defvar my/snapshot-dir)
(defvar my/index-file)
(defvar my/index-sync-interval)
(defvar my/node-types)

(let ((dir (file-name-directory load-file-name)))
  (add-to-list 'load-path (expand-file-name "../kernel" dir))
  (load-file (expand-file-name "../modules/notes/init-nodes.el" dir))
  (load-file (expand-file-name "../modules/notes/init-views.el" dir))
  (load-file (expand-file-name "../modules/notes/init-sync.el" dir))
  (load-file (expand-file-name "../modules/notes/init-private.el" dir))
  (load-file (expand-file-name "../modules/notes/init-import.el" dir)))

(defconst my/test-import--a "0123456789abcdef0123456789abcdef")
(defconst my/test-import--b "1123456789abcdef0123456789abcdef")
(defconst my/test-import--c "2123456789abcdef0123456789abcdef")
(defconst my/test-import--d "3123456789abcdef0123456789abcdef")
(defconst my/test-import--e "4123456789abcdef0123456789abcdef")

(defconst my/test-import--types
  "#+title: Node types

* Lesson
:PROPERTIES:
:TYPE_TAG:    lesson
:TYPE_FIELDS: STATUS DUE:date DONE:check TEACHER:node
:TYPE_LAYER:  area
:END:
")

(defun my/test-import--write (file text)
  "Write TEXT to FILE, creating parent directories."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file file (insert text))))

(defun my/test-import--slurp (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/test-import--export (dir)
  "Write a small Notion export into DIR."
  (let ((a my/test-import--a) (b my/test-import--b) (c my/test-import--c)
        (d my/test-import--d) (e my/test-import--e))
    (my/test-import--write
     (expand-file-name (format "Home %s.md" a) dir)
     (concat "# Home\n\n"
             "Status: this line is text, not a property\n\n"
             "## Plan\n\n"
             "- [x] done **bold** item\n"
             "- [ ] open item with `code`\n"
             "* starred item\n\n"
             (format "See [Sub Page](Home%%20%s/Sub%%20Page%%20%s.md) and [site](https://example.org/a_(b)).\n" a b)
             (format "![shot](Home%%20%s/pic.png)\n" a)
             "[Gone](Elsewhere%20ffffffffffffffffffffffffffffffff.md)\n\n"
             "> quoted line\n> second\n\n"
             "```python\n* not a heading\nprint(1)\n```\n\n"
             "| A | B |\n| --- | --- |\n| 1 | 2 |\n"))
    (my/test-import--write
     (expand-file-name (format "Home %s/Sub Page %s.md" a b) dir)
     (format "# Sub Page\n\nBack to [Home](../Home%%20%s.md).\n" a))
    (my/test-import--write
     (expand-file-name (format "Home %s/pic.png" a) dir) "PNG")
    (my/test-import--write
     (expand-file-name (format "Courses %s.csv" c) dir)
     "﻿Name,Status,Due,Done,Teacher,\"Class, room\"\nUnit 1,Ready,\"November 5, 2026\",Yes,,\n")
    (my/test-import--write
     (expand-file-name (format "Courses %s/Unit 1 %s.md" c d) dir)
     (concat "# Unit 1\n\n"
             "Status: Ready\n"
             "Due: November 5, 2026\n"
             "Done: Yes\n"
             (format "Teacher: Sub Page (../Home%%20%s/Sub%%20Page%%20%s.md)\n" a b)
             "Class, room: B204\n\n"
             "Lesson text.\n"))
    ;; Newer exports name the rows folder without the id.
    (my/test-import--write
     (expand-file-name (format "Courses/Unit 2 %s.md" e) dir)
     "# Unit 2\n\nStatus: Draft\nDue: 2026/11/09\n")))

(defmacro my/test-import--with-library (&rest body)
  "Run BODY with a temporary library, private zone and Notion export.
Binds `root' and `export'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "org-seq-import-" t)))
          (export (expand-file-name "export/" root))
          (my/note-home (expand-file-name "library/" root))
          (my/inbox-dir (expand-file-name "00_Inbox/" my/note-home))
          (my/outputs-dir (expand-file-name "10_Outputs/" my/note-home))
          (my/practice-dir (expand-file-name "20_Practice/" my/note-home))
          (my/library-dir (expand-file-name "30_Library/" my/note-home))
          (my/archives-dir (expand-file-name "40_Archives/" my/note-home))
          (my/ai-dir (expand-file-name "50_AI/" my/note-home))
          (my/private-dir (expand-file-name "private/" root))
          (my/snapshot-dir (expand-file-name "snapshots/" root))
          (my/index-file (expand-file-name "index.db" root))
          (my/index-sync-interval 0)
          (my/node-types
           (with-temp-buffer
             (insert my/test-import--types)
             (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
             (my/node-types-parse-buffer)))
          (org-inhibit-startup t)
          (inhibit-message t))
     (unwind-protect
         (progn (make-directory my/inbox-dir t)
                (my/test-import--export export)
                ,@body)
       (my/index-close)
       (delete-directory root t))))

(defun my/test-import--node (key)
  "Return the index record imported from the Notion page KEY."
  (cl-find key (my/index-records)
           :key (lambda (r) (cdr (assoc "NOTION_ID" (plist-get r :props))))
           :test #'equal))

;; -- Markdown --

(ert-deftest my/notion-md-to-org-converts-blocks ()
  (should (equal (my/notion-md-to-org
                  "# One\n### Three\n- [x] a\n- [ ] b\n* c\n    - nested\n1. first\n---")
                 "* One\n*** Three\n- [X] a\n- [ ] b\n- c\n    - nested\n1. first\n-----"))
  ;; The shallowest heading becomes level one; code is not a heading.
  (should (equal (my/notion-md-to-org "## Two\n```\n# code\n```\n#### Four")
                 "* Two\n#+begin_example\n# code\n#+end_example\n*** Four"))
  (should (equal (my/notion-md-to-org "> a\n> b\ntext")
                 "#+begin_quote\na\nb\n#+end_quote\ntext"))
  (should (equal (my/notion-md-to-org "```python\n* x\n#+y\n**z**\n```\n```\nplain\n```")
                 "#+begin_src python\n,* x\n,#+y\n,**z**\n#+end_src\n#+begin_example\nplain\n#+end_example"))
  (should (equal (my/notion-md-to-org "| A | B |\n| --- | :-: |\n| 1 | 2 |")
                 "| A | B |\n|-\n| 1 | 2 |"))
  (should (equal (my/notion-md-to-org "<aside>\nnote\n</aside>")
                 "#+begin_quote\nnote\n#+end_quote")))

(ert-deftest my/notion-md-to-org-converts-inline-markup ()
  (should (equal (my/notion-md-to-org "**bold** and *it* and ~~gone~~ and `a*b*c`")
                 "*bold* and /it/ and +gone+ and ~a*b*c~"))
  (should (equal (my/notion-md-to-org "[site](https://example.org/a_(b)) ![x](https://e.org/p.png)")
                 "[[https://example.org/a_(b)][site]] [[https://e.org/p.png]]"))
  (should (equal (my/notion-md-to-org "**see [a](https://e.org)**")
                 "*see [[https://e.org][a]]*"))
  ;; snake_case and a lone star are left alone.
  (should (equal (my/notion-md-to-org "my_var_name 2 * 3") "my_var_name 2 * 3")))

;; -- Values --

(ert-deftest my/notion-dates-and-values-are-normalised ()
  (should (equal (my/notion--date "November 5, 2026") "2026-11-05"))
  (should (equal (my/notion--date "November 5, 2026 3:30 PM") "2026-11-05 15:30"))
  (should (equal (my/notion--date "March 1, 2026 12:05 AM") "2026-03-01 00:05"))
  (should (equal (my/notion--date "2026/11/09") "2026-11-09"))
  (should (equal (my/notion--date "2026年11月5日") "2026-11-05"))
  (should-not (my/notion--date "Unit 5, 2026 notes"))
  (should-not (my/notion--date "Ready"))
  (let ((plain (lambda (_kind label _target) (concat "<" label ">"))))
    (should (equal (my/notion--value "Yes" plain) "yes"))
    (should (equal (my/notion--value "November 5, 2026 → November 9, 2026" plain)
                   "2026-11-05--2026-11-09"))
    (should (equal (my/notion--value "A (x/A%20aa.md), B (B%20bb.md)" plain)
                   "<A> <B>"))
    (should (equal (my/notion--value "plain, text" plain) "plain, text"))))

(ert-deftest my/notion-property-names-are-safe ()
  (should (equal (my/notion--property-name "Class, room" nil) "CLASS,_ROOM"))
  (should (equal (my/notion--property-name "Due date" nil) "DUE_DATE"))
  (should (equal (my/notion--property-name "ID" nil) "NOTION_ID"))
  (should (equal (my/notion--property-name "Tags" nil) "NOTION_TAGS"))
  (should (equal (my/notion--property-name "Due date" '(("due date" . "due")))
                 "DUE"))
  (should (equal (my/notion--split-name (concat "Unit 1 " my/test-import--d))
                 (cons "Unit 1" my/test-import--d)))
  (should (equal (my/notion--split-name "Courses") '("Courses")))
  (should (equal (my/notion--csv-row "a,\"b, \"\"c\"\"\",,d")
                 '("a" "b, \"c\"" "" "d"))))

;; -- Plan --

(ert-deftest my/notion-import-plan-changes-nothing ()
  (my/test-import--with-library
    (let ((plan (my/notion-import-plan export :type "Lesson")))
      ;; Four pages and the note that stands for the Courses database.
      (should (= (plist-get plan :new) 5))
      (should (= (plist-get plan :existing) 0))
      (should (string-prefix-p my/practice-dir (plist-get plan :target)))
      (let ((database (car (plist-get plan :databases))))
        (should (= (length (plist-get plan :databases)) 1))
        (should (equal (plist-get database :name) "Courses"))
        (should (= (plist-get database :pages) 2))
        (should (equal (plist-get database :properties)
                       '("Status" "Due" "Done" "Teacher" "Class, room")))
        (should (equal (plist-get database :unmapped) '("Class, room"))))
      (should-not (my/index-records))
      (should-not (file-directory-p my/practice-dir))
      (should-not (file-directory-p my/snapshot-dir)))
    (should-error (my/notion-import-plan export :type "Nope") :type 'user-error)
    (should-error (my/notion-import-plan export :layer "attic") :type 'user-error)
    (should-error (my/notion-import-plan export :folder "../..") :type 'user-error)
    (should-error (my/notion-import-plan (expand-file-name "missing" root))
                  :type 'user-error)))

(ert-deftest my/notion-import-gives-each-database-its-own-type ()
  "One run over the whole export: typed rows, untyped pages, links intact."
  (my/test-import--with-library
    (let ((plan (my/notion-import-plan export
                                       :types '(("Courses" . "Lesson")))))
      (should (equal (plist-get (car (plist-get plan :databases)) :type)
                     "Lesson"))
      (should (= (length (plist-get plan :targets)) 2)))
    (should-error (my/notion-import-plan export :types '(("Nope" . "Lesson")))
                  :type 'user-error)
    (should-error (my/notion-import-plan export :types '(("Courses" . "Nope")))
                  :type 'user-error)
    (my/notion-import export :types '(("Courses" . "Lesson")))
    (let ((unit (my/test-import--node my/test-import--d))
          (home (my/test-import--node my/test-import--a))
          (sub (my/test-import--node my/test-import--b)))
      (should (eq (plist-get unit :layer) 'area))
      (should (member "lesson" (plist-get unit :tags)))
      (should (eq (plist-get home :layer) 'resource))
      (should-not (plist-get home :tags))
      ;; The row's relation reaches a page that has no type.
      (should (equal (cdr (assoc "TEACHER" (plist-get unit :props)))
                     (format "[[id:%s][Sub Page]]" (plist-get sub :id)))))))

;; -- Import --

(ert-deftest my/notion-import-writes-nodes-with-links-and-assets ()
  (my/test-import--with-library
    (let ((result (my/notion-import export)))
      (should (= (plist-get result :created) 5))
      (should (= (plist-get result :assets) 1))
      (should (= (plist-get result :unresolved) 1))
      (should (equal (plist-get result :target)
                     (expand-file-name "notion/" my/library-dir))))
    (let* ((home (my/test-import--node my/test-import--a))
           (sub (my/test-import--node my/test-import--b))
           (text (my/test-import--slurp (plist-get home :file))))
      (should (equal (plist-get home :title) "Home"))
      (should (eq (plist-get home :layer) 'resource))
      ;; Text that looks like a property stays text on an ordinary page.
      (should (string-match-p "^Status: this line is text" text))
      (should-not (assoc "STATUS" (plist-get home :props)))
      (should (string-match-p "^\\* Plan$" text))
      (should (string-match-p "^- \\[X\\] done \\*bold\\* item$" text))
      (should (string-match-p "^- starred item$" text))
      (should (string-match-p
               (regexp-quote (format "[[id:%s][Sub Page]]" (plist-get sub :id)))
               text))
      (should (string-match-p (regexp-quote "[[https://example.org/a_(b)][site]]")
                              text))
      ;; A page outside the export keeps its words, without a dead link.
      (should (string-match-p "^Gone$" text))
      (should (string-match-p "^,\\* not a heading$" text))
      (should (string-match "\\[\\[file:\\(assets/[^]]+pic\\.png\\)\\]\\]" text))
      (should (file-exists-p
               (expand-file-name (match-string 1 text)
                                 (file-name-directory (plist-get home :file)))))
      ;; The link back resolves too, and shows up as a backlink.
      (should (string-match-p
               (regexp-quote (format "[[id:%s][Home]]" (plist-get home :id)))
               (my/test-import--slurp (plist-get sub :file)))))
    ;; The export itself is untouched.
    (should (file-exists-p (expand-file-name
                            (format "Home %s/pic.png" my/test-import--a) export)))))

(ert-deftest my/notion-import-maps-database-rows-to-a-type ()
  (my/test-import--with-library
    (my/notion-import export :type "Lesson" :map '(("Class, room" . "room")))
    (let* ((unit (my/test-import--node my/test-import--d))
           (teacher (my/test-import--node my/test-import--b))
           (props (plist-get unit :props)))
      (should (eq (plist-get unit :layer) 'area))
      (should (member "lesson" (plist-get unit :tags)))
      (should (equal (cdr (assoc "STATUS" props)) "Ready"))
      (should (equal (cdr (assoc "DUE" props)) "2026-11-05"))
      (should (equal (cdr (assoc "DONE" props)) "yes"))
      (should (equal (cdr (assoc "ROOM" props)) "B204"))
      (should (equal (cdr (assoc "TEACHER" props))
                     (format "[[id:%s][Sub Page]]" (plist-get teacher :id))))
      (should (string-match-p "Lesson text\\."
                              (my/test-import--slurp (plist-get unit :file)))))
    ;; A row in a folder named without the id, with fewer properties:
    ;; the type's other fields are present and empty.
    (let ((props (plist-get (my/test-import--node my/test-import--e) :props)))
      (should (equal (cdr (assoc "DUE" props)) "2026-11-09"))
      (should (assoc "TEACHER" props)))))

(ert-deftest my/notion-import-skips-pages-imported-before ()
  (my/test-import--with-library
    (should (= (plist-get (my/notion-import export) :created) 5))
    (let* ((home (my/test-import--node my/test-import--a))
           (file (plist-get home :file)))
      (my/test-import--write file (concat (my/test-import--slurp file)
                                          "\nEdited after the import.\n"))
      (my/index-sync t)
      (let ((plan (my/notion-import-plan export)))
        (should (= (plist-get plan :new) 0))
        (should (= (plist-get plan :existing) 5)))
      (let ((result (my/notion-import export)))
        (should (= (plist-get result :created) 0))
        (should (= (plist-get result :skipped) 5)))
      (should (= (length (my/index-records)) 5))
      (should (string-match-p "Edited after the import"
                              (my/test-import--slurp file)))
      ;; A page added to the export later links to the earlier import.
      (my/test-import--write
       (expand-file-name "Later 5123456789abcdef0123456789abcdef.md" export)
       (format "# Later\n\n[Home](Home%%20%s.md)\n" my/test-import--a))
      (should (= (plist-get (my/notion-import export) :created) 1))
      (should (string-match-p
               (regexp-quote (format "[[id:%s][Home]]" (plist-get home :id)))
               (my/test-import--slurp
                (plist-get (my/test-import--node
                            "5123456789abcdef0123456789abcdef")
                           :file)))))))

(ert-deftest my/notion-import-takes-a-snapshot-first ()
  (my/test-import--with-library
    (my/note-create :title "Existing" :body "before\n")
    (let ((result (my/notion-import export)))
      (should (plist-get result :snapshot))
      (should (= (length (directory-files-recursively
                          (plist-get result :snapshot) "\\.org\\'"))
                 1)))))

(ert-deftest my/notion-import-private-stays-out-of-the-index ()
  (my/test-import--with-library
    (let ((result (my/notion-import export :private t)))
      (should (= (plist-get result :created) 5))
      (should (= (plist-get result :private) 5))
      (should (string-prefix-p my/private-dir (plist-get result :target))))
    (should-not (my/index-records))
    (should-not (my/index-search "Lesson text"))
    (should-not (file-directory-p my/library-dir))
    (let* ((files (directory-files-recursively my/private-dir "\\.org\\'"))
           (home (cl-find-if (lambda (f) (string-match-p "home" f)) files))
           (sub (cl-find-if (lambda (f) (string-match-p "sub_page" f)) files)))
      (should (= (length files) 5))
      ;; The database note lists its rows; there is no index for a table.
      (should (string-match-p
               "^- \\[\\[file:unit_1\\.org\\]\\[Unit 1\\]\\]$"
               (my/test-import--slurp
                (cl-find-if (lambda (f) (string-match-p "courses" f)) files))))
      ;; No index resolves ids there, so page links are file links.
      (should (string-match-p
               (regexp-quote (format "[[file:%s][Sub Page]]"
                                     (file-name-nondirectory sub)))
               (my/test-import--slurp home))))
    ;; A second run knows the private notes and a library import of the
    ;; same pages is refused as already imported.
    (should (= (plist-get (my/notion-import-plan export :private t) :new) 0))
    (should (= (plist-get (my/notion-import-plan export) :new) 0))))

;; -- Routes, databases, real export names --

(ert-deftest my/import-routes-pick-the-longest-prefix ()
  (let ((routes '(("*" . "inbox/misc") ("Area" . "area")
                  ("Area/Clinic" . "private/clinic") ("Trash" . "skip"))))
    (should (equal (my/import--route '("Area" "Teaching" "Unit") routes)
                   '("area" "Teaching")))
    (should (equal (my/import--route '("Area") routes) '("area")))
    (should (equal (my/import--route '("Area" "Clinic" "Notes" "A") routes)
                   '("private/clinic" "Notes")))
    (should (equal (my/import--route '("Loose") routes) '("inbox/misc")))
    (should (equal (my/import--route '("Trash" "X") routes) '("skip")))
    (should-not (my/import--route '("Loose") (cdr routes)))))

(ert-deftest my/import-profile-is-read ()
  (let ((file (make-temp-file "org-seq-profile-")))
    (unwind-protect
        (progn
          (my/test-import--write
           file "# choices\nroute Area/Clinic = private/clinic\nroute * = inbox\n\ntype Courses = Lesson\nmap Class, room = room\n")
          (should (equal (my/import-profile-read file)
                         '(:routes (("Area/Clinic" . "private/clinic")
                                    ("*" . "inbox"))
                           :types (("Courses" . "Lesson"))
                           :map (("Class, room" . "room")))))
          (my/test-import--write file "nonsense\n")
          (should-error (my/import-profile-read file) :type 'user-error))
      (delete-file file))))

(ert-deftest my/notion-import-follows-routes ()
  (my/test-import--with-library
    (my/test-import--write
     (expand-file-name "Later 5123456789abcdef0123456789abcdef.md" export)
     (format "# Later\n\n[Unit 1](Courses%%20%s/Unit%%201%%20%s.md) and [Sub Page](Home%%20%s/Sub%%20Page%%20%s.md)\n"
             my/test-import--c my/test-import--d
             my/test-import--a my/test-import--b))
    (let* ((routes '(("Home" . "area/home") ("Home/Sub Page" . "skip")
                     ("Courses" . "private/courses") ("*" . "inbox/misc")))
           (plan (my/notion-import-plan export :routes routes))
           (result (my/notion-import export :routes routes
                                     :types '(("Courses" . "Lesson")))))
      (should (= (plist-get plan :new) 5))
      (should (= (plist-get plan :new-private) 3))
      (should (= (plist-get plan :left-out) 1))
      (should (= (plist-get result :created) 5))
      (should (= (plist-get result :private) 3))
      ;; Later links to a private row: the words stay, the link does not.
      (should (= (plist-get result :withheld) 1))
      (let ((home (my/test-import--node my/test-import--a))
            (later (my/test-import--node "5123456789abcdef0123456789abcdef")))
        (should (equal (plist-get home :file)
                       (expand-file-name "home/home.org" my/practice-dir)))
        (should (equal (plist-get later :file)
                       (expand-file-name "misc/later.org" my/inbox-dir)))
        (should (string-match-p "^Unit 1 and Sub Page$"
                                (my/test-import--slurp (plist-get later :file)))))
      ;; Rows and the database note are in the zone, none in the index.
      (should-not (my/test-import--node my/test-import--d))
      (should-not (my/test-import--node my/test-import--b))
      (should (file-exists-p (expand-file-name "courses/unit_1.org"
                                               my/private-dir)))
      (should (= (file-modes (expand-file-name "courses/unit_1.org"
                                               my/private-dir))
                 #o600)))))

(ert-deftest my/notion-import-gives-a-database-a-note-with-its-rows ()
  (my/test-import--with-library
    (my/test-import--write
     (expand-file-name "Later 5123456789abcdef0123456789abcdef.md" export)
     (format "# Later\n\n[Untitled](Courses%%20%s.csv)\n\nsort: \nDue: descending\n\nAfter.\n"
             my/test-import--c))
    (my/notion-import export :routes '(("Courses" . "area/courses"))
                      :types '(("Courses" . "Lesson")))
    (let* ((courses (my/test-import--node my/test-import--c))
           (text (my/test-import--slurp (plist-get courses :file)))
           (later (my/test-import--slurp
                   (plist-get (my/test-import--node
                               "5123456789abcdef0123456789abcdef")
                              :file))))
      (should (equal (plist-get courses :title) "Courses"))
      (should (string-match-p
               (regexp-quote "#+BEGIN: orgseq-view :type \"lesson\" :filter (folder \"20_Practice/courses\")")
               text))
      ;; The block was filled: both rows, not the database note itself.
      (should (string-match-p "\\]\\[Unit 1\\]\\]" text))
      (should (string-match-p "\\]\\[Unit 2\\]\\]" text))
      (should (string-match-p "| *Ready *|" text))
      ;; A link to the database goes to its note under the note's title;
      ;; the view settings of the export are dropped.
      (should (string-match-p
               (regexp-quote (format "[[id:%s][Courses]]" (plist-get courses :id)))
               later))
      (should-not (string-match-p "descending" later))
      (should (string-match-p "^After\\.$" later)))))

(ert-deftest my/notion-export-names-are-understood ()
  (my/test-import--with-library
    (let* ((page "6123456789abcdef0123456789abcdef")
           (one "7123456789abcdef0123456789abcdef")
           (two "8123456789abcdef0123456789abcdef")
           (mem "4108aaaaaaaaaaaaaaaaaaaaaaaa63d6")
           (old "3fe8aaaaaaaaaaaaaaaaaaaaaaaae222")
           (row (lambda (n) (format "9%d23456789abcdef0123456789abcdef" n)))
           (dir (expand-file-name "real/" root)))
      ;; Two databases inside one page share one folder of rows.
      (my/test-import--write
       (expand-file-name (format "Clinic %s_Sessions %s_all.csv" page one) dir)
       "No,Topic\nS1,x\n")
      (my/test-import--write
       (expand-file-name (format "Clinic %s_Clients %s_all.csv" page two) dir)
       "Name,Grade\nK,2\n")
      (my/test-import--write
       (expand-file-name (format "Clinic/S1 %s.md" (funcall row 1)) dir)
       "# S1\n\nTopic: x\n\nBody\n")
      (my/test-import--write
       (expand-file-name (format "Clinic/K %s.md" (funcall row 2)) dir)
       "# K\n\nGrade: 2\n")
      ;; A folder whose title is not unique carries a shortened id.
      (my/test-import--write
       (expand-file-name (format "Memories %s_all.csv" old) dir) "Title,Type\n")
      (my/test-import--write
       (expand-file-name (format "Memories %s_all.csv" mem) dir)
       "Title,Type\nM,pref\n")
      (my/test-import--write
       (expand-file-name (format "Memories 4108-63d6/M %s.md" (funcall row 3)) dir)
       "# M\n\nType: pref\n")
      ;; Uploaded files are not pages.
      (my/test-import--write
       (expand-file-name "attachments/abc/SKILL.md" dir) "# Not a page\n")
      (my/test-import--write
       (expand-file-name "attachments/abc/data.csv" dir) "a,b\n1,2\n")
      (let* ((plan (my/notion-import-plan
                    dir :routes '(("Memories" . "ai/Memories"))))
             (pages (plist-get plan :pages))
             (by-title (lambda (title)
                         (cl-find title pages :test #'equal
                                  :key (lambda (p) (plist-get p :title))))))
        (should (equal (plist-get (funcall by-title "S1") :database) "Sessions"))
        (should (equal (plist-get (funcall by-title "K") :database) "Clients"))
        (should (equal (plist-get (funcall by-title "S1") :props)
                       '(("Topic" . "x"))))
        (should (equal (plist-get (funcall by-title "M") :database) "Memories"))
        (should (equal (plist-get (plist-get (funcall by-title "M") :db) :id)
                       mem))
        (should (equal (plist-get (funcall by-title "M") :dir)
                       (expand-file-name "Memories/" my/ai-dir)))
        (should-not (funcall by-title "Not a page"))
        ;; 3 rows + Sessions, Clients and the Memories that has rows.
        (should (= (plist-get plan :new) 6))))
    (should (equal (my/notion--root (expand-file-name "missing/" root))
                   (expand-file-name "missing/" root)))
    (make-directory (expand-file-name "zip/Export-1234" root) t)
    (should (equal (my/notion--root (expand-file-name "zip" root))
                   (expand-file-name "zip/Export-1234/" root)))))

(ert-deftest my/notion-values-keep-what-is-not-a-reference ()
  (let ((plain (lambda (_kind label target) (format "<%s|%s>" label target))))
    (should (equal (my/notion--value "Applied (rejected)" plain) "Applied (rejected)"))
    (should (equal (my/notion--value
                    "Teach, Not Punish (https://app.notion.com/p/c2750f92eecb48d3953b2ae40045c9db)"
                    plain)
                   "<Teach, Not Punish|https://app.notion.com/p/c2750f92eecb48d3953b2ae40045c9db>"))
    (should (equal (my/notion--value "refs (https://e.org/a), scripts (https://e.org/b)" plain)
                   "<refs|https://e.org/a> <scripts|https://e.org/b>"))))

;; -- Tana --

(defconst my/test-import--tana
  "{\"version\": \"TanaIntermediateFile V2.2\", \"contents\": {
 \"workspace\": {\"type\": \"node\", \"id\": \"W\", \"nameParts\": [], \"children\": [
  {\"type\": \"node\", \"id\": \"dn\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Daily notes\"}], \"children\": [
   {\"type\": \"journalPart\", \"id\": \"y\", \"granularity\": \"year\", \"date\": \"2026\", \"nameParts\": [], \"children\": [
    {\"type\": \"journalPart\", \"id\": \"d0\", \"granularity\": \"day\", \"date\": \"2026-11-09\", \"nameParts\": []},
    {\"type\": \"journalPart\", \"id\": \"d1\", \"granularity\": \"day\", \"date\": \"2026-11-10\", \"nameParts\": [], \"children\": [
     {\"type\": \"node\", \"id\": \"n1\", \"nameParts\": [{\"type\": \"text\", \"text\": \"plain \"}, {\"type\": \"text\", \"text\": \"bold\", \"formats\": [\"bold\"]}], \"children\": [
      {\"type\": \"node\", \"id\": \"n2\", \"isDone\": true, \"nameParts\": [{\"type\": \"text\", \"text\": \"done child\"}]},
      {\"type\": \"node\", \"id\": \"n3\", \"nameParts\": [{\"type\": \"text\", \"text\": \"see \"}, {\"type\": \"node\", \"nodeId\": \"c1\"}, {\"type\": \"text\", \"text\": \" and \"}, {\"type\": \"node\", \"nodeId\": \"s1\"}]}]},
     {\"type\": \"node\", \"id\": \"c1\", \"isDone\": false, \"nameParts\": [{\"type\": \"text\", \"text\": \"Stats class\"}],
      \"tags\": [{\"type\": \"supertag\", \"id\": \"tc\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Lesson\"}]}],
      \"children\": [
       {\"type\": \"field\", \"id\": \"f1\", \"field\": {\"type\": \"fieldDefinition\", \"id\": \"fd1\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Status\"}], \"dataType\": \"options\"},
        \"values\": [{\"type\": \"node\", \"id\": \"o1\", \"isRef\": true, \"nameParts\": [{\"type\": \"text\", \"text\": \"Ready\"}]}]},
       {\"type\": \"field\", \"id\": \"f2\", \"field\": {\"type\": \"fieldDefinition\", \"id\": \"fd2\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Due\"}], \"dataType\": \"date\"},
        \"values\": [{\"type\": \"node\", \"id\": \"v2\", \"nameParts\": [{\"type\": \"date\", \"date\": \"2026-03-16T16:30[Asia/Shanghai]/2026-03-16T18:10[Asia/Shanghai]\"}]}]},
       {\"type\": \"field\", \"id\": \"f3\", \"field\": {\"type\": \"fieldDefinition\", \"id\": \"fd3\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Page\"}], \"dataType\": \"url\"},
        \"values\": [{\"type\": \"node\", \"id\": \"v3\", \"nameParts\": [{\"type\": \"text\", \"text\": \"https://app.notion.com/p/0123456789abcdef0123456789abcdef\"}]}]},
       {\"type\": \"node\", \"id\": \"n4\", \"nameParts\": [{\"type\": \"text\", \"text\": \"read \"}, {\"type\": \"link\", \"url\": \"https://example.org\", \"text\": \"this\"}]}]},
     {\"type\": \"node\", \"id\": \"s1\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Client K\"}],
      \"tags\": [{\"type\": \"supertag\", \"id\": \"ts\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Session\"}]}],
      \"children\": [{\"type\": \"node\", \"id\": \"n5\", \"nameParts\": [{\"type\": \"text\", \"text\": \"confidential words\"}]}]}]}]}]},
  {\"type\": \"node\", \"id\": \"p1\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Work hub\"}], \"children\": [
   {\"type\": \"node\", \"id\": \"c1\", \"isRef\": true, \"nameParts\": [{\"type\": \"text\", \"text\": \"Stats class\"}]},
   {\"type\": \"search\", \"id\": \"q1\", \"nameParts\": [{\"type\": \"text\", \"text\": \"Open tasks\"}]}]},
  {\"type\": \"node\", \"id\": \"e1\", \"nameParts\": [{\"type\": \"text\", \"text\": \"-----\"}]}]},
 \"library\": {\"type\": \"node\", \"id\": \"L\", \"nameParts\": [], \"children\": []},
 \"schema\": {\"type\": \"node\", \"id\": \"S\", \"nameParts\": [], \"children\": []},
 \"inbox\": {\"type\": \"node\", \"id\": \"I\", \"nameParts\": []}}}"
  "A small Tana export: one day, a typed node, a private node, a page.")

(defun my/test-import--tana-node (key)
  "Return the index record imported from the Tana node KEY."
  (cl-find key (my/index-records)
           :key (lambda (r) (cdr (assoc "TANA_ID" (plist-get r :props))))
           :test #'equal))

(ert-deftest my/tana-dates-are-normalised ()
  (should (equal (my/tana--date "2026-11-10") "2026-11-10"))
  (should (equal (my/tana--date
                  "2026-03-16T16:30[Asia/Shanghai]/2026-03-16T18:10[Asia/Shanghai]")
                 "2026-03-16 16:30--2026-03-16 18:10"))
  (should (equal (my/tana--date "2026-W43") "2026-W43"))
  (should (equal (my/tana--org-tag "Task (old)") "Task_old")))

(ert-deftest my/tana-import-plan-changes-nothing ()
  (my/test-import--with-library
    (let* ((file (expand-file-name "tana.json" root))
           (_ (my/test-import--write file my/test-import--tana))
           (plan (my/tana-import-plan
                  file :routes '(("tag/Session" . "private/sessions")
                                 ("*" . "inbox/notion")))))
      ;; One day, the class, the session, the hub; the empty day and the
      ;; childless top-level node are nothing.
      (should (= (plist-get plan :new) 4))
      (should (= (plist-get plan :daily) 1))
      (should (= (plist-get plan :new-private) 1))
      (should (equal (mapcar (lambda (tag) (plist-get tag :name))
                             (plist-get plan :tags))
                     '("Lesson" "Session")))
      ;; A supertag gets the type of the same name.
      (should (equal (plist-get (car (plist-get plan :tags)) :type) "Lesson"))
      (should-not (my/index-records))
      (should-not (file-directory-p my/private-dir))
      (should-not (file-directory-p my/snapshot-dir)))
    (should-error (my/tana-import-plan (expand-file-name "export" root))
                  :type 'user-error)
    (my/test-import--write (expand-file-name "bad.json" root) "[1, 2]")
    (should-error (my/tana-import-plan (expand-file-name "bad.json" root))
                  :type 'user-error)))

(ert-deftest my/tana-import-writes-days-notes-and-private-notes ()
  (my/test-import--with-library
    (my/notion-import export)
    (let* ((file (expand-file-name "tana.json" root))
           (_ (my/test-import--write file my/test-import--tana))
           (routes '(("tag/Session" . "private/sessions")))
           (result (my/tana-import file :routes routes))
           (class (my/test-import--tana-node "c1"))
           (hub (my/test-import--tana-node "p1"))
           (day (my/test-import--tana-node "d1"))
           (home (my/test-import--node my/test-import--a))
           (daily (my/test-import--slurp
                   (expand-file-name "daily/2026-11-10.org" my/inbox-dir)))
           (props (plist-get class :props)))
      (should (= (plist-get result :created) 3))
      (should (= (plist-get result :daily) 1))
      (should (= (plist-get result :private) 1))
      ;; The day is a heading in the Daily file.
      (should (string-prefix-p "#+title: 2026-11-10\n#+filetags: :daily:\n" daily))
      (should (string-match-p "^\\* Tana$" daily))
      (should (equal (plist-get day :title) "Tana"))
      (should (string-match-p "^- plain \\*bold\\*$" daily))
      (should (string-match-p "^  - \\[X\\] done child$" daily))
      (should (string-match-p
               (regexp-quote (format "- [ ] [[id:%s][Stats class]]"
                                     (plist-get class :id)))
               daily))
      ;; Neither the link nor the title of the private note is in the library.
      (should (string-match-p
               (regexp-quote (format "  - see [[id:%s][Stats class]] and (private note)"
                                     (plist-get class :id)))
               daily))
      (should (string-match-p "^- (private note)$" daily))
      (should-not (string-match-p "Client K" daily))
      (should (>= (plist-get result :withheld) 2))
      ;; The typed node: fields are properties, the rest is the body.
      (should (equal (plist-get class :file)
                     (expand-file-name "tana/Lesson/stats_class.org" my/inbox-dir)))
      (should (member "lesson" (plist-get class :tags)))
      (should (equal (cdr (assoc "STATUS" props)) "Ready"))
      (should (equal (cdr (assoc "DUE" props)) "2026-03-16 16:30--2026-03-16 18:10"))
      (should (equal (cdr (assoc "TANA_DONE" props)) "no"))
      (should (assoc "TEACHER" props))
      ;; The address of an imported Notion page is a link to its note.
      (should (equal (cdr (assoc "PAGE" props))
                     (format "[[id:%s][Notion page]]" (plist-get home :id))))
      (should (string-match-p "^- read \\[\\[https://example.org\\]\\[this\\]\\]$"
                              (my/test-import--slurp (plist-get class :file))))
      ;; The page: a reference and a search.
      (let ((text (my/test-import--slurp (plist-get hub :file))))
        (should (string-match-p
                 (regexp-quote (format "- [[id:%s][Stats class]]" (plist-get class :id)))
                 text))
        (should (string-match-p "^- (Tana search) Open tasks$" text)))
      ;; The private note is in the zone only.
      (should-not (my/test-import--tana-node "s1"))
      (should-not (my/index-search "confidential"))
      (let ((session (expand-file-name "sessions/client_k.org" my/private-dir)))
        (should (string-match-p "^- confidential words$"
                                (my/test-import--slurp session)))
        (should (= (file-modes session) #o600)))
      ;; A second run adds nothing, to notes or to the Daily file.
      (let ((again (my/tana-import file :routes routes)))
        (should (= (plist-get again :created) 0))
        (should (= (plist-get again :daily) 0))
        (should (= (plist-get again :skipped) 4)))
      (should (equal daily
                     (my/test-import--slurp
                      (expand-file-name "daily/2026-11-10.org" my/inbox-dir)))))))


(provide 'test-init-import)
;;; test-init-import.el ends here
