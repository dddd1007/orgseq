;;; test-init-views.el --- Tests for saved views -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar my/types-file)
(defvar my/views-file)
(defvar my/node-types)
(defvar my/view--ctx)

(let ((dir (file-name-directory load-file-name)))
  (load-file (expand-file-name "../modules/notes/init-nodes.el" dir))
  (load-file (expand-file-name "../modules/notes/init-views.el" dir)))

(defconst my/test-views--types
  "* Work
:PROPERTIES:
:TYPE_FIELDS: STATUS AREA:node
:STATUS_ALL:  queued doing done
:END:

* Reading
:PROPERTIES:
:TYPE_EXTENDS: Work
:TYPE_FIELDS:  YEAR:number
:END:

* Area
:PROPERTIES:
:TYPE_FIELDS: OWNER
:END:
")

(defun my/test-views--types ()
  "Return the parsed test type registry."
  (with-temp-buffer
    (insert my/test-views--types)
    (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
    (my/node-types-parse-buffer)))

(defun my/test-views--records ()
  "Return a small fixed library."
  (list
   (list :id "a1" :title "Stats" :tags '("area") :file "/lib/a.org" :level 0
         :mtime (current-time) :props '(("OWNER" . "Kai")))
   (list :id "r1" :title "Old paper" :tags '("reading") :file "/lib/r1.org"
         :level 0 :mtime (time-subtract nil (days-to-time 30))
         :props '(("YEAR" . "1999") ("STATUS" . "done")
                  ("AREA" . "[[id:a1][Stats]]")))
   (list :id "r2" :title "New paper" :tags '("reading" "draft")
         :file "/lib/r2.org" :level 0 :mtime (current-time) :todo "NEXT"
         :props '(("YEAR" . "2024") ("STATUS" . "queued")))
   (list :id "w1" :title "Plain work" :tags '("work") :file "/lib/a.org"
         :level 1 :olp nil :mtime (current-time)
         :props '(("STATUS" . "doing")))))

(defmacro my/test-views--with (&rest body)
  "Run BODY with test types and a context over the test records."
  (declare (indent 0))
  `(let* ((my/node-types (my/test-views--types))
          (links (cons (make-hash-table :test 'equal)
                       (make-hash-table :test 'equal)))
          (my/view--ctx (my/view--make-ctx (my/test-views--records) "a1" links)))
     (puthash "a1" '("r1") (car links))
     (puthash "r1" '("a1") (cdr links))
     ,@body))

(defun my/test-views--ids (form)
  "Return the ids of test records matching filter FORM."
  (let ((pred (my/view--compile form)))
    (mapcar (lambda (r) (plist-get r :id))
            (cl-remove-if-not pred (plist-get my/view--ctx :records)))))

(ert-deftest my/node-types-inherit-fields-and-choices ()
  (let* ((types (my/test-views--types))
         (reading (cadr types)))
    (should (equal (mapcar (lambda (f) (plist-get f :name))
                           (my/node-type-fields reading))
                   '("STATUS" "AREA" "YEAR")))
    (should (eq (plist-get (nth 2 (my/node-type-fields reading)) :kind) 'number))
    (should (equal (cdr (assoc "STATUS" (my/node-type-choices reading)))
                   '("queued" "doing" "done")))
    (let ((my/node-types types))
      (should (equal (my/node-type-family-tags "work") '("work" "reading")))
      (should (equal (my/node-type-family-tags "reading") '("reading"))))))

(ert-deftest my/node-set-type-replaces-when-asked ()
  (let ((my/node-types (my/test-views--types)))
    (with-temp-buffer
      (insert ":PROPERTIES:\n:ID:       abc\n:END:\n#+title: T\n#+filetags: :area:keep:\n")
      (org-mode)
      (my/node-set-type (car my/node-types) 'replace)
      (should (equal (my/node--file-tags) '("keep" "work")))
      (my/node-set-type (nth 2 my/node-types) 'keep)
      (should (equal (my/node--file-tags) '("keep" "work" "area"))))))

(ert-deftest my/view-filters-cover-type-field-link-and-logic ()
  (my/test-views--with
    (should (equal (my/test-views--ids '(type "work")) '("r1" "r2" "w1")))
    (should (equal (my/test-views--ids '(tag "work")) '("w1")))
    (should (equal (my/test-views--ids '(field "YEAR" > 2000)) '("r2")))
    (should (equal (my/test-views--ids '(field "STATUS" "done")) '("r1")))
    (should (equal (my/test-views--ids '(field "AREA" = current)) '("r1")))
    (should (equal (my/test-views--ids '(field "AREA.OWNER" contains "kai"))
                   '("r1")))
    (should (equal (my/test-views--ids '(and (type "reading")
                                             (not (tag "draft"))))
                   '("r1")))
    (should (equal (my/test-views--ids '(or (todo) (field "OWNER" set)))
                   '("a1" "r2")))
    (should (equal (my/test-views--ids '(links-to current)) '("r1")))
    (should (equal (my/test-views--ids '(linked-from "r1")) '("a1")))
    (should (equal (my/test-views--ids '(under "a1")) '("w1")))
    (should (equal (my/test-views--ids '(and (type "reading")
                                             (modified-within 7)))
                   '("r2")))
    (should (equal (my/test-views--ids '(title "PAPER")) '("r1" "r2")))
    (should-error (my/view--compile '(nonsense 1)) :type 'user-error)))

(ert-deftest my/view-values-follow-paths-and-reverse-relations ()
  (my/test-views--with
    (let ((r1 (my/view--record "r1"))
          (a1 (my/view--record "a1")))
      (should (equal (my/view-value r1 "AREA") "Stats"))
      (should (equal (my/view-value r1 "AREA.OWNER") "Kai"))
      (should (equal (my/view-value a1 "<-reading") "Old paper"))
      (should (equal (my/view-value a1 "@in") "1"))
      (should (equal (my/view-value r1 "@out") "1")))))

(ert-deftest my/view-run-sorts-groups-and-limits ()
  (my/test-views--with
    (let* ((view (list :name "t" :type "work" :layout 'board :group "STATUS"
                       :sort (my/view--parse-sort "YEAR desc")))
           (result (my/view-run view)))
      ;; Declared choices keep their order, including the empty-safe ones.
      (should (equal (mapcar #'car (plist-get result :groups))
                     '("queued" "doing" "done")))
      (should (equal (plist-get result :columns) '("STATUS" "AREA")))
      (should (= (plist-get result :count) 3)))
    (let ((result (my/view-run (list :name "t" :type "reading"
                                     :sort '(("YEAR" . nil)) :limit 1))))
      (should (equal (mapcar (lambda (r) (plist-get r :id))
                             (cdar (plist-get result :groups)))
                     '("r1"))))))

(ert-deftest my/view-layouts-render-every-node ()
  (my/test-views--with
    (dolist (layout '(table list board))
      (let ((view (list :name "t" :type "work" :layout layout :group "STATUS"
                        :columns '("YEAR"))))
        (with-temp-buffer
          (my/view--render view (my/view-run view))
          (dolist (title '("Old paper" "New paper" "Plain work"))
            (should (string-match-p title (buffer-string))))
          (goto-char (point-min))
          (search-forward "New paper")
          (should (equal (get-text-property (1- (point)) 'my/view-id) "r2"))
          (should (equal (get-text-property (1- (point)) 'my/view-group)
                         "queued")))))))

(ert-deftest my/view-board-lists-columns-left-to-right ()
  (my/test-views--with
    (let ((view (list :name "t" :type "work" :layout 'board :group "STATUS")))
      (with-temp-buffer
        (my/view--render view (my/view-run view))
        (should (equal (my/view--group-order-in-buffer)
                       '("queued" "doing" "done")))))))

(ert-deftest my/view-definitions-round-trip-through-org ()
  (let* ((dir (make-temp-file "org-seq-views-" t))
         (my/views-file (expand-file-name "views.org" dir))
         (view (list :name "Recent reading" :type "reading" :layout 'board
                     :group "STATUS" :columns '("YEAR" "AREA.OWNER")
                     :sort '(("YEAR" . t) ("@title" . nil))
                     :filter '(and (field "YEAR" > 2000) (not (tag "draft")))
                     :limit 50)))
    (unwind-protect
        (progn
          (my/view-save-definition view)
          (let ((loaded (my/view-by-name "Recent reading")))
            (dolist (key '(:name :type :layout :group :columns :sort :filter
                           :limit))
              (should (equal (plist-get loaded key) (plist-get view key)))))
          ;; The starter view survives, and saving again replaces in place.
          (should (my/view-by-name "Reading board"))
          (my/view-save-definition (plist-put (copy-sequence view) :layout 'list))
          (should (= 2 (length (my/views-load))))
          (should (eq 'list (plist-get (my/view-by-name "Recent reading")
                                       :layout))))
      (when-let* ((buffer (get-file-buffer my/views-file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory dir t))))

(ert-deftest my/view-prefill-comes-from-equality-filters ()
  (should (equal (my/view--equality-fields
                  '(and (field "STATUS" "queued") (field "YEAR" > 2000)
                        (field "KIND" = "paper") (tag "x")))
                 '(("STATUS" . "queued") ("KIND" . "paper")))))

(ert-deftest my/view-org-output-links-nodes ()
  (my/test-views--with
    (dolist (layout '(table list board))
      (let ((view (list :name "t" :type "work" :layout layout :group "STATUS")))
        (with-temp-buffer
          (org-mode)
          (my/view--insert-org view (my/view-run view))
          (should (string-match-p "\\[\\[id:r2\\]\\[New paper\\]\\]"
                                  (buffer-string))))))))

;;; test-init-views.el ends here
