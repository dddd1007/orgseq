;;; test-init-nodes.el --- Tests for node types, fields, and queries -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar my/types-file)
(defvar my/node-types)

(load-file
 (expand-file-name "../modules/notes/init-nodes.el"
                   (file-name-directory load-file-name)))

(defconst my/test-nodes--types
  "#+title: Node types

* Reading
:PROPERTIES:
:TYPE_TAG:    reading
:TYPE_KEY:    r
:TYPE_FIELDS: AUTHORS YEAR status topic:node
:STATUS_ALL:  queued \"in progress\" read
:END:
** Summary
%?
** TODO Follow up

* Person Card
:PROPERTIES:
:TYPE_FIELDS: ROLE
:END:
")

(defun my/test-nodes--parse (text)
  "Parse TEXT as a type registry."
  (with-temp-buffer
    (insert text)
    (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
    (my/node-types-parse-buffer)))

(ert-deftest my/node-types-parse-fields-choices-and-template ()
  (let* ((types (my/test-nodes--parse my/test-nodes--types))
         (reading (car types)))
    (should (= (length types) 2))
    (should (equal (my/node-type-tag reading) "reading"))
    (should (equal (my/node-type-key reading) "r"))
    (should (equal (mapcar (lambda (f) (plist-get f :name)) (my/node-type-fields reading))
                   '("AUTHORS" "YEAR" "STATUS" "TOPIC")))
    (should (eq (plist-get (nth 3 (my/node-type-fields reading)) :kind) 'node))
    (should (equal (cdr (assoc "STATUS" (my/node-type-choices reading)))
                   '("queued" "in progress" "read")))
    ;; Template headings move up one level; body text is preserved.
    (should (string-prefix-p "* Summary\n%?\n* TODO Follow up"
                             (my/node-type-template reading)))))

(ert-deftest my/node-types-derive-tag-from-name ()
  (let ((person (cadr (my/test-nodes--parse my/test-nodes--types))))
    (should (equal (my/node-type-tag person) "person_card"))
    (should (equal (my/node-type-template person) ""))))

(ert-deftest my/node-type-capture-templates-target-capture-with-tag ()
  (let* ((my/node-types (my/test-nodes--parse my/test-nodes--types))
         (templates (my/node-type-capture-templates)))
    (should (equal (car templates) '("t" "Typed note")))
    (should (equal (car (nth 1 templates)) "tr"))
    (should (equal (car (nth 2 templates)) "tp"))
    (should (string-match-p ":reading:"
                            (nth 2 (plist-get (nthcdr 4 (nth 1 templates)) :target))))))

(ert-deftest my/node-set-type-on-file-node-adds-filetags-and-fields ()
  (let ((my/node-types (my/test-nodes--parse my/test-nodes--types)))
    (with-temp-buffer
      (insert ":PROPERTIES:\n:ID:       abc\n:END:\n#+title: A book\n\nBody\n")
      (org-mode)
      (goto-char (point-max))
      (my/node-set-type (car my/node-types))
      (should (equal (my/node--file-tags) '("reading")))
      (should (equal (org-entry-get (point-min) "AUTHORS") ""))
      ;; Applying again is idempotent.
      (my/node-set-type (car my/node-types))
      (should (= 1 (how-many "^#\\+filetags:" (point-min) (point-max))))
      (my/node--set-tags-at (my/node-position) nil)
      (should-not (my/node--file-tags)))))

(ert-deftest my/node-position-finds-nearest-heading-with-id ()
  (with-temp-buffer
    (insert "#+title: File\n* Parent\n:PROPERTIES:\n:ID: p1\n:END:\n** Child\ntext\n")
    (org-mode)
    (goto-char (point-max))
    (should (equal (org-entry-get (my/node-position) "ID") "p1"))
    (my/node-position t)
    (should (equal (org-entry-get (my/node-position) "ID") "p1"))))

(ert-deftest my/node-position-creates-heading-id-when-asked ()
  (let* ((dir (make-temp-file "org-seq-nodes-" t))
         (file (expand-file-name "note.org" dir))
         (org-id-locations-file (expand-file-name "ids" dir))
         (org-id-track-globally nil))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "#+title: File\n* Lonely\ntext\n")
          (goto-char (point-max))
          (should-not (my/node-position))
          (let ((pos (my/node-position t)))
            (should (org-entry-get pos "ID"))
            (should (equal "Lonely"
                           (save-excursion (goto-char pos)
                                           (org-get-heading t t t t)))))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-directory dir t))))

(ert-deftest my/node-translate-supertag-query-subset ()
  (should (equal (my/node--translate-supertag-query '(tag "reading"))
                 '(:tag "reading")))
  (should (equal (my/node--translate-supertag-query
                  '(and (tag "reading") (property "book_status" "queued")
                        (recent-days 7)))
                 '(:tag "reading" :recent-days 7
                   :where (("BOOK_STATUS" "queued")))))
  (should-error (my/node--translate-supertag-query '(similar "x"))
                :type 'user-error))

(ert-deftest my/node-value-order-is-numeric-when-possible ()
  (should (my/node--value< "9" "10"))
  (should (my/node--value< "apple" "banana")))

;;; Named templates, formulas and view settings

(defconst my/test-nodes--rich-types
  "* Paper
:PROPERTIES:
:TYPE_KEY:    r
:TYPE_FIELDS: YEAR:number LABELS:multi SITE:url
:LABELS_ALL:  method theory
:FORMULA_AGE: (- 2026 YEAR)
:FORMULA_CITED: (count <-paper)
:TYPE_VIEW_LAYOUT: board
:TYPE_VIEW_GROUP: LABELS
:END:
Intro line
** Summary
%?
** Template: Review
:PROPERTIES:
:TYPE_FIELDS: IGNORED
:END:
*** Claim
%?
*** Verdict
** Notes
** Template: Quick
One line.

* Preprint
:PROPERTIES:
:TYPE_KEY:     r
:TYPE_EXTENDS: Paper
:TYPE_FIELDS:  SERVER
:FORMULA_AGE:  (- 2027 YEAR)
:END:
")

(ert-deftest my/node-types-parse-named-templates-apart-from-the-default ()
  (let* ((types (my/test-nodes--parse my/test-nodes--rich-types))
         (paper (car types)))
    ;; Template children are not types and add no fields.
    (should (= (length types) 2))
    (should (equal (mapcar (lambda (f) (plist-get f :name)) (my/node-type-fields paper))
                   '("YEAR" "LABELS" "SITE")))
    (should (equal (mapcar (lambda (f) (plist-get f :kind)) (my/node-type-fields paper))
                   '(number multi url)))
    ;; The default template keeps everything but the named templates.
    (should (equal (my/node-type-template paper)
                   "Intro line\n* Summary\n%?\n* Notes"))
    (should (equal (my/node-type-templates paper)
                   '(("Review" . "* Claim\n%?\n* Verdict")
                     ("Quick" . "One line."))))
    (should (equal (my/node-type-template-body paper "Review") "* Claim\n%?\n* Verdict"))
    (should (equal (my/node-type-template-body paper) (my/node-type-template paper)))
    (should-error (my/node-type-template-body paper "Missing") :type 'user-error)
    ;; Old registries parse exactly as before.
    (let ((reading (car (my/test-nodes--parse my/test-nodes--types))))
      (should-not (my/node-type-templates reading))
      (should-not (my/node-type-formulas reading))
      (should-not (my/node-type-view reading)))))

(ert-deftest my/node-types-parse-formulas-views-and-inherit-formulas ()
  (let* ((types (my/test-nodes--parse my/test-nodes--rich-types))
         (paper (car types))
         (preprint (cadr types)))
    (should (equal (my/node-type-formulas paper)
                   '((:name "AGE" :kind formula :expr "(- 2026 YEAR)")
                     (:name "CITED" :kind formula :expr "(count <-paper)"))))
    (should (equal (my/node-type-view paper)
                   '(("LAYOUT" . "board") ("GROUP" . "LABELS"))))
    (should (equal (my/node-type-column-names paper)
                   '("YEAR" "LABELS" "SITE" "AGE" "CITED")))
    ;; The child inherits fields and formulas and overrides AGE; templates
    ;; and view settings stay with the parent.
    (should (equal (my/node-type-column-names preprint)
                   '("YEAR" "LABELS" "SITE" "SERVER" "CITED" "AGE")))
    (should (equal (plist-get (my/node-type-formula preprint "age") :expr)
                   "(- 2027 YEAR)"))
    (should-not (my/node-type-templates preprint))
    (should-not (my/node-type-view preprint))))

(ert-deftest my/node-capture-templates-list-named-templates-after-the-default ()
  (let* ((my/node-types (my/test-nodes--parse my/test-nodes--rich-types))
         (templates (cdr (my/node-type-capture-templates))))
    ;; Both types use TYPE_KEY r: default keys are given out first, so the
    ;; second type keeps the key it had before named templates existed.
    (should (equal (mapcar (lambda (tp) (list (car tp) (cadr tp))) templates)
                   '(("tr" "Paper") ("tr3" "Paper / Review") ("tr4" "Paper / Quick")
                     ("tr2" "Preprint"))))
    (should (equal (nth 3 (my/node--type-capture-template (car my/node-types) "Review"))
                   "* Claim\n%?\n* Verdict"))
    (should (equal (car (my/node--type-capture-template (car my/node-types))) "tr"))
    (should (equal (car (my/node--type-capture-template (car my/node-types) 'default))
                   "tr"))
    (should-error (my/node--type-capture-template (car my/node-types) "Nope")
                  :type 'user-error)))

(ert-deftest my/node-capture-selects-a-named-template ()
  (let ((my/node-types (my/test-nodes--parse my/test-nodes--rich-types))
        used)
    (cl-letf (((symbol-function 'my/note-capture)
               (lambda (title template &optional fields _no-visit)
                 (push (list title (cadr template) fields) used)
                 (list :id "x" :title title))))
      (my/node-capture (car my/node-types) "A" nil "Quick")
      ;; A batch caller without a template name gets the default, unasked.
      (my/node-capture (car my/node-types) "B" '(("YEAR" . "2001")))
      (should (equal (nreverse used)
                     '(("A" "Paper / Quick" nil)
                       ("B" "Paper" (("YEAR" . "2001")))))))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt choices &rest _)
                 (should (equal choices '("(default)" "Review" "Quick")))
                 "Review")))
      (should (equal (my/node-read-template (car my/node-types)) "Review")))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "(default)")))
      (should (eq (my/node-read-template (car my/node-types)) 'default)))
    ;; A type without named templates never asks.
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (error "Should not ask"))))
      (should (eq (my/node-read-template (cadr my/node-types)) 'default)))))

(ert-deftest my/node-split-multi-reads-comma-and-space-forms ()
  (should (equal (my/node-split-multi "red, green") '("red" "green")))
  (should (equal (my/node-split-multi "red green") '("red" "green")))
  (should (equal (my/node-split-multi "\"light blue\" red") '("light blue" "red")))
  (should (equal (my/node-split-multi "single") '("single"))))

(defmacro my/test-nodes--with-library (&rest body)
  "Run BODY in a temporary library with its own index; binds `root'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "org-seq-file-" t)))
          (my/note-home (expand-file-name "library/" root))
          (my/inbox-dir (expand-file-name "00_Inbox/" my/note-home))
          (my/outputs-dir (expand-file-name "10_Outputs/" my/note-home))
          (my/practice-dir (expand-file-name "20_Practice/" my/note-home))
          (my/library-dir (expand-file-name "30_Library/" my/note-home))
          (my/archives-dir (expand-file-name "40_Archives/" my/note-home))
          (my/ai-dir (expand-file-name "50_AI/" my/note-home))
          (my/index-file (expand-file-name "index.db" root))
          (my/index-sync-interval 0)
          (my/node-types (my/test-nodes--parse my/test-nodes--types))
          (org-inhibit-startup t)
          (inhibit-message t))
     (unwind-protect
         (progn (make-directory (expand-file-name "daily/" my/inbox-dir) t)
                ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (string-prefix-p root (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (my/index-close)
       (delete-directory root t))))

(defun my/test-nodes--slurp (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest my/node-file-into-moves-a-note-file-and-keeps-its-id ()
  (my/test-nodes--with-library
    (let ((note (my/note-create :title "Working memory" :id "wm-1"
                                :body "Text.\n")))
      (should (eq 'inbox (plist-get (my/index-node "wm-1") :layer)))
      (let* ((result (my/node-file-into "wm-1" "resource" "reading"))
             (file (plist-get result :file)))
        (should (string-prefix-p my/library-dir file))
        (should-not (file-exists-p (plist-get note :file)))
        (let ((record (my/index-node "wm-1")))
          (should (equal (plist-get record :file) file))
          (should (eq 'resource (plist-get record :layer)))
          (should (member "reading" (plist-get record :tags))))
        (should (string-match-p "^:STATUS:" (my/test-nodes--slurp file)))
        (should (string-match-p "Text\\." (my/test-nodes--slurp file)))))))

(ert-deftest my/node-file-into-uses-a-folder-inside-the-layer ()
  (my/test-nodes--with-library
    (my/note-create :title "Plan" :id "p-1")
    (let ((file (plist-get (my/node-file-into "p-1" 'project nil "grant-2027")
                           :file)))
      (should (string-prefix-p (expand-file-name "grant-2027/" my/outputs-dir)
                               file)))
    (should-error (my/node-file-into "p-1" 'project nil "../../outside"))
    (should-error (my/node-file-into "p-1" "nowhere"))))

(ert-deftest my/node-file-into-gives-a-heading-its-own-file-and-leaves-a-link ()
  (my/test-nodes--with-library
    (let ((daily (expand-file-name "daily/2026-11-13.org" my/inbox-dir)))
      (with-temp-file daily
        (insert ":PROPERTIES:\n:ID: day-1\n:END:\n#+title: 2026-11-13\n\n"
                "* Before\n"
                "* Prediction error idea :draft:\n"
                ":PROPERTIES:\n:ID: idea-1\n:SOURCE: lecture\n:END:\n"
                "First thought.\n"
                "** Detail\nMore.\n"
                "* After\n"))
      (my/index-sync 'check)
      (let* ((result (my/node-file-into "idea-1" "area" nil "research"))
             (file (plist-get result :file))
             (text (my/test-nodes--slurp file))
             (left (my/test-nodes--slurp daily)))
        (should (string-prefix-p (expand-file-name "research/" my/practice-dir)
                                 file))
        (should (string-match-p "^#\\+title: Prediction error idea$" text))
        (should (string-match-p "^:SOURCE: lecture$" text))
        (should (string-match-p "^#\\+filetags: :draft:$" text))
        (should (string-match-p "^First thought\\.$" text))
        (should (string-match-p "^\\* Detail$" text))
        ;; The Daily keeps its shape and points at the node.
        (should (string-match-p
                 "^\\* Before\n\\* \\[\\[id:idea-1\\]\\[Prediction error idea\\]\\]\n\\* After"
                 left))
        (should-not (string-match-p "First thought" left))
        ;; One node with that id, now in the area layer.
        (should (= 1 (cl-count "idea-1" (my/index-records)
                               :key (lambda (r) (plist-get r :id))
                               :test #'equal)))
        (should (eq 'area (plist-get (my/index-node "idea-1") :layer)))
        (should (member '("day-1" "idea-1") (my/index-links)))))))

(ert-deftest my/node-file-into-refuses-a-task-heading ()
  (my/test-nodes--with-library
    (let ((daily (expand-file-name "daily/2026-11-13.org" my/inbox-dir)))
      (with-temp-file daily
        (insert "#+title: day\n\n* TODO Call\n:PROPERTIES:\n:ID: task-1\n:END:\n"))
      (my/index-sync 'check)
      (should-error (my/node-file-into "task-1" "project"))
      (should (string-match-p "TODO Call" (my/test-nodes--slurp daily))))))

(ert-deftest my/node-type-layer-places-new-notes-of-the-type ()
  (my/test-nodes--with-library
    (let* ((my/node-types
            (my/test-nodes--parse
             "* Memory\n:PROPERTIES:\n:TYPE_LAYER: ai\n:TYPE_FIELDS: KIND\n:END:\n%?\n\n* Plain\n\n* Odd\n:PROPERTIES:\n:TYPE_LAYER: nowhere\n:END:\n"))
           (memory (car my/node-types))
           (warning-minimum-log-level :emergency))
      (should (equal (my/node-type-dir memory) (file-name-as-directory my/ai-dir)))
      (should-not (my/node-type-dir (nth 1 my/node-types)))
      (should-not (my/node-type-dir (nth 2 my/node-types)))
      (let ((target (cadr (plist-get (nthcdr 4 (my/node--capture-entry
                                                "tm" "Memory" memory ""))
                                     :target))))
        (should (string-prefix-p (file-name-as-directory my/ai-dir) target)))
      (should (string-prefix-p
               "capture/"
               (cadr (plist-get (nthcdr 4 (my/node--capture-entry
                                           "tp" "Plain" (nth 1 my/node-types) ""))
                                :target)))))))

;;; test-init-nodes.el ends here
