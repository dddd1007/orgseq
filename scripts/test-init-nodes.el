;;; test-init-nodes.el --- Tests for node types, fields, and queries -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar my/types-file)
(defvar my/node-types)

(load-file
 (expand-file-name "../lisp/init-nodes.el"
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

;;; test-init-nodes.el ends here
