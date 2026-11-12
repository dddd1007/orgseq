;;; init-nodes.el --- Node types, fields, views, and actions -*- lexical-binding: t; -*-
;;
;; Every file or heading with an Org ID is a node and relations are
;; [[id:]] links.  The kernel index (kernel/orgseq-index.el) is what this
;; module reads; new notes are written through init-capture.  The module
;; adds the Tana/Fibery layer on top:
;;
;;   Types    Tana supertags / Fibery databases.  Defined as headings in
;;            `my/types-file' (.orgseq/types.org).  A type is an Org tag, a
;;            list of fields, and a template.  Applying a type to a node adds
;;            the tag; its fields are ordinary Org properties.
;;   Fields   Property values.  Choices come from KEY_ALL on the type
;;            heading or from values already used in the library; a field
;;            declared NAME:node stores an [[id:]] link to another node
;;            (a Fibery relation).  NAME:date, NAME:number and NAME:check
;;            pick a matching reader.  A type may extend one parent type
;;            (TYPE_EXTENDS) and inherits its fields.
;;   Views    A sortable, filterable table per type (Fibery table view) with
;;            inline field editing, a Review table for unsorted notes, and the
;;            `orgseq-query' dynamic block for dashboards.
;;   Actions  One node menu (Tana command line): type, field, link, promote,
;;            extract, backlinks.
;;   Finding  Node find and link insertion over the index (titles and
;;            ROAM_ALIASES), a backlinks buffer, and id links that open
;;            through the index before Org's own id lookup.
;;
;; Org text is the only authority.  Everything here reads Org through the
;; kernel index and writes plain tags and properties, so notes stay
;; readable by any Org tool and the index can always be rebuilt.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │                       Table of Contents                          │
;; ├─────────────────────────────────────────────────────────────────┤
;; │ Section 1  Capture templates generated from the types            │
;; │ Section 2  Type registry (.orgseq/types.org)                     │
;; │ Section 3  Node at point: position, tags, types, fields          │
;; │ Section 4  Commands: set/remove type, set field, promote, capture│
;; │ Section 5  Queries over the node index                           │
;; │ Section 6  Table views (type view, review)                       │
;; │ Section 7  Dashboard dynamic blocks                              │
;; │ Section 8  Node action menu, find, links, backlinks, id links    │
;; │ Section 9  Dashboard files, PARA navigation, NoteHQ bootstrap    │
;; └─────────────────────────────────────────────────────────────────┘

;; Requires: init-org     (NoteHQ path constants, my/types-file)
;; Requires: init-capture (note creation, capture template registry)
(defvar my/note-home)
(defvar my/orgseq-dir)
(defvar my/roam-dir)
(defvar my/outputs-dir)
(defvar my/practice-dir)
(defvar my/library-dir)
(defvar my/archives-dir)
(defvar my/dashboards-dir)
(defvar my/types-file)
(defvar my/capture-template-functions)
(defvar my/capture-fields-function)
(defvar my/capture-templates-changed-hook)

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'tabulated-list)

(declare-function consult-ripgrep "consult")
(require 'orgseq-index)
(require 'orgseq-note)

(declare-function my/note-capture "init-capture"
                  (&optional title template fields no-visit))
(declare-function my/ensure-capture-templates-file "init-capture" ())
(declare-function evil-normal-state-p "evil-states" (&optional state))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Capture templates
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; init-capture merges three template sources: its built-in default, the
;; functions on `my/capture-template-functions', and the user's
;; .orgseq/capture-templates.el.  This module contributes one template per
;; type from types.org (keys "t" + TYPE_KEY), defined in Section 2, and
;; names the fields a new note of a type starts with.

(defvar my/node-types)
(defvar my/node-add-empty-fields)

(defun my/node-capture-fields (tags)
  "Return the field names of the types among TAGS, for a new note.
Nil when `my/node-add-empty-fields' is off."
  (when my/node-add-empty-fields
    (delete-dups
     (cl-loop for type in (my/node-types-for-tags tags)
              append (mapcar (lambda (field) (plist-get field :name))
                             (my/node-type-fields type))))))

(add-hook 'my/capture-template-functions #'my/node-type-capture-templates)
(setq my/capture-fields-function #'my/node-capture-fields)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Type registry
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; types.org holds one level-1 heading per type:
;;
;;   * Reading
;;   :PROPERTIES:
;;   :TYPE_TAG:        reading
;;   :TYPE_KEY:        r
;;   :TYPE_FIELDS:     AUTHORS YEAR STATUS TOPIC:node
;;   :STATUS_ALL:      queued reading read cited
;;   :END:
;;   ** Summary
;;   %?
;;   ** Key points
;;
;; TYPE_TAG defaults to the heading name in lower case.  TYPE_FIELDS lists
;; property keys; a ":node" suffix makes the field a link to another node,
;; ":date" a date, ":number" a number, ":check" a yes/no value.
;; TYPE_EXTENDS names one parent type (by name or tag): the type inherits
;; the parent's fields and choices, and queries for the parent type also
;; return nodes of the child type.
;; NAME_ALL gives the allowed values of field NAME (Org's own convention).
;; The heading body is the capture template, one level shallower; "%?"
;; marks where the cursor lands.
;;
;; The file lives in .orgseq/, outside every directory GTD scans, so TODO
;; headings inside templates never reach the agenda.

(cl-defstruct (my/node-type (:constructor my/node-type--create))
  "A note type: an Org tag with fields and a capture template."
  name tag key fields choices template parent)

(defvar my/node-types nil
  "Types parsed from `my/types-file', in file order.")

(defconst my/types-file-template
  "#+title: Node types
#+startup: content

# One heading per type.  Applying a type to a node adds TYPE_TAG to it;
# TYPE_FIELDS become Org properties on the node.  NAME_ALL lists allowed
# values for field NAME; a field written NAME:node stores a link to another
# node, NAME:date a date, NAME:number a number, NAME:check a yes/no value.
# TYPE_EXTENDS names a parent type whose fields are inherited.
# The heading body is the capture template (\"%?\" = cursor).
# Save this file to apply changes.

* Reading
:PROPERTIES:
:TYPE_TAG:    reading
:TYPE_KEY:    r
:TYPE_FIELDS: AUTHORS YEAR STATUS TOPIC:node
:STATUS_ALL:  queued reading read cited
:END:
** Summary
%?
** Key points
** My commentary

* Concept
:PROPERTIES:
:TYPE_TAG:    concept
:TYPE_KEY:    c
:TYPE_FIELDS: STAGE SOURCE:node
:STAGE_ALL:   seed growing evergreen
:END:
** Definition
%?
** Related

* Person
:PROPERTIES:
:TYPE_TAG:    person
:TYPE_KEY:    p
:TYPE_FIELDS: ROLE AFFILIATION
:END:
** Context
%?
"
  "Starter content for a new types.org file.")

(defun my/node--slug (name)
  "Return an Org tag derived from type NAME."
  (replace-regexp-in-string "[^[:alnum:]_@#%]+" "_" (downcase (string-trim name))))

(defun my/node-types--parse-fields (spec)
  "Parse a TYPE_FIELDS value SPEC into a list of field plists."
  (mapcar (lambda (token)
            (if (string-match "\\`\\([^:]+\\):\\([a-z]+\\)\\'" token)
                (list :name (upcase (match-string 1 token))
                      :kind (intern (match-string 2 token)))
              (list :name (upcase token) :kind 'text)))
          (and spec (split-string spec "[ \t,]+" t))))

(defun my/node-types--template-body ()
  "Return the body of the type heading at point as a capture template."
  (save-excursion
    (let ((end (save-excursion (org-end-of-subtree t t) (point))))
      (org-end-of-meta-data t)
      (if (>= (point) end)
          ""
        (string-trim
         (replace-regexp-in-string
          "^\\*\\(\\*+[ \t]\\)" "\\1"
          (buffer-substring-no-properties (point) end)))))))

(defun my/node-types-parse-buffer ()
  "Parse type definitions from the current Org buffer."
  (let (types)
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward "^\\* " nil t)
       (beginning-of-line)
       (let* ((name (org-get-heading t t t t))
              (fields (my/node-types--parse-fields
                       (org-entry-get nil "TYPE_FIELDS")))
              (choices
               (delq nil
                     (mapcar
                      (lambda (field)
                        (when-let* ((values (org-entry-get
                                             nil (concat (plist-get field :name)
                                                         "_ALL"))))
                          (cons (plist-get field :name)
                                (split-string-and-unquote values))))
                      fields))))
         (push (my/node-type--create
                :name name
                :tag (or (org-entry-get nil "TYPE_TAG") (my/node--slug name))
                :key (org-entry-get nil "TYPE_KEY")
                :fields fields
                :choices choices
                :template (my/node-types--template-body)
                :parent (org-entry-get nil "TYPE_EXTENDS"))
               types))
       (forward-line 1)))
    (my/node-types--resolve-inheritance (nreverse types))))

(defun my/node-types--find (ref types)
  "Return the type in TYPES whose name or tag is REF (case-insensitive)."
  (and ref
       (cl-find-if (lambda (type)
                     (or (string-equal-ignore-case ref (my/node-type-name type))
                         (string-equal-ignore-case ref (my/node-type-tag type))))
                   types)))

(defun my/node-types--resolve-inheritance (types)
  "Give each type in TYPES the fields and choices of its ancestors.
Inheritance is single: TYPE_EXTENDS names one parent.  Parent fields come
first; a field redeclared by the child keeps the child's definition.  An
unknown parent or a cycle leaves the type as written."
  (let ((done (make-hash-table :test 'eq)))
    (cl-labels
        ((resolve (type trail)
           (unless (gethash type done)
             (puthash type t done)
             (let ((parent (my/node-types--find (my/node-type-parent type) types)))
               (when (and parent (not (eq parent type)) (not (memq parent trail)))
                 (resolve parent (cons type trail))
                 (let* ((own (my/node-type-fields type))
                        (own-names (mapcar (lambda (f) (plist-get f :name)) own)))
                   (setf (my/node-type-fields type)
                         (append
                          (cl-remove-if
                           (lambda (f) (member (plist-get f :name) own-names))
                           (my/node-type-fields parent))
                          own))
                   (setf (my/node-type-choices type)
                         (append
                          (my/node-type-choices type)
                          (cl-remove-if
                           (lambda (c) (assoc (car c) (my/node-type-choices type)))
                           (my/node-type-choices parent))))))))))
      (dolist (type types) (resolve type nil)))
    types))

(defun my/node-type-family-tags (tag)
  "Return TAG plus the tags of every type that descends from TAG's type."
  (let ((tags (list tag))
        (changed t))
    (while changed
      (setq changed nil)
      (dolist (type my/node-types)
        (let ((parent (my/node-types--find (my/node-type-parent type)
                                           my/node-types)))
          (when (and parent
                     (member (my/node-type-tag parent) tags)
                     (not (member (my/node-type-tag type) tags)))
            (push (my/node-type-tag type) tags)
            (setq changed t)))))
    (nreverse tags)))

(defun my/node-types-ensure-file ()
  "Create `my/types-file' with example types if it does not exist."
  (unless (file-exists-p my/types-file)
    (make-directory (file-name-directory my/types-file) t)
    (with-temp-file my/types-file
      (insert my/types-file-template))
    (message "org-seq: created %s" my/types-file)))

(defun my/node-types-reload ()
  "Re-read `my/types-file' and regenerate typed capture templates."
  (interactive)
  (setq my/node-types
        (when (file-readable-p my/types-file)
          (with-temp-buffer
            (insert-file-contents my/types-file)
            (let ((org-inhibit-startup t))
              (delay-mode-hooks (org-mode)))
            (my/node-types-parse-buffer))))
  (run-hooks 'my/capture-templates-changed-hook)
  (when (called-interactively-p 'interactive)
    (message "org-seq: %d node types loaded" (length my/node-types)))
  my/node-types)

(defun my/node-types-edit ()
  "Open the type registry; saving it reloads the types."
  (interactive)
  (my/node-types-ensure-file)
  (find-file my/types-file))

(defun my/node-types--maybe-watch ()
  "Reload types after saving the type registry file."
  (when (and buffer-file-name
             (bound-and-true-p my/types-file)
             (file-equal-p buffer-file-name my/types-file))
    (add-hook 'after-save-hook #'my/node-types-reload nil t)))

(add-hook 'find-file-hook #'my/node-types--maybe-watch)

(defun my/node-type-by-tag (tag)
  "Return the type whose tag is TAG, or nil."
  (cl-find tag my/node-types :key #'my/node-type-tag :test #'equal))

(defun my/node-types-for-tags (tags)
  "Return the types among TAGS, in registry order."
  (cl-remove-if-not (lambda (type) (member (my/node-type-tag type) tags))
                    my/node-types))

(defun my/node-read-type (&optional prompt types)
  "Read a type with PROMPT from TYPES (default: all types)."
  (let* ((types (or types my/node-types))
         (names (mapcar #'my/node-type-name types)))
    (unless types
      (user-error "No node types defined; add one with SPC # T"))
    (cl-find (completing-read (or prompt "Type: ") names nil t)
             types :key #'my/node-type-name :test #'equal)))

(defun my/node-type-capture-templates ()
  "Return capture templates (org-roam format) generated from `my/node-types'."
  (when my/node-types
    (let ((used (make-hash-table :test 'equal)))
      (cons
       '("t" "Typed note")
       (mapcar
        (lambda (type)
          (let* ((base (or (my/node-type-key type)
                           (substring (my/node-type-tag type) 0 1)))
                 (key base)
                 (n 1))
            (while (gethash key used)
              (setq key (format "%s%d" base (cl-incf n))))
            (puthash key t used)
            (list (concat "t" key)
                  (my/node-type-name type)
                  'plain
                  (let ((body (my/node-type-template type)))
                    (if (string-empty-p body) "%?" body))
                  :target
                  (list 'file+head
                        "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                        (format "#+title: ${title}\n#+filetags: :%s:\n"
                                (my/node-type-tag type)))
                  :unnarrowed t)))
        my/node-types)))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Node at point
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; These helpers read the buffer, not the database, so they also work on a
;; node captured a second ago that the indexer has not seen yet.

(defconst my/node--hidden-properties
  '("ID" "CATEGORY" "ALLTAGS" "TAGS" "FILE" "PRIORITY" "ITEM" "BLOCKED"
    "TODO" "CLOSED" "DEADLINE" "SCHEDULED" "TIMESTAMP" "TIMESTAMP_IA"
    "CLOCKSUM" "CLOCKSUM_T" "OLP" "ROAM_ALIASES" "ROAM_REFS" "ROAM_EXCLUDE"
    "STYLE" "LAST_REPEAT")
  "Org and org-roam properties that are not user fields.")

(defun my/node--ensure-org ()
  "Signal a user error unless the current buffer is an Org buffer."
  (unless (derived-mode-p 'org-mode)
    (user-error "Node commands work in Org buffers")))

(defun my/node-position (&optional create)
  "Return the start of the nearest node around point.
That is the nearest heading with an ID, else the file when it has one.
With CREATE, give the current heading (or the file, before the first
heading) an ID when no enclosing node exists."
  (my/node--ensure-org)
  (org-with-wide-buffer
   (let ((origin (point))
         found)
     (unless (org-before-first-heading-p)
       (org-back-to-heading t)
       (while (and (not found)
                   (progn
                     (when (org-entry-get nil "ID") (setq found (point)))
                     (and (not found) (org-up-heading-safe))))))
     (unless found
       (when (org-entry-get (point-min) "ID")
         (setq found (point-min))))
     (when (and (not found) create)
       (goto-char origin)
       (if (org-before-first-heading-p)
           (progn (goto-char (point-min)) (org-id-get-create))
         (org-back-to-heading t)
         (org-id-get-create))
       (setq found (if (org-before-first-heading-p) (point-min) (point))))
     found)))

(defun my/node--file-level-p (pos)
  "Return non-nil when POS is the file-level node."
  (save-excursion (goto-char pos) (org-before-first-heading-p)))

(defun my/node--file-tags ()
  "Return the #+filetags of the current buffer as a list."
  (let ((value (cadr (assoc "FILETAGS" (org-collect-keywords '("FILETAGS"))))))
    (and value (split-string value ":" t "[ \t]+"))))

(defun my/node--set-file-tags (tags)
  "Replace the #+filetags line of the current buffer with TAGS."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((line (and tags (format "#+filetags: :%s:" (string-join tags ":")))))
     (if (re-search-forward "^#\\+filetags:.*$" nil t)
         (if line
             (replace-match line t t)
           (delete-region (line-beginning-position)
                          (min (point-max) (1+ (line-end-position)))))
       (when line
         (goto-char (point-min))
         (if (re-search-forward "^#\\+title:.*$" nil t)
             (progn (end-of-line) (insert "\n" line))
           ;; After a leading property drawer, if any.
           (when (looking-at-p "[ \t]*:PROPERTIES:")
             (re-search-forward "^[ \t]*:END:[ \t]*\n" nil t))
           (insert line "\n")))))))

(defun my/node-tags-at (pos)
  "Return the local tags of the node starting at POS."
  (save-excursion
    (goto-char pos)
    (if (my/node--file-level-p pos)
        (my/node--file-tags)
      (org-get-tags nil t))))

(defun my/node--set-tags-at (pos tags)
  "Set the local tags of the node at POS to TAGS."
  (save-excursion
    (goto-char pos)
    (if (my/node--file-level-p pos)
        (my/node--set-file-tags tags)
      (org-set-tags tags))))

(defun my/node-types-at (pos)
  "Return the types of the node at POS."
  (my/node-types-for-tags (my/node-tags-at pos)))

(defun my/node--ensure-fields (pos type)
  "Add empty properties at POS for TYPE's fields that are missing."
  (dolist (field (my/node-type-fields type))
    (let ((name (plist-get field :name)))
      (unless (org-entry-get pos name)
        (org-entry-put pos name "")))))

(defun my/node--existing-values (field)
  "Return distinct values of property FIELD used anywhere in the library."
  (let ((values nil))
    (dolist (record (ignore-errors (my/index-records)))
      (when-let* ((value (cdr (assoc field (plist-get record :props)))))
        (unless (or (string-empty-p value) (member value values))
          (push value values))))
    (sort values #'string<)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Commands on the node at point
;; ═══════════════════════════════════════════════════════════════════════════

(defcustom my/node-add-empty-fields t
  "When non-nil, applying a type adds its fields as empty properties.
Empty fields show what can be filled in, as field slots do in Tana."
  :type 'boolean
  :group 'org-seq)

(defcustom my/node-single-type t
  "When non-nil, a node is an instance of one type, as with a Tana supertag.
Applying a type to a node that already has another one offers to replace
it.  Field values of the old type always stay on the node as ordinary
properties.  Notes that already carry several type tags keep working."
  :type 'boolean
  :group 'org-seq)

(defun my/node-set-type (type &optional replace)
  "Apply TYPE to the node at point (creating the node ID if needed).
REPLACE controls what happens to other types on the node: `replace'
removes them, `keep' keeps them, nil asks when `my/node-single-type' is
set and the session is interactive."
  (interactive (list (my/node-read-type "Add type: ")))
  (let* ((pos (my/node-position t))
         (tags (my/node-tags-at pos))
         (tag (my/node-type-tag type))
         (others (cl-remove tag (mapcar #'my/node-type-tag
                                        (my/node-types-for-tags tags))
                            :test #'equal)))
    (when (and others
               (or (eq replace 'replace)
                   (and (null replace) my/node-single-type
                        (not noninteractive)
                        (y-or-n-p (format "Replace type %s with %s (fields stay)? "
                                          (string-join others ", ")
                                          (my/node-type-name type))))))
      (setq tags (cl-remove-if (lambda (tg) (member tg others)) tags))
      (my/node--set-tags-at pos tags))
    (unless (member tag tags)
      (my/node--set-tags-at pos (append tags (list tag))))
    (when my/node-add-empty-fields
      (my/node--ensure-fields (my/node-position) type))
    (message "Type %s applied" (my/node-type-name type))))

(defun my/node-remove-type ()
  "Remove one of the node's types.  Field values are kept."
  (interactive)
  (let* ((pos (or (my/node-position) (user-error "Not inside a node")))
         (types (or (my/node-types-at pos)
                    (user-error "This node has no type")))
         (type (my/node-read-type "Remove type: " types)))
    (my/node--set-tags-at pos (remove (my/node-type-tag type)
                                      (my/node-tags-at pos)))
    (message "Type %s removed; its field values stay on the node"
             (my/node-type-name type))))

(defun my/node--read-field-value (field-name spec types current)
  "Read a value for FIELD-NAME described by SPEC among TYPES.
CURRENT is the existing value, offered as the default."
  (pcase (plist-get spec :kind)
    ('node
     (let ((node (my/node-read (format "%s (node): " field-name))))
       (format "[[id:%s][%s]]" (plist-get node :id)
               (plist-get node :title))))
    ('date
     (org-read-date nil nil nil (format "%s (date): " field-name)))
    ('number
     (let ((value (read-string (format "%s (number): " field-name) current)))
       (unless (or (string-empty-p value)
                   (string-match-p "\\`-?[0-9]+\\(?:\\.[0-9]+\\)?\\'" value))
         (user-error "%s expects a number" field-name))
       value))
    ('check
     (completing-read (format "%s: " field-name) '("yes" "no") nil t))
    (_
    (let ((choices (or (cl-some (lambda (type)
                                  (cdr (assoc field-name
                                              (my/node-type-choices type))))
                                types)
                       (my/node--existing-values field-name))))
      (completing-read (format "%s: " field-name) choices nil nil
                       (and current (not (string-empty-p current)) current))))))

(defun my/node-set-field-at (pos)
  "Prompt for a field of the node at POS and set it."
  (let* ((types (my/node-types-at pos))
         (specs (cl-loop for type in types append (my/node-type-fields type)))
         (present (cl-remove-if
                   (lambda (key) (member key my/node--hidden-properties))
                   (mapcar #'car (org-entry-properties pos 'standard))))
         (names (delete-dups (append (mapcar (lambda (s) (plist-get s :name)) specs)
                                     present)))
         (name (upcase (completing-read "Field: " names nil nil)))
         (spec (cl-find name specs :key (lambda (s) (plist-get s :name))
                        :test #'equal))
         (value (my/node--read-field-value name spec types
                                           (org-entry-get pos name))))
    (org-entry-put pos name value)
    (cons name value)))

(defun my/node-set-field ()
  "Set a field (Org property) on the node at point."
  (interactive)
  (let* ((pos (or (my/node-position) (user-error "Not inside a node")))
         (result (my/node-set-field-at pos)))
    (message "%s = %s" (car result) (cdr result))))

(defun my/node-copy-id-link ()
  "Copy an id link to the node at point (creating the ID if needed)."
  (interactive)
  (let* ((pos (my/node-position t))
         (id (org-entry-get pos "ID"))
         (title (save-excursion
                  (goto-char pos)
                  (if (my/node--file-level-p pos)
                      (or (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))
                          (file-name-base (or buffer-file-name (buffer-name))))
                    (org-get-heading t t t t))))
         (link (format "[[id:%s][%s]]" id title)))
    (kill-new link)
    (message "Copied: %s" link)))

(defun my/node-capture-region-as-note (title)
  "Extract the active region into a new note titled TITLE.
The region is replaced by a link to the new note, and the new note links
back to the node the text came from."
  (interactive
   (progn
     (unless (use-region-p) (user-error "Select a region first"))
     (list (read-string "New note title: "))))
  (my/node--ensure-org)
  (let* ((beg (region-beginning))
         (end (region-end))
         (text (buffer-substring-no-properties beg end))
         (source-id (org-entry-get (my/node-position t) "ID"))
         (note (my/note-create
                :title title
                :body (concat (string-trim-right text) "\n\n* Source\n"
                              (format "[[id:%s]]\n" source-id)))))
    (delete-region beg end)
    (goto-char beg)
    (deactivate-mark)
    (insert (format "[[id:%s][%s]]" (plist-get note :id) title))
    (message "Extracted to %s" (file-relative-name (plist-get note :file) my/note-home))
    note))

(defun my/node-promote ()
  "Turn the region or current heading into a node.
With an active region, extract it to a new note and leave a link.
Otherwise give the heading an ID so it can be linked, typed, and found
in place, as any block can be referenced in Tana."
  (interactive)
  (my/node--ensure-org)
  (if (use-region-p)
      (call-interactively #'my/node-capture-region-as-note)
    (when (org-before-first-heading-p)
      (user-error "Move to a heading, or select a region to extract"))
    (org-back-to-heading t)
    (let ((had-id (org-entry-get nil "ID")))
      (org-id-get-create)
      (if (and my/node-types (y-or-n-p (format "%s.  Add a type? "
                                               (if had-id "Already a node"
                                                 "Heading is now a node"))))
          (call-interactively #'my/node-set-type)
        (message (if had-id "Already a node" "Heading is now a node"))))))

(defun my/node--type-capture-template (type)
  "Return the generated capture template of TYPE."
  (or (cl-find (my/node-type-name type)
               (cdr (my/node-type-capture-templates))
               :key #'cadr :test #'equal)
      (user-error "Type %s has no capture template" (my/node-type-name type))))

(defun my/node-capture (type title &optional fields)
  "Create a new note of TYPE titled TITLE and visit it.
FIELDS is an alist of (FIELD . VALUE) to set on the new note; a view
passes the values it filters or groups by."
  (interactive (list (my/node-read-type "New note of type: ")
                     (read-string "Title: ")))
  (my/note-capture title (my/node--type-capture-template type) fields))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Queries
;; ═══════════════════════════════════════════════════════════════════════════

(defcustom my/node-review-days 14
  "Age limit in days for notes listed by `my/node-review'."
  :type 'integer
  :group 'org-seq)

(defun my/node--nodes ()
  "Return every node as a record from the kernel index (see orgseq-index)."
  (my/index-records))

(defun my/node-field (node field)
  "Return the value of FIELD on record NODE as a string (empty when unset)."
  (or (cdr (assoc field (plist-get node :props))) ""))

(defun my/node-aliases (record)
  "Return the ROAM_ALIASES values of RECORD as a list of strings."
  (let ((value (cdr (assoc "ROAM_ALIASES" (plist-get record :props)))))
    (and value (not (string-empty-p value))
         (split-string-and-unquote value))))

(defun my/node-candidates (records &optional aliases)
  "Return a hash table from completion label to record for RECORDS.
Nodes sharing a title are told apart by their file name.  With ALIASES,
each ROAM_ALIASES value is an extra label, shown as \"ALIAS -> TITLE\"."
  (let ((seen (make-hash-table :test 'equal))
        (table (make-hash-table :test 'equal)))
    (dolist (record records)
      (puthash (plist-get record :title)
               (1+ (gethash (plist-get record :title) seen 0)) seen))
    (cl-flet ((add (label record)
                (let ((n 1)
                      (key label))
                  (while (gethash key table)
                    (setq n (1+ n) key (format "%s <%d>" label n)))
                  (puthash key record table))))
      (dolist (record records)
        (let ((title (plist-get record :title)))
          (add (if (> (gethash title seen) 1)
                   (format "%s  (%s)" title (file-name-base (plist-get record :file)))
                 title)
               record)))
      (when aliases
        (dolist (record records)
          (dolist (alias (my/node-aliases record))
            (add (format "%s -> %s" alias (plist-get record :title)) record)))))
    table))

(defun my/node-read (&optional prompt)
  "Read a node with completion and return its record.
PROMPT defaults to \"Node: \".  Aliases are offered as well."
  (let ((table (my/node-candidates (my/index-records) t)))
    (unless (> (hash-table-count table) 0)
      (user-error "The library has no nodes yet"))
    (gethash (completing-read (or prompt "Node: ") table nil t) table)))

(defun my/node--read-or-new (prompt)
  "Read a node with PROMPT; return its record, or the typed text when new.
The text is returned as a string so the caller can offer to create a
note with that title."
  (let* ((table (my/node-candidates (my/index-records) t))
         (input (string-trim (completing-read prompt table nil nil))))
    (cond
     ((string-empty-p input) (user-error "No node given"))
     ((gethash input table))
     (t input))))

(defun my/node-visit (node &optional other-window)
  "Visit record NODE (or the node with that id) at its heading.
OTHER-WINDOW shows it in another window."
  (let* ((record (if (stringp node)
                     (or (my/index-node node)
                         (user-error "Node %s is not in the index" node))
                   node))
         (file (plist-get record :file)))
    (unless (and file (file-exists-p file))
      (user-error "The file of node %s is gone; refresh the view" (plist-get record :id)))
    (if other-window (find-file-other-window file) (find-file file))
    (let ((pos (if (eql 0 (plist-get record :level))
                   (point-min)
                 (or (org-find-property "ID" (plist-get record :id))
                     (plist-get record :pos)))))
      (unless (<= (point-min) pos (point-max)) (widen))
      (goto-char pos)
      (when (and (derived-mode-p 'org-mode) (org-at-heading-p))
        (org-fold-show-context 'link-search)))
    record))

(defun my/node--link-counts ()
  "Return a cons (INCOMING . OUTGOING) of hash tables: node id -> id links."
  (let ((in (make-hash-table :test 'equal))
        (out (make-hash-table :test 'equal)))
    (pcase-dolist (`(,source ,dest) (my/index-links))
      (puthash dest (1+ (gethash dest in 0)) in)
      (puthash source (1+ (gethash source out 0)) out))
    (cons in out)))

(defun my/node--mtime-days (node)
  "Return the age in days of NODE's file."
  (let ((mtime (plist-get node :mtime)))
    (if mtime
        (/ (float-time (time-subtract nil mtime)) 86400.0)
      most-positive-fixnum)))

(defun my/node-query (&rest spec)
  "Return nodes matching SPEC, a plist of filters and ordering.
:tag            tag the node must have
:type           like :tag, and also matches types that extend it
:where          list of (FIELD VALUE) pairs that must match exactly
:recent-days N  file modified within N days
:sort FIELD     \"title\", \"modified\", or a field name
:order          `asc' (default) or `desc'
:limit N        at most N nodes"
  (let* ((tag (or (plist-get spec :tag) (plist-get spec :type)))
         (family (and tag
                      (if (plist-get spec :type)
                          (my/node-type-family-tags (format "%s" tag))
                        (list (format "%s" tag)))))
         (where (plist-get spec :where))
         (recent (plist-get spec :recent-days))
         (sort-key (format "%s" (or (plist-get spec :sort) "title")))
         (desc (member (plist-get spec :order) '(desc "desc")))
         (limit (plist-get spec :limit))
         (nodes
          (cl-remove-if-not
           (lambda (node)
             (and (or (null family)
                      (cl-intersection family (plist-get node :tags)
                                       :test #'equal))
                  (cl-every (lambda (pair)
                              (equal (my/node-field node (format "%s" (car pair)))
                                     (format "%s" (if (consp (cdr pair))
                                                      (cadr pair)
                                                    (cdr pair)))))
                            where)
                  (or (null recent) (<= (my/node--mtime-days node) recent))))
           (my/node--nodes)))
         (key-fn (pcase (downcase sort-key)
                   ("title" (lambda (n) (plist-get n :title)))
                   ("modified" (lambda (n) (format-time-string
                                            "%Y%m%d%H%M%S"
                                            (plist-get n :mtime))))
                   (_ (lambda (n) (my/node-field n (upcase sort-key))))))
         (sorted (sort nodes (lambda (a b)
                               (my/node--value< (funcall key-fn a)
                                                (funcall key-fn b))))))
    (when desc (setq sorted (nreverse sorted)))
    (if (and limit (> (length sorted) limit))
        (cl-subseq sorted 0 limit)
      sorted)))

(defun my/node--value< (a b)
  "Compare field values A and B: numerically when both are numbers."
  (let ((na (and (string-match-p "\\`-?[0-9.]+\\'" a) (string-to-number a)))
        (nb (and (string-match-p "\\`-?[0-9.]+\\'" b) (string-to-number b))))
    (if (and na nb) (< na nb) (string< a b))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: Table views
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; One row per node, one column per field.  Click a column header (or S) to
;; sort, / to filter, RET to open, f to edit a field in place, + to create a
;; node of the viewed type, g to refresh.

(defvar-local my/node-view--spec nil
  "Plist describing the current view: :title :type :rows-fn :columns.")

(defvar-local my/node-view--all-entries nil
  "Unfiltered entries of the current view.")

(defvar-local my/node-view--filter nil
  "Current filter string, or nil.")

(defvar-keymap my/node-view-mode-map
  :parent tabulated-list-mode-map
  "RET" #'my/node-view-open
  "o"   #'my/node-view-open-other-window
  "f"   #'my/node-view-set-field
  "+"   #'my/node-view-new
  "/"   #'my/node-view-filter
  "g"   #'revert-buffer)

(define-derived-mode my/node-view-mode tabulated-list-mode "Nodes"
  "Table of nodes.
\\{my/node-view-mode-map}"
  (setq-local tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook #'my/node-view--refresh nil t))

(defun my/node--column-width (name values)
  "Return a column width for NAME given its VALUES."
  (min 32 (max (+ 2 (length name))
               (apply #'max 6 (mapcar #'string-width values)))))

(defun my/node--display-value (value)
  "Return VALUE with Org links reduced to their description."
  (org-link-display-format (or value "")))

(defun my/node-view--sorter (index)
  "Return a tabulated-list sort predicate for column INDEX."
  (lambda (a b)
    (my/node--value< (aref (cadr a) index) (aref (cadr b) index))))

(defun my/node-view--refresh ()
  "Recompute rows and columns of the current view."
  (let* ((spec my/node-view--spec)
         (columns (plist-get spec :columns))
         (rows (funcall (plist-get spec :rows-fn)))
         (entries
          (mapcar (lambda (row)
                    (list (car row)
                          (apply #'vector (mapcar #'my/node--display-value
                                                  (cdr row)))))
                  rows))
         (index -1))
    (setq my/node-view--all-entries entries)
    (setq tabulated-list-format
          (apply #'vector
                 (mapcar (lambda (name)
                           (cl-incf index)
                           (let ((values (mapcar (lambda (e) (aref (cadr e) index))
                                                 entries)))
                             (list name
                                   (if (= index 0)
                                       (min 48 (max 24 (apply #'max 5 (mapcar #'string-width values))))
                                     (my/node--column-width name values))
                                   (my/node-view--sorter index))))
                         columns)))
    (my/node-view--apply-filter)
    (tabulated-list-init-header)
    (setq mode-line-process
          (format "  %d of %d" (length tabulated-list-entries) (length entries)))))

(defun my/node-view--apply-filter ()
  "Restrict `tabulated-list-entries' to rows matching the filter."
  (setq tabulated-list-entries
        (if (not my/node-view--filter)
            my/node-view--all-entries
          (cl-remove-if-not
           (lambda (entry)
             (cl-some (lambda (cell)
                        (string-match-p (regexp-quote my/node-view--filter) cell))
                      (cadr entry)))
           my/node-view--all-entries))))

(defun my/node-view--show (name spec)
  "Display a node view buffer called NAME for SPEC."
  (let ((buffer (get-buffer-create (format "*%s*" name))))
    (with-current-buffer buffer
      (my/node-view-mode)
      (setq my/node-view--spec spec)
      (my/node-view--refresh)
      (tabulated-list-print))
    (pop-to-buffer-same-window buffer)))

(declare-function my/view-show-type "init-views" (type))

(defun my/node-view (type)
  "Show the view of all nodes of TYPE.
With init-views loaded this opens the type's saved view (table, list or
board); otherwise it falls back to the plain table below."
  (interactive (list (my/node-read-type "View type: ")))
  (if (fboundp 'my/view-show-type)
      (my/view-show-type type)
    (my/node-view--table type)))

(defun my/node-view--table (type)
  "Show the plain table of all nodes of TYPE."
  (let* ((fields (mapcar (lambda (f) (plist-get f :name))
                         (my/node-type-fields type)))
         (tag (my/node-type-tag type)))
    (my/node-view--show
     (format "%s nodes" (my/node-type-name type))
     (list :title (my/node-type-name type)
           :type type
           :columns (append '("Title") fields '("Modified"))
           :rows-fn
           (lambda ()
             (mapcar (lambda (node)
                       (append (list (plist-get node :id)
                                     (plist-get node :title))
                               (mapcar (lambda (f) (my/node-field node f)) fields)
                               (list (format-time-string
                                      "%Y-%m-%d" (plist-get node :mtime)))))
                     (my/node-query :type tag :sort "modified" :order 'desc)))))))

(defun my/node--daily-p (node)
  "Return non-nil when NODE lives in a Daily note.
Daily files are the running log; the review covers notes meant to stand
on their own."
  (or (member "daily" (plist-get node :tags))
      (let ((file (plist-get node :file)))
        (and file (file-in-directory-p
                   file (my/daily-dir))))))

(defun my/node-review ()
  "Review recent notes that have no type or no links yet.
This is the tidy-up pass of the weekly workflow: give each note a type,
link it, or leave it as a deliberate fragment."
  (interactive)
  (my/node-view--show
   "Review"
   (list :title "Review"
         :columns '("Title" "Types" "In" "Out" "Modified")
         :rows-fn
         (lambda ()
           (let* ((counts (my/node--link-counts))
                  (type-tags (mapcar #'my/node-type-tag my/node-types)))
             (delq nil
                   (mapcar
                    (lambda (node)
                      (let* ((id (plist-get node :id))
                             (in (gethash id (car counts) 0))
                             (out (gethash id (cdr counts) 0))
                             (types (cl-intersection (plist-get node :tags)
                                                     type-tags :test #'equal)))
                        (when (and (or (null types) (= 0 (+ in out)))
                                   (not (my/node--daily-p node)))
                          (list id (plist-get node :title)
                                (string-join types " ")
                                (number-to-string in) (number-to-string out)
                                (format-time-string
                                 "%Y-%m-%d" (plist-get node :mtime))))))
                    (my/node-query :recent-days my/node-review-days
                                   :sort "modified" :order 'desc))))))))

(defun my/node-view--node ()
  "Return the record of the node on the current row."
  (let ((id (tabulated-list-get-id)))
    (unless id (user-error "No node on this line"))
    (or (my/index-node id)
        (user-error "Node %s is no longer in the index; press g" id))))

(defun my/node-view-open ()
  "Open the node on the current row."
  (interactive)
  (my/node-visit (my/node-view--node)))

(defun my/node-view-open-other-window ()
  "Open the node on the current row in another window."
  (interactive)
  (my/node-visit (my/node-view--node) t))

(defun my/node-call-at-id (id fn)
  "Call FN with the buffer position of node ID, then save and re-index.
FN runs in the node's file buffer with the buffer widened.  This is the
single write path for views, the command line and MCP tools: the change
lands in the Org file and the index follows."
  (let* ((node (or (my/index-node id)
                   (user-error "Node %s is not in the index" id)))
         (file (plist-get node :file))
         result)
    (with-current-buffer (find-file-noselect file)
      (let ((pos (org-find-property "ID" id)))
        (unless pos (user-error "Cannot find node %s in %s" id file))
        (org-with-wide-buffer
         (setq result (funcall fn pos)))
        (save-buffer)))
    (my/index-update-file file)
    result))

(defun my/node-set-field-by-id (id name value)
  "Set field NAME of node ID to VALUE; an empty or nil VALUE clears it."
  (my/node-call-at-id
   id (lambda (pos)
        (if (or (null value) (string-empty-p value))
            (org-entry-delete pos (upcase name))
          (org-entry-put pos (upcase name) value)))))

(defun my/node-view-set-field ()
  "Edit a field of the node on the current row without leaving the view."
  (interactive)
  (let* ((node (my/node-view--node))
         (line (line-number-at-pos)))
    (my/node-call-at-id (plist-get node :id) #'my/node-set-field-at)
    (revert-buffer)
    (goto-char (point-min))
    (forward-line (1- line))))

(defun my/node-view-new ()
  "Create a node of the viewed type."
  (interactive)
  (if-let* ((type (plist-get my/node-view--spec :type)))
      (my/node-capture type (read-string (format "New %s: " (my/node-type-name type))))
    (call-interactively #'my/node-capture)))

(defun my/node-view-filter (text)
  "Show only rows containing TEXT; empty TEXT clears the filter."
  (interactive (list (read-string "Filter (empty clears): " my/node-view--filter)))
  (setq my/node-view--filter (unless (string-empty-p text) text))
  (my/node-view--apply-filter)
  (tabulated-list-print t)
  (setq mode-line-process
        (format "  %d of %d%s" (length tabulated-list-entries)
                (length my/node-view--all-entries)
                (if my/node-view--filter
                    (format "  filter: %s" my/node-view--filter)
                  ""))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 7: Dashboard dynamic blocks
;; ═══════════════════════════════════════════════════════════════════════════
;;
;;   #+BEGIN: orgseq-query :type "reading" :where (("STATUS" "queued")) :columns ("AUTHORS" "YEAR") :sort "YEAR"
;;   #+END:
;;
;; Parameters are those of `my/node-query' plus :columns (default: the
;; type's fields).  Rows link to their nodes.  Blocks written for the
;; retired supertag-query block keep working for the common subset
;; (tag, property, and, recent-days); see `my/node--translate-supertag-query'.

(defun my/node--table-cell (value)
  "Escape VALUE for an Org table cell."
  (replace-regexp-in-string "|" "\\\\vert{}" (or value "") t t))

(defun my/node-insert-query-table (params)
  "Insert an Org table of the nodes selected by PARAMS."
  (let* ((tag (or (plist-get params :type) (plist-get params :tag)))
         (type (and tag (my/node-type-by-tag (format "%s" tag))))
         (columns (or (plist-get params :columns)
                      (and type (mapcar (lambda (f) (plist-get f :name))
                                        (my/node-type-fields type)))))
         (nodes (apply #'my/node-query params)))
    (if (null nodes)
        (insert "/No matching nodes./")
      (insert "| Title | " (mapconcat #'identity columns " | ") " |\n|-\n")
      (dolist (node nodes)
        (insert "| "
                (my/node--table-cell
                 (format "[[id:%s][%s]]" (plist-get node :id)
                         (plist-get node :title)))
                " | "
                (mapconcat (lambda (c) (my/node--table-cell (my/node-field node c)))
                           columns " | ")
                " |\n"))
      (delete-char -1)
      (org-table-align))))

(defun org-dblock-write:orgseq-query (params)
  "Write an `orgseq-query' dynamic block from PARAMS."
  (my/node-insert-query-table params))

(defun my/node--translate-supertag-query (form)
  "Translate a supertag query FORM into `my/node-query' parameters.
Supports (tag T), (property K V), (recent-days N) and (and ...)."
  (pcase form
    (`(tag ,tag) (list :tag tag))
    (`(property ,key ,value) (list :where (list (list (upcase key) value))))
    (`(recent-days ,n) (list :recent-days n))
    (`(and . ,forms)
     (let (result where)
       (dolist (f forms)
         (let ((p (my/node--translate-supertag-query f)))
           (setq where (append where (plist-get p :where)))
           (cl-remf p :where)
           (setq result (append result p))))
       (if where (append result (list :where where)) result)))
    (_ (user-error "Unsupported supertag query form: %S" form))))

(defun org-dblock-write:supertag-query (params)
  "Render a retired supertag-query block from PARAMS with index data."
  (let* ((query (plist-get params :query))
         (form (if (stringp query) (car (read-from-string query)) query))
         (translated (condition-case err
                         (my/node--translate-supertag-query form)
                       (user-error (insert (format "/%s/" (error-message-string err)))
                                   nil))))
    (when translated
      (my/node-insert-query-table
       (append translated
               (list :columns (plist-get params :columns)
                     :sort (plist-get params :sort)
                     :order (plist-get params :order)
                     :limit (plist-get params :limit)))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 8: Node action menu
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/node-action ()
  "Open the action menu for the node at point (Tana command line)."
  (interactive)
  (my/node--ensure-org)
  (let* ((pos (my/node-position))
         (types (and pos (my/node-types-at pos)))
         (actions
          (append
           (when (use-region-p)
             '(("Extract region to new note" . my/node-capture-region-as-note)))
           (unless pos
             '(("Make this heading a node" . my/node-promote)))
           '(("Add type" . my/node-set-type))
           (when types
             '(("Set field" . my/node-set-field)
               ("Remove type" . my/node-remove-type)))
           (mapcar (lambda (type)
                     (cons (format "View all %s nodes" (my/node-type-name type))
                           (lambda () (interactive) (my/node-view type))))
                   types)
           '(("Insert link to another node" . my/node-insert-link)
             ("Show backlinks" . my/node-backlinks)
             ("Copy node link" . my/node-copy-id-link)
             ("Add alias" . my/node-add-alias)
             ("Edit any Org property" . org-set-property)
             ("New note of a type" . my/node-capture)
             ("Review unsorted notes" . my/node-review))))
         (choice (completing-read
                  (if types
                      (format "Node [%s]: "
                              (mapconcat #'my/node-type-name types ", "))
                    "Node: ")
                  (mapcar #'car actions) nil t)))
    (call-interactively (cdr (assoc choice actions)))))

;; ---- Find, insert link, alias ----

(defun my/node-find ()
  "Visit a node chosen by title or alias.
Text that names no node offers to capture a new note with that title."
  (interactive)
  (let ((choice (my/node--read-or-new "Find node: ")))
    (if (stringp choice)
        (when (y-or-n-p (format "No node \"%s\".  Create it? " choice))
          (my/note-capture choice))
      (my/node-visit choice))))

(defun my/node--insert-position ()
  "In Evil normal state, move after the character at point before inserting.
That is where a link typed with `a' would land."
  (when (and (bound-and-true-p evil-local-mode)
             (fboundp 'evil-normal-state-p)
             (evil-normal-state-p)
             (not (eolp)))
    (forward-char)))

(defun my/node-insert-link ()
  "Insert an id link to a node chosen by title or alias.
With an active region, the region becomes the link description.  Text
that names no node offers to create a note with that title (the note is
written without leaving the current buffer)."
  (interactive)
  (let* ((region (and (use-region-p)
                      (cons (region-beginning) (region-end))))
         (description (and region (buffer-substring-no-properties
                                   (car region) (cdr region))))
         (choice (my/node--read-or-new "Link to node: "))
         (target (if (stringp choice)
                     (if (y-or-n-p (format "No node \"%s\".  Create it? " choice))
                         (save-window-excursion
                           (save-excursion (my/note-capture choice nil nil t)))
                       (user-error "Nothing inserted"))
                   choice))
         (link (format "[[id:%s][%s]]" (plist-get target :id)
                       (or description (plist-get target :title)))))
    (if region
        (progn (delete-region (car region) (cdr region))
               (goto-char (car region))
               (deactivate-mark))
      (my/node--insert-position))
    (insert link)
    link))

(defun my/node-add-alias (alias)
  "Add ALIAS to the ROAM_ALIASES of the node at point.
Node find offers aliases next to titles."
  (interactive (list (read-string "Alias: ")))
  (let* ((pos (my/node-position t))
         (current (org-entry-get pos "ROAM_ALIASES"))
         (aliases (and current (split-string-and-unquote current))))
    (when (string-empty-p (string-trim alias))
      (user-error "Empty alias"))
    (unless (member alias aliases)
      (org-entry-put pos "ROAM_ALIASES"
                     (combine-and-quote-strings (append aliases (list alias)))))
    (message "Aliases: %s" (org-entry-get pos "ROAM_ALIASES"))))

;; ---- Backlinks ----

(defun my/node-backlink-records (id)
  "Return the records of nodes that link to node ID, sorted by title.
Each node appears once, however many links it has."
  (let ((sources nil))
    (pcase-dolist (`(,source ,dest) (my/index-links))
      (when (and (equal dest id) (not (equal source id)))
        (cl-pushnew source sources :test #'equal)))
    (sort (delq nil (mapcar #'my/index-node sources))
          (lambda (a b) (string< (plist-get a :title) (plist-get b :title))))))

(defconst my/node-backlinks-buffer-name "*Backlinks*"
  "Buffer name of the backlinks list.")

(defvar-local my/node-backlinks--id nil
  "Id of the node whose backlinks the current buffer lists.")

(defvar-keymap my/node-backlinks-mode-map
  :parent special-mode-map
  "RET" #'my/node-backlinks-visit
  "o"   #'my/node-backlinks-visit-other-window
  "g"   #'my/node-backlinks-refresh)

(define-derived-mode my/node-backlinks-mode special-mode "Backlinks"
  "List of nodes that link to one node.
\\{my/node-backlinks-mode-map}"
  (setq-local truncate-lines t))

(defun my/node-backlinks-refresh ()
  "Redraw the backlinks list from the index."
  (interactive)
  (let* ((id my/node-backlinks--id)
         (node (my/index-node id))
         (records (my/node-backlink-records id))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (format "Links to %s" (if node (plist-get node :title) id))
                        'face 'bold)
            (format "  (%d)\n\n" (length records)))
    (if (null records)
        (insert "No node links here yet.\n")
      (dolist (record records)
        (insert (propertize
                 (concat "  " (plist-get record :title)
                         (propertize
                          (format "  %s" (file-relative-name (plist-get record :file)
                                                             my/note-home))
                          'face 'shadow))
                 'my/node-id (plist-get record :id)
                 'mouse-face 'highlight)
                "\n")))
    (goto-char (point-min))
    (forward-line 2)))

(defun my/node-backlinks (&optional id)
  "List the nodes that link to node ID (default: the node at point).
RET visits the node on the line."
  (interactive)
  (let* ((id (or id
                 (and (derived-mode-p 'org-mode)
                      (when-let* ((pos (my/node-position)))
                        (org-entry-get pos "ID")))
                 (user-error "Not inside a node")))
         (buffer (get-buffer-create my/node-backlinks-buffer-name)))
    (with-current-buffer buffer
      (my/node-backlinks-mode)
      (setq my/node-backlinks--id id)
      (my/node-backlinks-refresh))
    (display-buffer buffer)
    buffer))

(defun my/node-backlinks--id-at-point ()
  "Return the id of the node on the current backlinks line."
  (or (get-text-property (line-beginning-position) 'my/node-id)
      (get-text-property (point) 'my/node-id)
      (user-error "No node on this line")))

(defun my/node-backlinks-visit ()
  "Visit the node on the current line."
  (interactive)
  (my/node-visit (my/node-backlinks--id-at-point)))

(defun my/node-backlinks-visit-other-window ()
  "Visit the node on the current line in another window."
  (interactive)
  (my/node-visit (my/node-backlinks--id-at-point) t))

;; ---- Following id links ----
;;
;; An [[id:]] link resolves through the kernel index first, which knows
;; every node in the library without Org's id-locations file, then falls
;; back to Org's own lookup (ids in files outside the index, or created a
;; moment ago in a buffer that was not saved yet).

(declare-function org-id-open "org-id" (id _))

(defun my/node-id-open (link &optional arg)
  "Open id LINK (ID or ID::SEARCH).  ARG is passed on to Org's id lookup."
  (let* ((parts (split-string link "::"))
         (id (car parts))
         (search (cadr parts))
         (record (ignore-errors (my/index-node id))))
    (if (and record (file-exists-p (plist-get record :file)))
        (progn
          (org-mark-ring-push)
          (my/node-visit record)
          (when search (org-link-search search)))
      (org-id-open link arg))))

(defun my/node-install-id-link-handler ()
  "Make [[id:]] links open through `my/node-id-open'."
  (org-link-set-parameters "id" :follow #'my/node-id-open))

(with-eval-after-load 'org-id
  (my/node-install-id-link-handler))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 9: Dashboard files, PARA navigation, NoteHQ bootstrap
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Dashboards are read-only query pages in 00_Roam/dashboards/.  Opening
;; one refreshes its dynamic blocks.  They are never used for data entry.

(defun my/dashboard-open (name)
  "Open dashboard NAME (without .org) and refresh all dynamic blocks."
  (let ((file (expand-file-name (concat name ".org") my/dashboards-dir)))
    (if (file-exists-p file)
        (progn
          (find-file file)
          (condition-case err
              (org-update-all-dblocks)
            (error
             (message "org-seq: dashboard refresh failed: %s" err))))
      (message "org-seq: dashboard not found: %s" file))))

(defun my/dashboard-find ()
  "Pick and open a dashboard from the dashboards directory."
  (interactive)
  (make-directory my/dashboards-dir t)
  (let* ((files (directory-files my/dashboards-dir nil "\\.org\\'"))
         (names (mapcar #'file-name-sans-extension files)))
    (if (null names)
        (when (y-or-n-p "No dashboards yet.  Create one? ")
          (call-interactively #'my/dashboard-create))
      (my/dashboard-open (completing-read "Dashboard: " names nil t)))))

(defun my/dashboard-create (name)
  "Create a dashboard NAME with a query block for a chosen type."
  (interactive "sDashboard name: ")
  (let ((file (expand-file-name (concat name ".org") my/dashboards-dir))
        (type (and my/node-types (my/node-read-type "Query type: "))))
    (if (file-exists-p file)
        (progn (find-file file) (message "Dashboard already exists"))
      (make-directory my/dashboards-dir t)
      (find-file file)
      (insert (format "#+title: %s\n#+startup: content\n\n* Nodes\n" name)
              (format "#+BEGIN: orgseq-query :type %S :sort \"modified\" :order desc\n"
                      (if type (my/node-type-tag type) "TAG"))
              "#+END:\n")
      (save-buffer)
      (when type (org-update-all-dblocks))
      (message "org-seq: dashboard %s created; edit the block parameters to refine it"
               name))))

(defun my/dash-index  () "Open dashboard index." (interactive) (my/dashboard-open "index"))
(defun my/dash-review () "Open weekly review."   (interactive) (my/dashboard-open "weekly-review"))

(defun my/find-in-outputs ()
  "Find file in Outputs/ (deliverable projects)."
  (interactive)
  (let ((default-directory my/outputs-dir))
    (call-interactively #'find-file)))

(defun my/find-in-practice ()
  "Find file in Practice/ (long-term responsibility domains)."
  (interactive)
  (let ((default-directory my/practice-dir))
    (call-interactively #'find-file)))

(defun my/find-in-library ()
  "Find file in Library/ (reference materials)."
  (interactive)
  (let ((default-directory my/library-dir))
    (call-interactively #'find-file)))

(defun my/ripgrep-notehq ()
  "Ripgrep across entire NoteHQ (Roam + PARA layers)."
  (interactive)
  (consult-ripgrep my/note-home))

(defun my/ensure-notehq-structure ()
  "Create NoteHQ directory skeleton if missing.  Idempotent."
  (dolist (dir (list my/roam-dir
                     (my/daily-dir)
                     (my/note-capture-dir)
                     my/dashboards-dir
                     my/outputs-dir
                     my/practice-dir
                     my/library-dir
                     my/archives-dir))
    (make-directory dir t)))

(add-hook 'after-init-hook
          (lambda ()
            (run-with-idle-timer 0.5 nil #'my/ensure-notehq-structure)))

;; Types are read at startup (cheap: one small file) so views, queries and
;; capture work at once.  The starter types and template files are created
;; on the same idle pass as the directory skeleton.
(unless noninteractive
  (my/node-types-reload))

(defun my/node--ensure-library-files ()
  "Create the starter type registry and capture template file if missing."
  (my/node-types-ensure-file)
  (when (fboundp 'my/ensure-capture-templates-file)
    (my/ensure-capture-templates-file))
  (unless my/node-types (my/node-types-reload)))

(add-hook 'after-init-hook
          (lambda ()
            (run-with-idle-timer 0.6 nil #'my/node--ensure-library-files)))

(provide 'init-nodes)
;;; init-nodes.el ends here
