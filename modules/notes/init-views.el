;;; init-views.el --- Saved views over nodes: table, list, board -*- lexical-binding: t; -*-
;;
;; A view is a query plus a layout (Notion database view, Tana live query).
;; It never stores note data: rows are org-roam nodes read from the index,
;; and every edit made in a view is written to the node's Org file.
;;
;;   Query    A filter expression, sort keys, an optional group field and a
;;            column list.  Filters combine type, tag, field, TODO state,
;;            time, link, hierarchy and text conditions with and/or/not.
;;   Layouts  table  one row per node, one column per field
;;            list   one compact line per node
;;            board  one column per value of the group field (kanban);
;;                   moving a card sets that field on the node
;;   Saved    One heading per view in `my/views-file' (.orgseq/views.org),
;;            so views are Org text and travel with the library.
;;   Embeds   The `orgseq-view' dynamic block renders a view inside any
;;            note; `current' in its filter means the enclosing node.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │                       Table of Contents                          │
;; ├─────────────────────────────────────────────────────────────────┤
;; │ Section 1  Records and query context                             │
;; │ Section 2  Column values                                         │
;; │ Section 3  Filter expressions                                    │
;; │ Section 4  Sorting, grouping, running a view                     │
;; │ Section 5  Saved views (.orgseq/views.org)                       │
;; │ Section 6  Rendering: table, list, board                         │
;; │ Section 7  View buffer mode and commands                         │
;; │ Section 8  Dynamic block                                         │
;; └─────────────────────────────────────────────────────────────────┘

;; Requires: init-org   (my/views-file, my/note-home)
;; Requires: init-nodes (type registry, node write path)
(defvar my/views-file)
(defvar my/note-home)
(defvar my/node-types)
(defvar org-todo-keywords)

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'orgseq-index)

(declare-function evil-set-initial-state "evil-core" (mode state))
(declare-function my/node-type-by-tag "init-nodes" (tag))
(declare-function my/node-type-family-tags "init-nodes" (tag))
(declare-function my/node-type-name "init-nodes" (type))
(declare-function my/node-type-tag "init-nodes" (type))
(declare-function my/node-type-fields "init-nodes" (type))
(declare-function my/node-type-choices "init-nodes" (type))
(declare-function my/node-types-at "init-nodes" (pos))
(declare-function my/node-read-type "init-nodes" (&optional prompt types))
(declare-function my/node-capture "init-nodes" (type title &optional fields))
(declare-function my/node-call-at-id "init-nodes" (id fn))
(declare-function my/node-visit "init-nodes" (node &optional other-window))
(declare-function my/node-set-field-at "init-nodes" (pos))
(declare-function my/node-set-field-by-id "init-nodes" (id name value))
(declare-function my/node-position "init-nodes" (&optional create))
(declare-function my/node--read-field-value "init-nodes"
                  (field-name spec types current))
(declare-function my/node--value< "init-nodes" (a b))
(declare-function my/node--display-value "init-nodes" (value))
(declare-function my/node--table-cell "init-nodes" (value))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Records and query context
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Views work on plain plists ("records") copied out of the node index once per
;; refresh, so filtering, sorting and rendering are ordinary list code that
;; can be tested without a database.

(defvar my/view--ctx nil
  "Query context while a view runs.
A plist: :records (all records), :by-id (hash id -> record), :current
\(id of the node a view is embedded in), :links (cons of hash tables
INCOMING . OUTGOING, id -> list of ids; computed on first use).")

(defun my/view--records ()
  "Return every node as a record plist from the kernel index."
  (my/index-records))

(defun my/view--make-ctx (records &optional current links)
  "Return a query context for RECORDS.
CURRENT is the id of the enclosing node; LINKS presets the link tables."
  (let ((by-id (make-hash-table :test 'equal)))
    (dolist (record records)
      (puthash (plist-get record :id) record by-id))
    (list :records records :by-id by-id :current current :links links)))

(defun my/view--links ()
  "Return (INCOMING . OUTGOING) id-link tables, loading them on first use."
  (or (plist-get my/view--ctx :links)
      (let ((in (make-hash-table :test 'equal))
            (out (make-hash-table :test 'equal)))
        (pcase-dolist (`(,source ,dest) (my/index-links))
          (push source (gethash dest in))
          (push dest (gethash source out)))
        (setq my/view--ctx
              (plist-put my/view--ctx :links (cons in out)))
        (cons in out))))

(defun my/view--record (id)
  "Return the record with ID in the current context."
  (gethash id (plist-get my/view--ctx :by-id)))

(defun my/view--resolve-target (target)
  "Return the node id named by TARGET: a string id or the symbol `current'."
  (cond
   ((eq target 'current)
    (or (plist-get my/view--ctx :current)
        (user-error "This view refers to `current'; embed it in a node")))
   (t (format "%s" target))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Column values
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; A column is a string:
;;   NAME        the field (Org property) NAME
;;   A.B         follow the node links in field A, read B on each target
;;               (multi-hop path; B may itself be a path)
;;   <-TAG       titles of TAG nodes that link to this node (the reverse
;;               side of a relation field)
;;   @title @todo @tags @modified @created @file @in @out
;;               built-in values; @in/@out count id links

(defun my/view--raw (record name)
  "Return the raw value of property NAME on RECORD, or nil."
  (cdr (assoc (upcase name) (plist-get record :props))))

(defun my/view--link-ids (value)
  "Return the node ids of all id links in VALUE."
  (let ((start 0) ids)
    (while (and value (string-match "\\[\\[id:\\([^]]+\\)\\]" value start))
      (push (match-string 1 value) ids)
      (setq start (match-end 0)))
    (nreverse ids)))

(defun my/view--created-time (record)
  "Return the creation time of RECORD, or nil when unknown.
Read from the CREATED property, else from a timestamp-style ID."
  (let ((created (my/view--raw record "CREATED"))
        (id (plist-get record :id)))
    (cond
     ((and created (not (string-empty-p created)))
      (ignore-errors (org-time-string-to-time created)))
     ((and id (string-match
               "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)"
               id))
      (encode-time (string-to-number (match-string 6 id))
                   (string-to-number (match-string 5 id))
                   (string-to-number (match-string 4 id))
                   (string-to-number (match-string 3 id))
                   (string-to-number (match-string 2 id))
                   (string-to-number (match-string 1 id)))))))

(defun my/view--age-days (time)
  "Return the age of TIME in days, or nil when TIME is nil."
  (and time (/ (float-time (time-subtract nil time)) 86400.0)))

(defun my/view-value (record column)
  "Return the display string of COLUMN for RECORD."
  (cond
   ((string-prefix-p "@" column)
    (pcase column
      ("@title" (plist-get record :title))
      ("@todo" (or (plist-get record :todo) ""))
      ("@tags" (string-join (plist-get record :tags) " "))
      ("@modified" (if-let* ((mtime (plist-get record :mtime)))
                       (format-time-string "%Y-%m-%d" mtime)
                     ""))
      ("@created" (if-let* ((time (my/view--created-time record)))
                      (format-time-string "%Y-%m-%d" time)
                    ""))
      ("@file" (if-let* ((file (plist-get record :file)))
                   (file-name-nondirectory file)
                 ""))
      ("@in" (number-to-string
              (length (gethash (plist-get record :id) (car (my/view--links))))))
      ("@out" (number-to-string
               (length (gethash (plist-get record :id) (cdr (my/view--links))))))
      (_ "")))
   ((string-prefix-p "<-" column)
    (let ((family (my/node-type-family-tags (substring column 2))))
      (mapconcat
       (lambda (record) (plist-get record :title))
       (cl-remove-if-not
        (lambda (source)
          (and source
               (cl-intersection family (plist-get source :tags) :test #'equal)))
        (mapcar #'my/view--record
                (delete-dups
                 (copy-sequence
                  (gethash (plist-get record :id) (car (my/view--links)))))))
       ", ")))
   ((string-match "\\`\\([^.]+\\)\\.\\(.+\\)\\'" column)
    (let ((rest (match-string 2 column))
          (ids (my/view--link-ids (my/view--raw record (match-string 1 column)))))
      (string-join
       (cl-remove-if
        #'string-empty-p
        (mapcar (lambda (id)
                  (if-let* ((target (my/view--record id)))
                      (my/view-value target rest)
                    ""))
                ids))
       ", ")))
   (t (my/node--display-value (my/view--raw record column)))))

(defun my/view--column-label (column)
  "Return the header label of COLUMN."
  (cond
   ((string-prefix-p "@" column) (capitalize (substring column 1)))
   (t column)))

(defun my/view--plain-field-p (column)
  "Return non-nil when COLUMN is an editable field, not a computed value."
  (and column
       (not (string-prefix-p "@" column))
       (not (string-prefix-p "<-" column))
       (not (string-match-p "\\." column))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Filter expressions
;; ═══════════════════════════════════════════════════════════════════════════
;;
;;   (type "reading")              has the type, or a type extending it
;;   (tag "draft")                 has the tag
;;   (todo) (todo "NEXT" "TODO")   has a TODO state / one of these states
;;   (field "YEAR" > 2020)         ops: = != < > <= >= contains
;;   (field "STATUS" "read")       short for =
;;   (field "TOPIC" = current)     relation field links to the enclosing node
;;   (field "TOPIC" empty|set)     value absent / present
;;   (modified-within 7)           file changed in the last 7 days
;;   (created-within 7)            created in the last 7 days
;;   (links-to ID|current)         has an id link to that node
;;   (linked-from ID|current)      that node links to it
;;   (under ID|current)            is below that node in its file
;;   (title "str") (text "str")    title contains / file text contains
;;   (and ...) (or ...) (not ...)
;;
;; Field names accept every column form of Section 2, so (field "@in" = 0)
;; and (field "TOPIC.AREA" contains "stats") work as well.

(defun my/view--text-files (string)
  "Return a hash set of files under `my/note-home' containing STRING."
  (unless (executable-find "rg")
    (user-error "Text filters need ripgrep (rg)"))
  (let ((files (make-hash-table :test 'equal)))
    (dolist (file (process-lines-ignore-status
                   "rg" "--files-with-matches" "--fixed-strings"
                   "--ignore-case" "--glob" "*.org" "--"
                   string (expand-file-name my/note-home)))
      (puthash (expand-file-name file) t files)
      (puthash (file-truename file) t files))
    files))

(defun my/view--compare (op left right)
  "Compare display strings LEFT and RIGHT with OP."
  (pcase op
    ('= (string= left right))
    ('!= (not (string= left right)))
    ('contains (string-match-p (regexp-quote (downcase right)) (downcase left)))
    ('< (my/node--value< left right))
    ('> (my/node--value< right left))
    ('<= (not (my/node--value< right left)))
    ('>= (not (my/node--value< left right)))
    (_ (user-error "Unknown field operator: %S" op))))

(defun my/view--field-predicate (name op value)
  "Return a predicate testing field NAME against VALUE with OP."
  (let ((name (format "%s" name)))
    (cond
     ((eq op 'empty)
      (lambda (record) (string-empty-p (my/view-value record name))))
     ((eq op 'set)
      (lambda (record) (not (string-empty-p (my/view-value record name)))))
     ((eq value 'current)
      (let ((needle (concat "id:" (my/view--resolve-target 'current))))
        (lambda (record)
          (let ((hit (string-search needle (or (my/view--raw record name) ""))))
            (if (eq op '!=) (not hit) hit)))))
     (t
      (let ((value (format "%s" value)))
        (lambda (record)
          (my/view--compare op (my/view-value record name) value)))))))

(defun my/view--compile (form)
  "Compile filter FORM into a predicate on records."
  (pcase form
    ('nil (lambda (_record) t))
    (`(and . ,forms)
     (let ((preds (mapcar #'my/view--compile forms)))
       (lambda (record) (cl-every (lambda (p) (funcall p record)) preds))))
    (`(or . ,forms)
     (let ((preds (mapcar #'my/view--compile forms)))
       (lambda (record) (cl-some (lambda (p) (funcall p record)) preds))))
    (`(not ,inner)
     (let ((pred (my/view--compile inner)))
       (lambda (record) (not (funcall pred record)))))
    (`(tag ,tag)
     (let ((tag (format "%s" tag)))
       (lambda (record) (member tag (plist-get record :tags)))))
    (`(type ,tag)
     (let ((family (my/node-type-family-tags (format "%s" tag))))
       (lambda (record)
         (cl-intersection family (plist-get record :tags) :test #'equal))))
    (`(todo . ,keywords)
     (lambda (record)
       (let ((todo (plist-get record :todo)))
         (if keywords (member todo keywords) todo))))
    (`(field ,name ,(and op (or 'empty 'set)))
     (my/view--field-predicate name op nil))
    (`(field ,name ,value)
     (my/view--field-predicate name '= value))
    (`(field ,name ,op ,value)
     (my/view--field-predicate name op value))
    (`(,(or 'modified-within 'recent-days) ,days)
     (lambda (record)
       (let ((age (my/view--age-days (plist-get record :mtime))))
         (and age (<= age days)))))
    (`(created-within ,days)
     (lambda (record)
       (let ((age (my/view--age-days (my/view--created-time record))))
         (and age (<= age days)))))
    (`(links-to ,target)
     (let ((id (my/view--resolve-target target)))
       (lambda (record)
         (member id (gethash (plist-get record :id) (cdr (my/view--links)))))))
    (`(linked-from ,target)
     (let ((id (my/view--resolve-target target)))
       (lambda (record)
         (member id (gethash (plist-get record :id) (car (my/view--links)))))))
    (`(under ,target)
     (let* ((id (my/view--resolve-target target))
            (parent (my/view--record id))
            (prefix (and parent
                         (append (plist-get parent :olp)
                                 (list (plist-get parent :title))))))
       (lambda (record)
         (and parent
              (not (equal (plist-get record :id) id))
              (equal (plist-get record :file) (plist-get parent :file))
              (or (= 0 (plist-get parent :level))
                  (let ((olp (plist-get record :olp)))
                    (and (>= (length olp) (length prefix))
                         (equal (cl-subseq olp 0 (length prefix)) prefix))))))))
    (`(title ,string)
     (let ((needle (regexp-quote (downcase string))))
       (lambda (record)
         (string-match-p needle (downcase (plist-get record :title))))))
    (`(text ,string)
     (let ((files (my/view--text-files string)))
       (lambda (record)
         (let ((file (plist-get record :file)))
           (and file (gethash (expand-file-name file) files))))))
    (_ (user-error "Unknown view filter: %S" form))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Sorting, grouping, running a view
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; A view is a plist:
;;   :name :type TAG :layout table|list|board :filter FORM
;;   :sort ((COLUMN . DESC) ...) :group COLUMN :columns (COLUMN ...) :limit N

(defconst my/view-layouts '(table list board)
  "Layouts a view can use, in cycling order.")

(defun my/view--parse-sort (spec)
  "Parse SPEC like \"YEAR desc, @title\" into ((COLUMN . DESC) ...)."
  (mapcar (lambda (part)
            (let ((tokens (split-string part "[ \t]+" t)))
              (cons (car tokens)
                    (and (cadr tokens)
                         (string-equal-ignore-case (cadr tokens) "desc")))))
          (and spec (split-string spec "," t "[ \t]+"))))

(defun my/view--format-sort (sort)
  "Return SORT, a list of (COLUMN . DESC), as a string."
  (mapconcat (lambda (key)
               (if (cdr key) (concat (car key) " desc") (car key)))
             sort ", "))

(defun my/view--sort (records sort)
  "Return RECORDS ordered by SORT, a list of (COLUMN . DESC)."
  (if (null sort)
      records
    (let ((keyed (mapcar (lambda (record)
                           (cons (mapcar (lambda (key)
                                           (my/view-value record (car key)))
                                         sort)
                                 record))
                         records)))
      (mapcar
       #'cdr
       (sort keyed
             (lambda (a b)
               (cl-loop for key in sort
                        for va in (car a)
                        for vb in (car b)
                        unless (string= va vb)
                        return (if (cdr key)
                                   (my/node--value< vb va)
                                 (my/node--value< va vb))
                        finally return nil)))))))

(defun my/view--todo-keywords ()
  "Return the configured TODO keywords without their key suffixes."
  (cl-loop for sequence in org-todo-keywords
           append (cl-loop for keyword in (cdr sequence)
                           unless (equal keyword "|")
                           collect (replace-regexp-in-string
                                    "(.*\\'" "" keyword))))

(defun my/view--group-order (view)
  "Return the known values of VIEW's group column, in display order."
  (let ((group (plist-get view :group)))
    (cond
     ((null group) nil)
     ((equal group "@todo") (my/view--todo-keywords))
     (t
      (let ((type (and (plist-get view :type)
                       (my/node-type-by-tag (plist-get view :type)))))
        (or (and type (cdr (assoc (upcase group) (my/node-type-choices type))))
            (cl-some (lambda (other)
                       (cdr (assoc (upcase group) (my/node-type-choices other))))
                     my/node-types)))))))

(defun my/view--group (records view)
  "Split RECORDS into ((VALUE . RECORDS) ...) by VIEW's group column.
Known values come first in their declared order and are kept even when
empty, so a board shows every stage; other values follow alphabetically;
records without a value come last under the empty string."
  (let ((group (plist-get view :group)))
    (if (null group)
        (list (cons nil records))
      (let ((table (make-hash-table :test 'equal))
            (known (my/view--group-order view))
            seen)
        (dolist (record records)
          (let ((value (my/view-value record group)))
            (unless (member value seen) (push value seen))
            (push record (gethash value table))))
        (let* ((extra (sort (cl-remove-if
                             (lambda (v) (or (string-empty-p v) (member v known)))
                             seen)
                            #'string<))
               (order (append known extra
                              (and (member "" seen) (list "")))))
          (mapcar (lambda (value)
                    (cons value (nreverse (gethash value table))))
                  order))))))

(defun my/view--effective-filter (view)
  "Return VIEW's filter combined with its type condition."
  (let ((type (plist-get view :type))
        (filter (plist-get view :filter)))
    (cond
     ((and type filter) `(and (type ,type) ,filter))
     (type `(type ,type))
     (t filter))))

(defun my/view--columns (view)
  "Return VIEW's columns, defaulting to the fields of its type."
  (or (plist-get view :columns)
      (when-let* ((tag (plist-get view :type))
                  (type (my/node-type-by-tag tag)))
        (mapcar (lambda (field) (plist-get field :name))
                (my/node-type-fields type)))))

(defun my/view-run (view)
  "Run VIEW in the current `my/view--ctx'.
Return a plist :groups ((VALUE . RECORDS) ...) :columns :count."
  (let* ((pred (my/view--compile (my/view--effective-filter view)))
         (records (cl-remove-if-not pred (plist-get my/view--ctx :records)))
         (sorted (my/view--sort
                  records
                  (or (plist-get view :sort) '(("@modified" . t)))))
         (limit (plist-get view :limit))
         (limited (if (and limit (> (length sorted) limit))
                      (cl-subseq sorted 0 limit)
                    sorted)))
    (list :groups (my/view--group limited view)
          :columns (my/view--columns view)
          :count (length limited))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Saved views
;; ═══════════════════════════════════════════════════════════════════════════
;;
;;   * Reading board
;;   :PROPERTIES:
;;   :VIEW_TYPE:    reading
;;   :VIEW_LAYOUT:  board
;;   :VIEW_GROUP:   STATUS
;;   :VIEW_COLUMNS: AUTHORS YEAR
;;   :VIEW_SORT:    YEAR desc
;;   :VIEW_FILTER:  (not (field "STATUS" "cited"))
;;   :VIEW_LIMIT:   200
;;   :END:

(defconst my/views-file-template
  "#+title: Views
#+startup: content

# One heading per saved view: a query plus a layout.
#   VIEW_TYPE     type tag whose nodes the view shows (optional)
#   VIEW_LAYOUT   table, list or board
#   VIEW_GROUP    field to group by; a board has one column per value
#   VIEW_COLUMNS  fields to show (default: the type's fields)
#   VIEW_SORT     e.g. YEAR desc, @title
#   VIEW_FILTER   e.g. (and (field \"YEAR\" > 2020) (not (tag \"draft\")))
#   VIEW_LIMIT    maximum number of nodes
# Views can also be created and saved from a view buffer (w).

* Reading board
:PROPERTIES:
:VIEW_TYPE:    reading
:VIEW_LAYOUT:  board
:VIEW_GROUP:   STATUS
:VIEW_COLUMNS: AUTHORS YEAR
:END:
"
  "Starter content for a new views.org file.")

(defun my/views-ensure-file ()
  "Create `my/views-file' with an example view if it does not exist."
  (unless (file-exists-p my/views-file)
    (make-directory (file-name-directory my/views-file) t)
    (with-temp-file my/views-file
      (insert my/views-file-template))
    (message "org-seq: created %s" my/views-file)))

(defun my/views-parse-buffer ()
  "Parse saved views from the current Org buffer."
  (let (views)
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward "^\\* " nil t)
       (beginning-of-line)
       (let ((layout (org-entry-get nil "VIEW_LAYOUT"))
             (filter (org-entry-get nil "VIEW_FILTER"))
             (columns (org-entry-get nil "VIEW_COLUMNS"))
             (limit (org-entry-get nil "VIEW_LIMIT"))
             (group (org-entry-get nil "VIEW_GROUP"))
             (type (org-entry-get nil "VIEW_TYPE")))
         (push (list :name (org-get-heading t t t t)
                     :type (and type (not (string-empty-p type)) type)
                     :layout (if (and layout
                                      (memq (intern layout) my/view-layouts))
                                 (intern layout)
                               'table)
                     :filter (and filter (not (string-empty-p filter))
                                  (car (read-from-string filter)))
                     :sort (my/view--parse-sort (org-entry-get nil "VIEW_SORT"))
                     :group (and group (not (string-empty-p group)) group)
                     :columns (and columns (split-string-and-unquote columns))
                     :limit (and limit (string-to-number limit)))
               views))
       (forward-line 1)))
    (nreverse views)))

(defun my/views-load ()
  "Return the saved views from `my/views-file'."
  (when (file-readable-p my/views-file)
    (with-temp-buffer
      (insert-file-contents my/views-file)
      (let ((org-inhibit-startup t))
        (delay-mode-hooks (org-mode)))
      (my/views-parse-buffer))))

(defun my/view-by-name (name)
  "Return the saved view called NAME, or nil."
  (cl-find name (my/views-load)
           :key (lambda (view) (plist-get view :name)) :test #'equal))

(defun my/view-save-definition (view)
  "Write VIEW to `my/views-file', replacing a view of the same name."
  (my/views-ensure-file)
  (let ((name (plist-get view :name)))
    (with-current-buffer (find-file-noselect my/views-file)
      (org-with-wide-buffer
       (let ((pos (org-find-exact-headline-in-buffer name)))
         (unless pos
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert "\n* " name "\n")
           (setq pos (save-excursion (forward-line -1) (point))))
         (pcase-dolist
             (`(,key . ,value)
              (list (cons "VIEW_TYPE" (plist-get view :type))
                    (cons "VIEW_LAYOUT" (symbol-name
                                         (or (plist-get view :layout) 'table)))
                    (cons "VIEW_GROUP" (plist-get view :group))
                    (cons "VIEW_COLUMNS"
                          (and (plist-get view :columns)
                               (combine-and-quote-strings
                                (plist-get view :columns))))
                    (cons "VIEW_SORT"
                          (and (plist-get view :sort)
                               (my/view--format-sort (plist-get view :sort))))
                    (cons "VIEW_FILTER"
                          (and (plist-get view :filter)
                               (prin1-to-string (plist-get view :filter))))
                    (cons "VIEW_LIMIT"
                          (and (plist-get view :limit)
                               (number-to-string (plist-get view :limit))))))
           (if value
               (org-entry-put pos key value)
             (org-entry-delete pos key)))))
      (save-buffer))))

(defun my/views-edit ()
  "Open the saved views file."
  (interactive)
  (my/views-ensure-file)
  (find-file my/views-file))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: Rendering
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Every rendered node carries the text property `my/view-id'; table cells
;; also carry `my/view-field', board cells `my/view-group'.

(defface my/view-header
  '((t :inherit bold :underline t))
  "Face for column headers in view buffers."
  :group 'org-seq)

(defface my/view-group
  '((t :inherit (bold font-lock-keyword-face)))
  "Face for group headings in view buffers."
  :group 'org-seq)

(defface my/view-dim
  '((t :inherit shadow))
  "Face for secondary values in view buffers."
  :group 'org-seq)

(defun my/view--pad (string width)
  "Return STRING truncated or padded to display WIDTH."
  (truncate-string-to-width (or string "") width nil ?\s "…"))

(defun my/view--group-label (value)
  "Return the heading text for group VALUE."
  (if (string-empty-p value) "(none)" value))

(defun my/view--todo-prefix (record)
  "Return RECORD's TODO keyword followed by a space, or an empty string."
  (if-let* ((todo (plist-get record :todo)))
      (concat (propertize todo 'face 'org-todo) " ")
    ""))

(defun my/view--render-table (result)
  "Insert RESULT as an aligned table."
  (let* ((columns (cons "@title" (plist-get result :columns)))
         (groups (plist-get result :groups))
         (rows (cl-loop for group in groups
                        append (mapcar
                                (lambda (record)
                                  (cons record
                                        (mapcar (lambda (column)
                                                  (my/view-value record column))
                                                columns)))
                                (cdr group))))
         (widths (cl-loop for column in columns
                          for index from 0
                          collect
                          (min (if (= index 0) 48 32)
                               (apply #'max
                                      (string-width (my/view--column-label column))
                                      (if (= index 0) 24 6)
                                      (mapcar (lambda (row)
                                                (string-width (nth index (cdr row))))
                                              rows)))))
         (by-record (make-hash-table :test 'eq)))
    (dolist (row rows) (puthash (car row) (cdr row) by-record))
    (insert (mapconcat (lambda (pair)
                         (propertize (my/view--pad
                                      (my/view--column-label (car pair)) (cdr pair))
                                     'face 'my/view-header))
                       (cl-mapcar #'cons columns widths)
                       "  ")
            "\n")
    (dolist (group groups)
      (when (and (car group) (cdr group))
        (insert (propertize (format "%s (%d)" (my/view--group-label (car group))
                                    (length (cdr group)))
                            'face 'my/view-group 'my/view-group (car group))
                "\n"))
      (dolist (record (cdr group))
        (let ((start (point)))
          (cl-loop for column in columns
                   for width in widths
                   for value in (gethash record by-record)
                   for index from 0
                   do (insert (propertize
                               (my/view--pad
                                (if (= index 0)
                                    (concat (my/view--todo-prefix record) value)
                                  value)
                                width)
                               'my/view-field column)
                              "  "))
          (insert "\n")
          (add-text-properties start (point)
                               (list 'my/view-id (plist-get record :id)
                                     'my/view-group (car group))))))))

(defun my/view--render-list (result)
  "Insert RESULT as one compact line per node."
  (let ((columns (plist-get result :columns)))
    (dolist (group (plist-get result :groups))
      (when (and (car group) (cdr group))
        (insert (propertize (format "%s (%d)" (my/view--group-label (car group))
                                    (length (cdr group)))
                            'face 'my/view-group 'my/view-group (car group))
                "\n"))
      (dolist (record (cdr group))
        (let ((start (point))
              (details (cl-remove-if
                        #'string-empty-p
                        (mapcar (lambda (column) (my/view-value record column))
                                columns))))
          (insert (if (car group) "  - " "- ")
                  (my/view--todo-prefix record)
                  (propertize (plist-get record :title) 'face 'bold))
          (when details
            (insert "   "
                    (propertize (string-join details " | ") 'face 'my/view-dim)))
          (insert "\n")
          (add-text-properties start (point)
                               (list 'my/view-id (plist-get record :id)
                                     'my/view-group (car group))))))))

(defun my/view--board-width (count)
  "Return the card width for a board with COUNT columns."
  (max 20 (min 40 (/ (- (window-width) 2) (max 1 count)))))

(defun my/view--board-cells (group columns width)
  "Return the padded cell strings of board column GROUP.
COLUMNS are the fields shown under each card title; WIDTH is the cell
width.  Each cell carries the node id (when on a card) and group value."
  (let ((value (car group))
        cells)
    (cl-flet ((cell (text &optional id face)
                (push (apply #'propertize
                             (my/view--pad text width)
                             'my/view-group value
                             (append (and id (list 'my/view-id id))
                                     (and face (list 'face face))))
                      cells)))
      (cell (format "%s (%d)" (my/view--group-label value) (length (cdr group)))
            nil 'my/view-group)
      (cell (make-string (1- width) ?-) nil 'my/view-dim)
      (dolist (record (cdr group))
        (let ((id (plist-get record :id))
              (details (cl-remove-if
                        #'string-empty-p
                        (mapcar (lambda (column) (my/view-value record column))
                                columns))))
          (cell (concat (my/view--todo-prefix record)
                        (propertize (plist-get record :title) 'face 'bold))
                id)
          (when details
            (cell (concat "  " (string-join details " | ")) id 'my/view-dim))
          (cell "" nil))))
    (nreverse cells)))

(defun my/view--render-board (result)
  "Insert RESULT as a board with one column per group."
  (let* ((groups (plist-get result :groups))
         (width (my/view--board-width (length groups)))
         (columns (mapcar (lambda (group)
                            (my/view--board-cells
                             group (plist-get result :columns) width))
                          groups))
         (height (apply #'max 0 (mapcar #'length columns))))
    (dotimes (row height)
      (cl-loop for column in columns
               for group in groups
               do (insert (or (nth row column)
                              (propertize (make-string width ?\s)
                                          'my/view-group (car group)))
                          " "))
      (insert "\n"))))

(defun my/view--render (view result)
  "Insert RESULT in the layout of VIEW."
  (pcase (plist-get view :layout)
    ('list (my/view--render-list result))
    ('board
     (if (plist-get view :group)
         (my/view--render-board result)
       (insert "A board needs a group field: press G to choose one.\n\n")
       (my/view--render-list result)))
    (_ (my/view--render-table result))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 7: View buffers
;; ═══════════════════════════════════════════════════════════════════════════

(defvar-local my/view--view nil
  "The view plist shown in this buffer.")

(defvar-local my/view--current nil
  "Id of the node `current' refers to in this buffer's view, or nil.")

(defvar-local my/view--quick-filter nil
  "Substring typed with `/' that rows must contain, or nil.")

(defvar-keymap my/view-mode-map
  :parent special-mode-map
  "RET" #'my/view-visit
  "o"   #'my/view-visit-other-window
  "j"   #'next-line
  "k"   #'previous-line
  "h"   #'my/view-left
  "l"   #'my/view-right
  "H"   #'my/view-move-left
  "L"   #'my/view-move-right
  "e"   #'my/view-edit-field
  "f"   #'my/view-edit-field
  "t"   #'my/view-set-todo
  "+"   #'my/view-new
  "/"   #'my/view-quick-filter
  "v"   #'my/view-cycle-layout
  "G"   #'my/view-set-group
  "s"   #'my/view-set-sort
  "F"   #'my/view-set-filter
  "c"   #'my/view-set-columns
  "w"   #'my/view-save
  "g"   #'my/view-refresh)

(define-derived-mode my/view-mode special-mode "View"
  "Table, list or board of org-roam nodes.
\\{my/view-mode-map}"
  (setq truncate-lines t)
  (setq-local revert-buffer-function (lambda (&rest _) (my/view-refresh))))

;; View keys are single letters; keep them out of Evil's normal state.
;; The SPC leader stays available because it is bound in emacs state too.
(with-eval-after-load 'evil
  (evil-set-initial-state 'my/view-mode 'emacs))

(defun my/view--quick-match-p (record columns)
  "Return non-nil when RECORD matches the buffer's quick filter."
  (or (null my/view--quick-filter)
      (let ((needle (regexp-quote (downcase my/view--quick-filter))))
        (cl-some (lambda (column)
                   (string-match-p needle (downcase (my/view-value record column))))
                 (cons "@title" columns)))))

(defun my/view-refresh ()
  "Re-run the view of this buffer and redraw it."
  (interactive)
  (let* ((inhibit-read-only t)
         (id (get-text-property (point) 'my/view-id))
         (line (line-number-at-pos))
         (column (current-column))
         (view my/view--view)
         (my/view--ctx (my/view--make-ctx (my/view--records) my/view--current))
         (result (my/view-run view))
         (columns (plist-get result :columns))
         (count 0))
    (setq result
          (plist-put result :groups
                     (mapcar (lambda (group)
                               (let ((kept (cl-remove-if-not
                                            (lambda (record)
                                              (my/view--quick-match-p record columns))
                                            (cdr group))))
                                 (cl-incf count (length kept))
                                 (cons (car group) kept)))
                             (plist-get result :groups))))
    (erase-buffer)
    (my/view--render view result)
    (setq header-line-format
          (format " %s   %s%s   %d nodes%s%s"
                  (plist-get view :name)
                  (plist-get view :layout)
                  (if (plist-get view :group)
                      (format " by %s" (plist-get view :group))
                    "")
                  count
                  (if (plist-get view :filter)
                      (format "   filter: %S" (plist-get view :filter))
                    "")
                  (if my/view--quick-filter
                      (format "   /%s" my/view--quick-filter)
                    "")))
    (goto-char (point-min))
    (let ((match (and id (text-property-search-forward 'my/view-id id t))))
      (if match
          ;; The match starts at the node's row or card, wherever it moved.
          (goto-char (prop-match-beginning match))
        (forward-line (1- line))
        (move-to-column column)))))

(defun my/view-show (view &optional current)
  "Display VIEW in a view buffer.
CURRENT is the id of the node that `current' refers to in its filter."
  (let ((buffer (get-buffer-create (format "*view: %s*" (plist-get view :name)))))
    (with-current-buffer buffer
      (my/view-mode)
      (setq my/view--view (copy-sequence view)
            my/view--current current)
      (my/view-refresh))
    (pop-to-buffer-same-window buffer)))

(defun my/view-open (name)
  "Open the saved view called NAME."
  (interactive
   (let ((names (mapcar (lambda (view) (plist-get view :name)) (my/views-load))))
     (unless names
       (user-error "No saved views yet; create one with `my/view-new-view'"))
     (list (completing-read "View: " names nil t))))
  (my/view-show (or (my/view-by-name name)
                    (user-error "No saved view called %s" name))))

(defun my/view-show-type (type)
  "Open the saved view of TYPE, or a default table of its nodes."
  (let* ((tag (my/node-type-tag type))
         (views (cl-remove-if-not
                 (lambda (view) (equal (plist-get view :type) tag))
                 (my/views-load))))
    (my/view-show
     (cond
      ((null views)
       (list :name (my/node-type-name type) :type tag :layout 'table))
      ((null (cdr views)) (car views))
      (t (my/view-by-name
          (completing-read
           (format "%s view: " (my/node-type-name type))
           (mapcar (lambda (view) (plist-get view :name)) views) nil t)))))))

(defun my/view-new-view (name)
  "Create a view called NAME: pick a type and layout, then refine it."
  (interactive "sNew view name: ")
  (let* ((type (and my/node-types
                    (y-or-n-p "Limit the view to one type? ")
                    (my/node-read-type "Type: ")))
         (layout (intern (completing-read
                          "Layout: " (mapcar #'symbol-name my/view-layouts)
                          nil t nil nil "table")))
         (view (list :name name
                     :type (and type (my/node-type-tag type))
                     :layout layout)))
    (my/view-show view)
    (when (eq layout 'board)
      (call-interactively #'my/view-set-group))
    (message "Press w to save this view, F to filter, c to choose columns")))

(defun my/view--id-at-point ()
  "Return the node id on the current row or card."
  (or (get-text-property (point) 'my/view-id)
      (get-text-property (line-beginning-position) 'my/view-id)
      (user-error "No node here")))

(defun my/view--node-at-point ()
  "Return the record of the node on the current row or card."
  (let ((id (my/view--id-at-point)))
    (or (my/index-node id)
        (user-error "Node %s is no longer in the index; press g" id))))

(defun my/view-visit ()
  "Open the node at point."
  (interactive)
  (my/node-visit (my/view--node-at-point)))

(defun my/view-visit-other-window ()
  "Open the node at point in another window."
  (interactive)
  (my/node-visit (my/view--node-at-point) t))

(defun my/view--update (&rest changes)
  "Apply plist CHANGES to this buffer's view and redraw."
  (while changes
    (setq my/view--view (plist-put my/view--view (pop changes) (pop changes))))
  (my/view-refresh))

(defun my/view-cycle-layout ()
  "Switch to the next layout: table, list, board."
  (interactive)
  (let* ((layout (or (plist-get my/view--view :layout) 'table))
         (next (or (cadr (memq layout my/view-layouts))
                   (car my/view-layouts))))
    (my/view--update :layout next)
    (message "Layout: %s" next)))

(defun my/view--field-candidates ()
  "Return field names worth offering for this buffer's view."
  (delete-dups
   (append (my/view--columns my/view--view)
           (cl-loop for type in my/node-types
                    append (mapcar (lambda (field) (plist-get field :name))
                                   (my/node-type-fields type)))
           '("@todo" "@tags" "@modified" "@created" "@in" "@out" "@file"))))

(defun my/view-set-group (field)
  "Group this view by FIELD; an empty FIELD removes grouping."
  (interactive
   (list (completing-read "Group by (empty for none): "
                          (my/view--field-candidates))))
  (my/view--update :group (unless (string-empty-p field) field)))

(defun my/view-set-sort (spec)
  "Sort this view by SPEC, e.g. \"YEAR desc, @title\"."
  (interactive
   (list (read-string "Sort (e.g. YEAR desc, @title): "
                      (my/view--format-sort (plist-get my/view--view :sort)))))
  (my/view--update :sort (my/view--parse-sort spec)))

(defun my/view-set-filter (form)
  "Replace this view's filter with FORM; nil removes it."
  (interactive
   (list (read-from-minibuffer
          "Filter: "
          (and (plist-get my/view--view :filter)
               (prin1-to-string (plist-get my/view--view :filter)))
          nil t)))
  (let ((my/view--ctx (my/view--make-ctx nil my/view--current)))
    (my/view--compile form))
  (my/view--update :filter form))

(defun my/view-set-columns (columns)
  "Show COLUMNS in this view."
  (interactive
   (list (completing-read-multiple
          "Columns (comma separated): " (my/view--field-candidates) nil nil
          (string-join (my/view--columns my/view--view) ","))))
  (my/view--update :columns columns))

(defun my/view-quick-filter (text)
  "Show only nodes containing TEXT; empty TEXT clears the quick filter."
  (interactive (list (read-string "Quick filter (empty clears): "
                                  my/view--quick-filter)))
  (setq my/view--quick-filter (unless (string-empty-p text) text))
  (my/view-refresh))

(defun my/view-save (name)
  "Save this view as NAME in the views file."
  (interactive (list (read-string "Save view as: "
                                  (plist-get my/view--view :name))))
  (setq my/view--view (plist-put my/view--view :name name))
  (my/view-save-definition my/view--view)
  (rename-buffer (format "*view: %s*" name) t)
  (my/view-refresh)
  (message "View %s saved" name))

(defun my/view-edit-field ()
  "Edit a field of the node at point.
In a table the field under the cursor is edited; elsewhere, or on a
computed column, the field is chosen from a prompt."
  (interactive)
  (let ((id (my/view--id-at-point))
        (field (get-text-property (point) 'my/view-field)))
    (my/node-call-at-id
     id
     (lambda (pos)
       (if (not (my/view--plain-field-p field))
           (my/node-set-field-at pos)
         (let* ((name (upcase field))
                (types (my/node-types-at pos))
                (spec (cl-find name
                               (cl-loop for type in types
                                        append (my/node-type-fields type))
                               :key (lambda (s) (plist-get s :name))
                               :test #'equal)))
           (org-entry-put pos name
                          (my/node--read-field-value
                           name spec types (org-entry-get pos name)))))))
    (my/view-refresh)))

(defun my/view--set-todo (id state)
  "Set the TODO state of node ID to STATE (empty string removes it)."
  (my/node-call-at-id
   id (lambda (pos)
        (goto-char pos)
        (when (org-before-first-heading-p)
          (user-error "A file-level node has no TODO state"))
        (let ((org-log-done nil)
              (org-log-into-drawer nil)
              (org-todo-log-states nil))
          (org-todo (if (string-empty-p state) 'none state))))))

(defun my/view-set-todo (state)
  "Set the TODO STATE of the node at point."
  (interactive
   (list (completing-read "State (empty removes): " (my/view--todo-keywords))))
  (my/view--set-todo (my/view--id-at-point) state)
  (my/view-refresh))

(defun my/view--equality-fields (form)
  "Return (FIELD . VALUE) pairs FORM requires, for prefilling new nodes."
  (pcase form
    (`(and . ,forms) (cl-mapcan #'my/view--equality-fields forms))
    ((or `(field ,name ,(and value (pred stringp)))
         `(field ,name = ,(and value (pred stringp))))
     (and (my/view--plain-field-p (format "%s" name))
          (list (cons (format "%s" name) value))))
    (`(field ,name = current)
     (when-let* ((id my/view--current)
                 (node (my/index-node id)))
       (list (cons (format "%s" name)
                   (format "[[id:%s][%s]]" id (plist-get node :title))))))
    (_ nil)))

(defun my/view-new ()
  "Create a node in this view.
The new note gets the view's type, the field values the filter requires,
and the group value of the column or section at point."
  (interactive)
  (let* ((view my/view--view)
         (type (or (and (plist-get view :type)
                        (my/node-type-by-tag (plist-get view :type)))
                   (my/node-read-type "New note of type: ")))
         (group (plist-get view :group))
         (value (get-text-property (point) 'my/view-group))
         (fields (append
                  (my/view--equality-fields (plist-get view :filter))
                  (and (my/view--plain-field-p group)
                       value (not (string-empty-p value))
                       (list (cons group value))))))
    (my/node-capture type
                     (read-string (format "New %s: " (my/node-type-name type)))
                     fields)))

;; ---- Board navigation and card moves ----

(defun my/view--board-p ()
  "Return non-nil when this buffer shows a board."
  (and (eq (plist-get my/view--view :layout) 'board)
       (plist-get my/view--view :group)))

(defun my/view--board-step (delta)
  "Move point DELTA board columns sideways, staying on the same line."
  (let* ((groups (length (my/view--group-order-in-buffer)))
         (width (1+ (my/view--board-width groups)))
         (index (/ (current-column) width))
         (target (max 0 (min (1- groups) (+ index delta)))))
    (move-to-column (* target width))))

(defun my/view--group-order-in-buffer ()
  "Return the group values of the board in this buffer, left to right."
  (let (values)
    (save-excursion
      (goto-char (point-min))
      (let ((end (line-end-position))
            (pos (point)))
        (while (< pos end)
          (let ((value (get-text-property pos 'my/view-group)))
            (unless (equal value (car values)) (push value values)))
          (setq pos (or (next-single-property-change pos 'my/view-group nil end)
                        end)))))
    (nreverse (delq nil values))))

(defun my/view-left ()
  "Move to the board column on the left, or one character back."
  (interactive)
  (if (my/view--board-p) (my/view--board-step -1) (backward-char)))

(defun my/view-right ()
  "Move to the board column on the right, or one character forward."
  (interactive)
  (if (my/view--board-p) (my/view--board-step 1) (forward-char)))

(defun my/view--move-card (delta)
  "Move the card at point DELTA columns by setting its group field."
  (unless (my/view--board-p)
    (user-error "Cards move in board layout (v switches layout)"))
  (let* ((id (my/view--id-at-point))
         (group (plist-get my/view--view :group))
         (order (my/view--group-order-in-buffer))
         (index (cl-position (get-text-property (point) 'my/view-group)
                             order :test #'equal))
         (target (nth (+ index delta) order)))
    (unless (and target (>= (+ index delta) 0))
      (user-error "No column in that direction"))
    (cond
     ((equal group "@todo") (my/view--set-todo id target))
     ((my/view--plain-field-p group) (my/node-set-field-by-id id group target))
     (t (user-error "Cards cannot move along the computed column %s" group)))
    (my/view-refresh)
    (message "%s: %s" group (my/view--group-label target))))

(defun my/view-move-left ()
  "Move the card at point to the previous board column."
  (interactive)
  (my/view--move-card -1))

(defun my/view-move-right ()
  "Move the card at point to the next board column."
  (interactive)
  (my/view--move-card 1))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 8: Dynamic block
;; ═══════════════════════════════════════════════════════════════════════════
;;
;;   #+BEGIN: orgseq-view :view "Reading board"
;;   #+END:
;;
;;   #+BEGIN: orgseq-view :type "material" :filter (field "COURSE" = current) :layout list
;;   #+END:
;;
;; :view names a saved view; the other parameters (those of a view plist,
;; with :sort as a string) define one inline or override the saved one.
;; `current' is the node the block sits in.  The block is a read-only
;; snapshot: table and list become an Org table and list, a board becomes
;; a table with one column per group.

(defun my/view--link (record)
  "Return an Org id link to RECORD."
  (format "[[id:%s][%s]]" (plist-get record :id)
          (replace-regexp-in-string "[][]" "" (plist-get record :title))))

(defun my/view--insert-org (view result)
  "Insert RESULT as Org markup in the layout of VIEW."
  (let ((columns (plist-get result :columns))
        (groups (plist-get result :groups)))
    (cond
     ((= 0 (plist-get result :count))
      (insert "/No matching nodes./"))
     ((and (eq (plist-get view :layout) 'board) (plist-get view :group))
      (insert "| "
              (mapconcat (lambda (group)
                           (format "%s (%d)" (my/view--group-label (car group))
                                   (length (cdr group))))
                         groups " | ")
              " |\n|-\n")
      (dotimes (row (apply #'max 0 (mapcar (lambda (g) (length (cdr g))) groups)))
        (insert "| "
                (mapconcat (lambda (group)
                             (if-let* ((record (nth row (cdr group))))
                                 (my/node--table-cell (my/view--link record))
                               ""))
                           groups " | ")
                " |\n"))
      (delete-char -1)
      (org-table-align))
     ((eq (plist-get view :layout) 'list)
      (dolist (group groups)
        (when (car group)
          (insert (format "- %s (%d)\n" (my/view--group-label (car group))
                          (length (cdr group)))))
        (dolist (record (cdr group))
          (let ((details (cl-remove-if
                          #'string-empty-p
                          (mapcar (lambda (c) (my/view-value record c)) columns))))
            (insert (if (car group) "  - " "- ")
                    (my/view--link record)
                    (if details (concat " :: " (string-join details " | ")) "")
                    "\n"))))
      (delete-char -1))
     (t
      (insert "| Title | "
              (mapconcat #'my/view--column-label columns " | ") " |\n")
      (dolist (group groups)
        (insert "|-\n")
        (when (car group)
          (insert (format "| *%s* (%d) |\n" (my/view--group-label (car group))
                          (length (cdr group)))))
        (dolist (record (cdr group))
          (insert "| " (my/node--table-cell (my/view--link record)) " | "
                  (mapconcat (lambda (c)
                               (my/node--table-cell (my/view-value record c)))
                             columns " | ")
                  " |\n")))
      (delete-char -1)
      (org-table-align)))))

(defun my/view-from-params (params)
  "Build a view plist from dynamic block or tool PARAMS."
  (let* ((saved (and (plist-get params :view)
                     (or (my/view-by-name (plist-get params :view))
                         (user-error "No saved view called %s"
                                     (plist-get params :view)))))
         (view (copy-sequence (or saved (list :name "inline" :layout 'table)))))
    (dolist (key '(:type :filter :group :columns :limit))
      (when (plist-member params key)
        (setq view (plist-put view key (plist-get params key)))))
    (when (plist-get params :layout)
      (setq view (plist-put view :layout
                            (intern (format "%s" (plist-get params :layout))))))
    (when (plist-get params :sort)
      (setq view (plist-put view :sort
                            (my/view--parse-sort
                             (format "%s" (plist-get params :sort))))))
    (when (plist-get view :type)
      (setq view (plist-put view :type (format "%s" (plist-get view :type)))))
    view))

(defun org-dblock-write:orgseq-view (params)
  "Write an `orgseq-view' dynamic block from PARAMS."
  (let* ((view (my/view-from-params params))
         (current (when-let* ((pos (ignore-errors (my/node-position))))
                    (org-entry-get pos "ID")))
         (my/view--ctx (my/view--make-ctx (my/view--records) current)))
    (my/view--insert-org view (my/view-run view))))

(provide 'init-views)
;;; init-views.el ends here
