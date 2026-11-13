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

;;; Types as databases: default views, rollups, formulas, new field kinds

(defconst my/test-views--db-types
  "* Project
:PROPERTIES:
:TYPE_FIELDS: STATUS BUDGET:number LABELS:multi SITE:url MEMBERS:nodes
:STATUS_ALL:  active done
:LABELS_ALL:  red green \"light blue\"
:FORMULA_TASKS: (count <-task)
:FORMULA_HOURS: (sum <-task.HOURS)
:FORMULA_LEFT:  (- BUDGET HOURS)
:FORMULA_RATE:  (/ BUDGET TASKS)
:TYPE_VIEW_LAYOUT:  board
:TYPE_VIEW_GROUP:   STATUS
:TYPE_VIEW_SORT:    HOURS desc
:TYPE_VIEW_COLUMNS: STATUS TASKS HOURS
:END:

* Task
:PROPERTIES:
:TYPE_FIELDS: PROJECT:node HOURS:number DUE:date
:FORMULA_LATE: (if (empty DUE) \"\" (> (days (today) DUE) 0))
:END:

* Bug
:PROPERTIES:
:TYPE_EXTENDS: Task
:TYPE_FIELDS:  SEVERITY
:FORMULA_LATE: (concat \"bug \" SEVERITY)
:END:

* Person
:PROPERTIES:
:TYPE_FIELDS:  NAME
:FORMULA_LOOP: (+ LOOP 1)
:END:
")

(defun my/test-views--day (month day)
  "Return the time of 2026-MONTH-DAY at noon."
  (encode-time (list 0 0 12 day month 2026 nil -1 nil)))

(defun my/test-views--db-records ()
  "Return a library of projects, tasks, a bug and people."
  (list
   (list :id "p1" :title "Alpha" :tags '("project") :file "/lib/p1.org" :level 0
         :mtime (my/test-views--day 6 1)
         :props '(("STATUS" . "active") ("BUDGET" . "100")
                  ("LABELS" . "red, green") ("SITE" . "https://alpha.example")
                  ("MEMBERS" . "[[id:u1][Ann]] [[id:u2][Bo]]")))
   (list :id "p2" :title "Beta" :tags '("project") :file "/lib/p2.org" :level 0
         :mtime (my/test-views--day 6 2)
         :props '(("STATUS" . "done") ("BUDGET" . "50")
                  ("LABELS" . "\"light blue\" red")))
   (list :id "t1" :title "Write" :tags '("task") :file "/lib/t1.org" :level 0
         :mtime (my/test-views--day 5 1)
         :props '(("PROJECT" . "[[id:p1][Alpha]]") ("HOURS" . "3")
                  ("DUE" . "<2026-01-10 Sat>")))
   (list :id "t2" :title "Test" :tags '("task") :file "/lib/t2.org" :level 0
         :mtime (my/test-views--day 5 20)
         :props '(("PROJECT" . "[[id:p1]]") ("HOURS" . "4.5") ("DUE" . "2026-03-01")))
   (list :id "b1" :title "Crash" :tags '("bug") :file "/lib/b1.org" :level 0
         :mtime (my/test-views--day 4 1)
         :props '(("PROJECT" . "[[id:p1][Alpha]]") ("HOURS" . "2")
                  ("SEVERITY" . "high")))
   (list :id "t3" :title "Idle" :tags '("task") :file "/lib/t3.org" :level 0
         :mtime (my/test-views--day 3 1) :props '(("HOURS" . "n/a")))
   (list :id "u1" :title "Ann" :tags '("person") :file "/lib/u1.org" :level 0
         :mtime (my/test-views--day 1 1) :props '(("NAME" . "Ann A.")))
   (list :id "u2" :title "Bo" :tags '("person") :file "/lib/u2.org" :level 0
         :mtime (my/test-views--day 1 2) :props '(("NAME" . "Bo B.")))))

(defmacro my/test-views--with-db (&rest body)
  "Run BODY with the database test types and records."
  (declare (indent 0))
  `(let* ((my/node-types
           (with-temp-buffer
             (insert my/test-views--db-types)
             (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
             (my/node-types-parse-buffer)))
          (links (cons (make-hash-table :test 'equal)
                       (make-hash-table :test 'equal)))
          (my/view--ctx (my/view--make-ctx (my/test-views--db-records) nil links)))
     (puthash "p1" '("t1" "t2" "b1") (car links))
     (puthash "u1" '("p1") (car links))
     (puthash "u2" '("p1") (car links))
     (dolist (task '("t1" "t2" "b1")) (puthash task '("p1") (cdr links)))
     (puthash "p1" '("u1" "u2") (cdr links))
     ,@body))

(defun my/test-views--type (name)
  "Return the test type called NAME."
  (cl-find name my/node-types :key #'my/node-type-name :test #'equal))

(defun my/test-views--formula (id expr)
  "Evaluate formula text EXPR for record ID."
  (my/view--formula-value (my/view--record id)
                          (list :name "TEST" :kind 'formula :expr expr)))

(ert-deftest my/view-type-default-view-uses-type-settings-and-overrides ()
  (my/test-views--with-db
    (let ((project (my/test-views--type "Project"))
          (task (my/test-views--type "Task"))
          (bug (my/test-views--type "Bug")))
      (should (equal (my/view-type-default project)
                     '(:name "Project" :type "project" :layout board :filter nil
                       :sort (("HOURS" . t)) :group "STATUS"
                       :columns ("STATUS" "TASKS" "HOURS") :limit nil)))
      ;; Without settings: a table with the fields and formulas as columns.
      (let ((view (my/view-type-default task)))
        (should (eq (plist-get view :layout) 'table))
        (should (equal (my/view--columns view) '("PROJECT" "HOURS" "DUE" "LATE"))))
      ;; Inherited fields and the child's own formula override.
      (should (equal (my/view--columns (my/view-type-default bug))
                     '("PROJECT" "HOURS" "DUE" "SEVERITY" "LATE")))
      ;; The parent's view includes the subtype's nodes.
      (should (equal (mapcar (lambda (r) (plist-get r :id))
                             (cdar (plist-get (my/view-run (my/view-type-default task))
                                              :groups)))
                     '("t2" "t1" "b1" "t3")))
      ;; A saved view named after the type replaces the default.
      (let ((saved (list :name "Project" :type "project" :layout 'list)))
        (should (eq (my/view-for-type project (list (list :name "Other") saved))
                    saved))
        (should (eq (plist-get (my/view-for-type project (list (list :name "Other")))
                               :layout)
                    'board))))))

(ert-deftest my/view-type-default-view-runs-grouped-and-sorted ()
  (my/test-views--with-db
    (let ((result (my/view-run (my/view-type-default (my/test-views--type "Project")))))
      (should (equal (mapcar #'car (plist-get result :groups)) '("active" "done")))
      (should (equal (plist-get result :columns) '("STATUS" "TASKS" "HOURS")))
      ;; Sorting by a formula column works like any column.
      (let ((sorted (my/view--sort (cl-remove-if-not
                                    (lambda (r) (member "project" (plist-get r :tags)))
                                    (plist-get my/view--ctx :records))
                                   '(("HOURS" . nil)))))
        (should (equal (mapcar (lambda (r) (plist-get r :id)) sorted) '("p2" "p1")))))))

(ert-deftest my/view-rollups-over-reverse-and-forward-relations ()
  (my/test-views--with-db
    (let ((p1 (my/view--record "p1"))
          (p2 (my/view--record "p2")))
      ;; Reverse relations include subtypes (the bug is a task).
      (should (equal (my/view-value p1 "count(<-task)") "3"))
      (should (equal (my/view-value p1 "sum(<-task.HOURS)") "9.5"))
      (should (equal (my/view-value p1 "avg(<-task.HOURS)") "3.17"))
      (should (equal (my/view-value p1 "min(<-task.HOURS)") "2"))
      (should (equal (my/view-value p1 "max(<-task.HOURS)") "4.5"))
      (should (equal (my/view-value p1 "earliest(<-task.DUE)") "2026-01-10"))
      (should (equal (my/view-value p1 "latest(<-task.DUE)") "2026-03-01"))
      (should (equal (my/view-value p1 "latest(<-task.@modified)") "2026-05-20"))
      (should (equal (my/view-value p1 "list(<-task.@title)") "Write, Test, Crash"))
      (should (equal (my/view-value p1 "list(<-bug.SEVERITY)") "high"))
      (should (equal (my/view-value p1 "<-task.HOURS") "3, 4.5, 2"))
      ;; Forward relations: a NAME:nodes field holds several links.
      (should (equal (my/view-value p1 "count(MEMBERS)") "2"))
      (should (equal (my/view-value p1 "list(MEMBERS.NAME)") "Ann A., Bo B."))
      (should (equal (my/view-value (my/view--record "t1") "list(PROJECT.MEMBERS.@title)")
                     "Ann, Bo"))
      ;; Text values are skipped by numeric rollups; non-numbers make
      ;; min/max compare as text.
      (should (equal (my/view-value (my/view--record "t3") "sum(HOURS)") "0"))
      (should (equal (my/view-value (my/view--record "t3") "max(HOURS)") "n/a"))
      ;; Empty sets.
      (dolist (pair '(("count(<-task)" . "0") ("sum(<-task.HOURS)" . "0")
                      ("avg(<-task.HOURS)" . "") ("min(<-task.HOURS)" . "")
                      ("max(<-task.HOURS)" . "") ("latest(<-task.DUE)" . "")
                      ("earliest(<-task.DUE)" . "") ("list(<-task.@title)" . "")
                      ("count(MEMBERS)" . "0")))
        (should (equal (my/view-value p2 (car pair)) (cdr pair))))
      ;; An unknown function name is an ordinary (empty) field.
      (should (equal (my/view-value p1 "median(<-task.HOURS)") "")))))

(ert-deftest my/view-formulas-evaluate-and-report-errors-inline ()
  (my/test-views--with-db
    (let ((p1 (my/view--record "p1"))
          (p2 (my/view--record "p2")))
      (should (equal (my/view-value p1 "TASKS") "3"))
      (should (equal (my/view-value p1 "HOURS") "9.5"))
      (should (equal (my/view-value p1 "LEFT") "90.5"))
      (should (equal (my/view-value p1 "RATE") "33.33"))
      (should (equal (my/view-value p2 "HOURS") "0"))
      (should (equal (my/view-value p2 "LEFT") "50"))
      (should (equal (my/view-value p2 "RATE") "#ERR: division by zero"))
      ;; Formulas belong to the node's type; a child type overrides.
      (should (equal (my/view-value (my/view--record "t1") "LATE") "yes"))
      (should (equal (my/view-value (my/view--record "b1") "LATE") "bug high"))
      (should (equal (my/view-value (my/view--record "t3") "LATE") ""))
      (should (equal (my/view-value p1 "LATE") ""))
      (should (string-match-p "\\`#ERR: .*LOOP refers to itself"
                              (my/view-value (my/view--record "u1") "LOOP")))
      ;; Arithmetic, logic, text and dates.
      (should (equal (my/test-views--formula "p1" "(* (+ BUDGET 1) 2)") "202"))
      (should (equal (my/test-views--formula "p1" "(round (/ 10 3) 1)") "3.3"))
      (should (equal (my/test-views--formula "p1" "(round 2.6)") "3"))
      (should (equal (my/test-views--formula "p1" "(if (> BUDGET 60) \"big\" \"small\")")
                     "big"))
      (should (equal (my/test-views--formula "p2" "(if (> BUDGET 60) \"big\" \"small\")")
                     "small"))
      (should (equal (my/test-views--formula "p1" "(and (= STATUS \"active\") (>= BUDGET 100))")
                     "yes"))
      (should (equal (my/test-views--formula "p1" "(not (= STATUS \"active\"))") "no"))
      (should (equal (my/test-views--formula "p1" "(concat @title \" / \" STATUS)")
                     "Alpha / active"))
      (should (equal (my/test-views--formula "p1" "(contains LABELS \"GREEN\")") "yes"))
      (should (equal (my/test-views--formula "t1" "(days DUE \"2026-01-01\")") "9"))
      (should (equal (my/test-views--formula "t1" "(days \"2026-03-01\" \"2026-02-01\")")
                     "28"))
      (should (equal (my/test-views--formula "t1" "(days (today) (today))") "0"))
      (should (equal (my/test-views--formula "t1" "(> (days (today) @modified) 100)")
                     (if (> (- (time-to-days nil)
                               (time-to-days (my/test-views--day 5 1)))
                            100)
                         "yes" "no")))
      ;; Missing fields are empty: arithmetic stays empty, or gives a default.
      (should (equal (my/test-views--formula "p1" "(+ NOPE 1)") ""))
      (should (equal (my/test-views--formula "p1" "(days NOPE (today))") ""))
      (should (equal (my/test-views--formula "p1" "(or NOPE 0)") "0"))
      (should (equal (my/test-views--formula "p1" "(empty NOPE)") "yes"))
      ;; Errors never escape: they become the cell text.
      (dolist (pair '(("(frobnicate 1)" . "unknown function frobnicate")
                      ("(+ 1" . "cannot read the formula")
                      ("(+ 1 2) extra" . "cannot read the formula")
                      ("(+ STATUS 1)" . "not a number: done")
                      ("(days STATUS 1)" . "not a number\\|not a date")
                      ("(/ 1 0)" . "division by zero")
                      ("(1 2)" . "cannot evaluate")
                      ("(if)" . "if takes")
                      ("(count)" . "count takes one column")
                      ("(= 1)" . "wrong number of arguments")
                      ("(+ RATE 1)" . "RATE: division by zero")))
        (let ((value (my/test-views--formula "p2" (car pair))))
          (should (string-prefix-p "#ERR: " value))
          (should (string-match-p (cdr pair) value)))))))

(ert-deftest my/view-multi-and-nodes-fields-filter-sort-and-display ()
  (my/test-views--with-db
    (let ((p1 (my/view--record "p1"))
          (p2 (my/view--record "p2")))
      (should (equal (my/view-value p1 "LABELS") "red, green"))
      (should (equal (my/view-value p2 "LABELS") "light blue, red"))
      (should (equal (my/view-value p1 "MEMBERS") "Ann, Bo"))
      (should (equal (my/view-value p1 "SITE") "https://alpha.example"))
      (should (equal (my/test-views--ids '(field "LABELS" has "red")) '("p1" "p2")))
      (should (equal (my/test-views--ids '(field "LABELS" has "Light Blue")) '("p2")))
      (should (equal (my/test-views--ids '(field "LABELS" has "green")) '("p1")))
      (should (equal (my/test-views--ids '(field "LABELS" has "gre")) nil))
      (should (equal (my/test-views--ids '(field "MEMBERS" has "Bo")) '("p1")))
      (should (equal (my/test-views--ids '(field "MEMBERS" has "u2")) '("p1")))
      (should (equal (my/test-views--ids '(field "<-task" has "Crash")) '("p1")))
      (should (equal (my/test-views--ids '(field "count(<-task)" > 1)) '("p1")))
      (should (equal (my/test-views--ids '(and (type "task") (field "LATE" = "yes")))
                     '("t1" "t2")))
      (should (equal (mapcar (lambda (r) (plist-get r :id))
                             (my/view--sort (list p1 p2) '(("LABELS"))))
                     '("p2" "p1"))))))

(ert-deftest my/view-computed-columns-render-in-every-layout-and-org ()
  (my/test-views--with-db
    (dolist (layout '(table list board))
      (let ((view (list :name "p" :type "project" :layout layout :group "STATUS"
                        :columns '("TASKS" "RATE" "count(MEMBERS)" "LABELS" "SITE"))))
        (with-temp-buffer
          (my/view--render view (my/view-run view))
          (should (string-match-p "Alpha" (buffer-string)))
          (should (string-match-p "33.33" (buffer-string)))
          (should (string-match-p "#ERR: div" (buffer-string)))
          (should (string-match-p "red, green" (buffer-string)))
          ;; A board card may truncate its details; table and list show
          ;; the URL in full, clickable.
          (unless (eq layout 'board)
            (goto-char (point-min))
            (search-forward "https://alpha")
            (should (equal (get-text-property (1- (point)) 'my/view-url)
                           "https://alpha.example"))))
        (with-temp-buffer
          (org-mode)
          (my/view--insert-org view (my/view-run view))
          (should (string-match-p "\\[\\[id:p1\\]\\[Alpha\\]\\]" (buffer-string)))
          (unless (eq layout 'board)
            (should (string-match-p "33.33" (buffer-string)))
            (should (string-match-p "#ERR: division by zero" (buffer-string)))))))))

(ert-deftest my/view-computed-columns-are-read-only ()
  (my/test-views--with-db
    (should (my/view--computed-p "TASKS"))
    (should (my/view--computed-p "count(<-task)"))
    (should-not (my/view--computed-p "STATUS"))
    (should-not (my/view--plain-field-p "TASKS"))
    (should (my/view--plain-field-p "BUDGET"))
    (should-not (my/view--equality-fields '(field "TASKS" "3")))
    (dolist (field '("TASKS" "sum(<-task.HOURS)"))
      (with-temp-buffer
        (insert (propertize "cell" 'my/view-id "p1" 'my/view-field field))
        (goto-char (point-min))
        (cl-letf (((symbol-function 'my/node-call-at-id)
                   (lambda (&rest _) (error "Must not write"))))
          (let ((err (should-error (my/view-edit-field) :type 'user-error)))
            (should (string-match-p "computed\\|rollup" (cadr err)))))))))

(ert-deftest my/view-rollups-scale-linearly-with-the-library ()
  (let* ((my/node-types
          (with-temp-buffer
            (insert my/test-views--db-types)
            (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
            (my/node-types-parse-buffer)))
         (in (make-hash-table :test 'equal))
         (records nil))
    (dotimes (p 100)
      (push (list :id (format "p%d" p) :title (format "Project %d" p)
                  :tags '("project") :props '(("BUDGET" . "10")))
            records))
    (dotimes (n 2900)
      (let ((id (format "t%d" n))
            (project (format "p%d" (% n 100))))
        (push (list :id id :title id :tags '("task")
                    :props (list (cons "HOURS" (number-to-string (% n 7)))
                                 (cons "PROJECT" (format "[[id:%s]]" project))))
              records)
        (push id (gethash project in))))
    (let* ((my/view--ctx (my/view--make-ctx records nil
                                            (cons in (make-hash-table :test 'equal))))
           (start (float-time))
           (result (my/view-run (list :name "big" :type "project"
                                      :columns '("TASKS" "HOURS" "LEFT")
                                      :sort '(("TASKS" . t) ("@title"))))))
      (should (= (plist-get result :count) 100))
      (should (equal (my/view-value (car (cdar (plist-get result :groups))) "TASKS")
                     "29"))
      (should (< (- (float-time) start) 10)))))

(ert-deftest my/view-hides-the-archive-layer-unless-a-layer-is-named ()
  (let* ((my/node-types (my/test-views--types))
         (records
          (list (list :id "k1" :title "Kept" :tags '("reading")
                      :file "/lib/k1.org" :level 0 :layer 'resource
                      :mtime (current-time))
                (list :id "o1" :title "Old" :tags '("reading")
                      :file "/lib/o1.org" :level 0 :layer 'archive
                      :mtime (current-time))
                (list :id "i1" :title "Draft" :tags '("reading")
                      :file "/lib/i1.org" :level 0 :layer 'inbox
                      :mtime (current-time))))
         (my/view--ctx (my/view--make-ctx records nil
                                          (cons (make-hash-table :test 'equal)
                                                (make-hash-table :test 'equal))))
         (ids (lambda (view)
                (sort (mapcar (lambda (r) (plist-get r :id))
                              (apply #'append
                                     (mapcar #'cdr
                                             (plist-get (my/view-run view)
                                                        :groups))))
                      #'string<))))
    (should (equal (funcall ids '(:type "reading")) '("i1" "k1")))
    (should (equal (funcall ids '(:type "reading" :filter (layer archive)))
                   '("o1")))
    (should (equal (funcall ids '(:filter (or (layer inbox) (layer archive))))
                   '("i1" "o1")))
    (should-error (my/view--compile '(layer nowhere)))))

;;; test-init-views.el ends here
