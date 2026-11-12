;;; init-palette.el --- Command palette, slash menu, field panel -*- lexical-binding: t; -*-
;;
;; The interaction layer over nodes, types and views:
;;
;;   Palette  `my/palette' (Tana command line): one completing-read over
;;            nodes, "#Type" (new note of a type), "@View" (open a saved
;;            view) and ">Command" entries.  Input that matches nothing
;;            offers to create a note with that title.
;;   Slash    `my/slash-mode' (Notion slash menu): typing "/" on an empty
;;            line of an Org buffer opens a menu of things to insert.
;;   Fields   `my/node-fields-mode' (Notion properties): shows the fields
;;            of a typed file-level node under its title.  The overlay is
;;            display only; the property drawer stays the source of truth.
;;
;; Nothing here stores note data.  Nodes come from the kernel index and
;; every write goes through the existing node functions.  Capture and node
;; visiting are reached through `my/palette--capture' and
;; `my/palette--visit', which use the first function that exists.
;;
;; Section 1  Wrappers and helpers
;; Section 2  Palette candidates, completion table, dispatch
;; Section 3  Slash menu
;; Section 4  Field panel

;; Requires: init-org   (my/note-home)
;; Requires: init-nodes (node index records, types, field setter)
;; Requires: init-views (saved views, orgseq-view dynamic block)
(defvar my/node-types)
(defvar org-capture-after-finalize-hook)
(defvar evil-local-mode)
(defvar my/slash-mode)
(defvar my/node-fields-mode)

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'orgseq-index)

(declare-function my/node--type-capture-template "init-nodes" (type))
(declare-function my/note-capture "init-capture" (&optional title template fields no-visit))
(declare-function evil-insert-state-p "evil-states" (&optional state))
(declare-function my/node-read "init-nodes" (&optional prompt))
(declare-function my/node-visit "init-nodes" (node &optional other-window))
(declare-function my/node-capture "init-nodes" (type title &optional fields))
(declare-function my/node-read-type "init-nodes" (&optional prompt types))
(declare-function my/node-type-name "init-nodes" (type))
(declare-function my/node-type-tag "init-nodes" (type))
(declare-function my/node-type-fields "init-nodes" (type))
(declare-function my/node-types-at "init-nodes" (pos))
(declare-function my/node--read-field-value "init-nodes"
                  (field-name spec types current))
(declare-function my/views-load "init-views" ())
(declare-function my/view-open "init-views" (name))

;; ---------------------------------------------------------------------------
;; Section 1: Wrappers and helpers
;; ---------------------------------------------------------------------------

(defconst my/palette--visit-candidates '(my/note-visit my/node-visit)
  "Functions tried in order to visit a node record.")

(defconst my/palette--read-candidates '(my/note-read my/node-read)
  "Functions tried in order to read a node; each takes an optional PROMPT.")

(defun my/palette--first-function (candidates)
  "Return the first bound function among CANDIDATES, or nil."
  (cl-find-if #'fboundp candidates))

(defun my/palette--capture (type title)
  "Create a note of TYPE (a type struct or nil) titled TITLE.
Return what the capture command returns (the new note)."
  (if type
      (my/node-capture type title)
    (my/note-capture title)))

(defun my/palette--visit (record)
  "Visit the node RECORD."
  (funcall (or (my/palette--first-function my/palette--visit-candidates)
               (user-error "No node visit function is available"))
           record))

(defun my/palette--read-node (&optional prompt)
  "Read a node with completion and return its record."
  (funcall (or (my/palette--first-function my/palette--read-candidates)
               (user-error "No node reader is available"))
           prompt))

(defun my/palette--node-labels (records)
  "Return an alist (LABEL . RECORD) for RECORDS with unique labels.
Nodes sharing a title are told apart by file name, then by a counter."
  (let ((counts (make-hash-table :test 'equal))
        (taken (make-hash-table :test 'equal))
        result)
    (dolist (record records)
      (cl-incf (gethash (plist-get record :title) counts 0)))
    (dolist (record records)
      (let* ((title (or (plist-get record :title) ""))
             (label (if (> (gethash title counts) 1)
                        (format "%s  (%s)" title
                                (file-name-base (or (plist-get record :file) "")))
                      title))
             (key label)
             (n 1))
        (while (gethash key taken)
          (setq n (1+ n) key (format "%s <%d>" label n)))
        (puthash key t taken)
        (push (cons key record) result)))
    (nreverse result)))

;; ---------------------------------------------------------------------------
;; Section 2: Palette candidates, completion table, dispatch
;; ---------------------------------------------------------------------------

(defcustom my/palette-commands
  '(("Sync now" . my/sync-now)
    ("Sync preview" . my/sync-preview)
    ("Sync status" . my/sync-status)
    ("Snapshot library" . my/storage-snapshot)
    ("Browse snapshots" . my/storage-browse-snapshots)
    ("Storage status" . my/storage-status)
    ("Doctor" . my/doctor)
    ("Review unsorted notes" . my/node-review)
    ("Node actions" . my/node-action)
    ("Set type" . my/node-set-type)
    ("Remove type" . my/node-remove-type)
    ("Set field" . my/node-set-field)
    ("Edit field panel" . my/node-fields-edit)
    ("Toggle field panel" . my/node-fields-toggle)
    ("New view" . my/view-new-view)
    ("Edit views" . my/views-edit)
    ("Edit types" . my/node-types-edit)
    ("Today's Daily" . my/daily-workspace-open)
    ("Open dashboard" . my/dashboard-find)
    ("Search text" . my/palette-search-text))
  "Commands listed in the palette as \">Label\", as (LABEL . COMMAND).
Entries whose command is not defined when the palette opens are skipped."
  :type '(alist :key-type (string :tag "Label")
                :value-type (symbol :tag "Command"))
  :group 'org-seq)

(defconst my/palette--groups
  '((node . "Nodes") (type . "New note") (view . "Views") (command . "Commands"))
  "Group title of each candidate kind.")

(defun my/palette--available-commands (&optional commands)
  "Return COMMANDS (default `my/palette-commands') whose function exists."
  (cl-remove-if-not (lambda (cell) (fboundp (cdr cell)))
                    (or commands my/palette-commands)))

(defun my/palette--candidates (records types views commands)
  "Return the palette candidates as an alist (LABEL . (KIND DATA NOTE)).
RECORDS are node records, TYPES type structs, VIEWS view plists and
COMMANDS an alist of (LABEL . COMMAND).  KIND is `node', `type', `view'
or `command'; DATA is the record, type, view name or command symbol; NOTE
is the text shown beside the label."
  (append
   (mapcar (lambda (cell)
             (let* ((record (cdr cell))
                    (tags (plist-get record :tags))
                    (note (string-join
                           (delq nil
                                 (list (and tags (mapconcat (lambda (tag)
                                                              (concat "#" tag))
                                                            tags " "))
                                       (and (> (or (plist-get record :level) 0) 0)
                                            (file-name-base
                                             (or (plist-get record :file) "")))))
                           "  ")))
               (list (car cell) 'node record note)))
           (my/palette--node-labels records))
   (mapcar (lambda (type)
             (let ((count (length (my/node-type-fields type))))
               (list (concat "#" (my/node-type-name type)) 'type type
                     (format "new note, %d field%s" count
                             (if (= count 1) "" "s")))))
           types)
   (mapcar (lambda (view)
             (list (concat "@" (plist-get view :name)) 'view
                   (plist-get view :name)
                   (format "%s view" (or (plist-get view :layout) 'table))))
           views)
   (mapcar (lambda (cell)
             (list (concat ">" (car cell)) 'command (cdr cell)
                   (symbol-name (cdr cell))))
           commands)))

(defun my/palette--table (candidates)
  "Return a completion table over CANDIDATES from `my/palette--candidates'.
The metadata carries group and annotation functions for UIs that use
them and keeps the candidate order."
  (let ((labels (mapcar #'car candidates)))
    (lambda (string predicate action)
      (if (eq action 'metadata)
          `(metadata
            (category . org-seq-palette)
            (display-sort-function . identity)
            (cycle-sort-function . identity)
            (group-function
             . ,(lambda (candidate transform)
                  (if transform
                      candidate
                    (let ((entry (assoc candidate candidates)))
                      (cdr (assq (nth 1 entry) my/palette--groups))))))
            (annotation-function
             . ,(lambda (candidate)
                  (let ((note (nth 3 (assoc candidate candidates))))
                    (and note (not (string-empty-p note))
                         (concat "  " note))))))
        (complete-with-action action labels string predicate)))))

(defun my/palette--dispatch (entry)
  "Run the action of palette ENTRY, a (KIND DATA NOTE) list."
  (pcase (car entry)
    ('node (my/palette--visit (nth 1 entry)))
    ('type (let ((type (nth 1 entry)))
             (my/palette--capture
              type (read-string (format "New %s: " (my/node-type-name type))))))
    ('view (my/view-open (nth 1 entry)))
    ('command (call-interactively (nth 1 entry)))
    (_ (user-error "Unknown palette entry"))))

(defun my/palette--create-from-input (input)
  "Offer to create a note titled INPUT, optionally of a type."
  (when (y-or-n-p (format "No match.  Create note \"%s\"? " input))
    (let* ((types (and (bound-and-true-p my/node-types) my/node-types))
           (none "(no type)")
           (name (and types
                      (completing-read "Type: "
                                       (cons none (mapcar #'my/node-type-name types))
                                       nil t nil nil none)))
           (type (and name (not (equal name none))
                      (cl-find name types :key #'my/node-type-name
                               :test #'equal))))
      (my/palette--capture type input))))

;;;###autoload
(defun my/palette ()
  "Open the command palette: nodes, #types, @views and >commands."
  (interactive)
  (let* ((candidates (my/palette--candidates
                      (ignore-errors (my/index-records))
                      (and (bound-and-true-p my/node-types) my/node-types)
                      (ignore-errors (my/views-load))
                      (my/palette--available-commands)))
         (input (completing-read "Palette: " (my/palette--table candidates)
                                 nil nil))
         (entry (cdr (assoc input candidates))))
    (cond
     ((string-empty-p input) nil)
     (entry (my/palette--dispatch entry))
     (t (my/palette--create-from-input input)))))

;;;###autoload
(defun my/palette-search-text ()
  "Search the text of all nodes and visit the chosen one."
  (interactive)
  (let* ((query (read-string "Search notes: "))
         (hits (my/index-search query))
         (rows (delq nil
                     (mapcar (lambda (hit)
                               (when-let* ((record (my/index-node (car hit))))
                                 (cons (format "%s  %s" (plist-get record :title)
                                               (replace-regexp-in-string
                                                "[\n\t ]+" " " (cdr hit)))
                                       record)))
                             hits))))
    (unless rows (user-error "Nothing found for \"%s\"" query))
    (my/palette--visit
     (cdr (assoc (completing-read "Match: " (mapcar #'car rows) nil t) rows)))))

;; ---------------------------------------------------------------------------
;; Section 3: Slash menu
;; ---------------------------------------------------------------------------

(defun my/slash--indent ()
  "Return the whitespace before point on the current line."
  (buffer-substring-no-properties (line-beginning-position) (point)))

(defun my/slash--insert-lines (lines &optional cursor-line cursor-column)
  "Replace the current blank line with LINES, indented like it was.
Point ends on line CURSOR-LINE (0-based, default: the last) at
CURSOR-COLUMN (default: end of line)."
  (let* ((indent (my/slash--indent))
         (start (line-beginning-position)))
    (delete-region start (line-end-position))
    (insert (mapconcat (lambda (line) (concat indent line)) lines "\n"))
    (goto-char start)
    (forward-line (or cursor-line (1- (length lines))))
    (if cursor-column
        (goto-char (+ (line-beginning-position) (length indent) cursor-column))
      (end-of-line))))

(defun my/slash--heading-stars ()
  "Return stars for a new heading at the level of the enclosing heading."
  (make-string (max 1 (or (save-excursion
                            (and (ignore-errors (org-back-to-heading t))
                                 (org-current-level)))
                          1))
               ?*))

(defun my/slash--update-block ()
  "Refresh the dynamic block that starts on the current line."
  (condition-case err
      (save-excursion
        (beginning-of-line)
        (org-update-dblock))
    (error (message "Block inserted but not updated: %s"
                    (error-message-string err)))))

(defun my/slash--insert-block (begin-line)
  "Insert a dynamic block opened by BEGIN-LINE, update it, end after it."
  (my/slash--insert-lines (list begin-line "#+END:") 0)
  (my/slash--update-block)
  (when (re-search-forward "^[ \t]*#\\+END:" nil t)
    (end-of-line)))

(defun my/slash-insert-node-link ()
  "Insert an id link to a node chosen by completion."
  (let ((node (my/palette--read-node "Link to node: ")))
    (insert (format "[[id:%s][%s]]" (plist-get node :id)
                    (plist-get node :title)))))

(defun my/slash-insert-view-block ()
  "Insert an `orgseq-view' block for a saved view and update it."
  (let ((names (mapcar (lambda (view) (plist-get view :name)) (my/views-load))))
    (unless names (user-error "No saved views yet"))
    (my/slash--insert-block
     (format "#+BEGIN: orgseq-view :view %S"
             (completing-read "View: " names nil t)))))

(defun my/slash-insert-query-block ()
  "Insert an `orgseq-query' block for a chosen type and update it."
  (let ((type (my/node-read-type "Query type: ")))
    (my/slash--insert-block
     (format "#+BEGIN: orgseq-query :type %S :sort \"modified\" :order desc"
             (my/node-type-tag type)))))

(defun my/slash-insert-heading ()
  "Insert an empty heading at the level of the enclosing heading."
  (my/slash--insert-lines (list (concat (my/slash--heading-stars) " ")) 0)
  (end-of-line))

(defun my/slash-insert-todo-heading ()
  "Insert an empty TODO heading at the level of the enclosing heading."
  (my/slash--insert-lines (list (concat (my/slash--heading-stars) " TODO ")) 0)
  (end-of-line))

(defun my/slash-insert-checkbox ()
  "Insert an empty checkbox item."
  (my/slash--insert-lines (list "- [ ] ") 0)
  (end-of-line))

(defun my/slash-insert-table ()
  "Insert a 2x2 table with point in the first cell."
  (my/slash--insert-lines (list "|   |   |" "|---+---|" "|   |   |") 0 2))

(defun my/slash-insert-source-block ()
  "Insert a source block with point after `begin_src'."
  (my/slash--insert-lines (list "#+begin_src " "" "#+end_src") 0))

(defun my/slash-insert-quote-block ()
  "Insert a quote block with point inside."
  (my/slash--insert-lines (list "#+begin_quote" "" "#+end_quote") 1))

(defun my/slash-insert-date ()
  "Insert today's date as an inactive timestamp."
  (insert (format-time-string (org-time-stamp-format nil t))))

(defun my/slash-insert-new-node-link ()
  "Create a node of a chosen type and insert a link to it at point.
The note is written without being shown, so the buffer being edited
keeps the focus."
  (let* ((type (my/node-read-type "New node of type: "))
         (title (read-string (format "New %s: " (my/node-type-name type))))
         (note (my/note-capture title (my/node--type-capture-template type)
                                nil t)))
    (insert (format "[[id:%s][%s]]" (plist-get note :id) title))))

(defcustom my/slash-items
  '(("Link to node" . my/slash-insert-node-link)
    ("Saved view" . my/slash-insert-view-block)
    ("Query of a type" . my/slash-insert-query-block)
    ("Heading" . my/slash-insert-heading)
    ("TODO heading" . my/slash-insert-todo-heading)
    ("Checkbox item" . my/slash-insert-checkbox)
    ("Table" . my/slash-insert-table)
    ("Source block" . my/slash-insert-source-block)
    ("Quote block" . my/slash-insert-quote-block)
    ("Today's date" . my/slash-insert-date)
    ("New node of a type, as link" . my/slash-insert-new-node-link))
  "Items of the slash menu, as (LABEL . ACTION).
ACTION is a function called with no arguments at point on an empty line,
or a string inserted as is."
  :type '(alist :key-type (string :tag "Label")
                :value-type (choice (function :tag "Function")
                                    (string :tag "Text to insert")))
  :group 'org-seq)

(defun my/slash--in-drawer-p ()
  "Return non-nil when point is inside a drawer or property drawer."
  (save-excursion
    (beginning-of-line)
    (catch 'result
      (while (not (bobp))
        (forward-line -1)
        (cond
         ((looking-at-p "[ \t]*:END:[ \t]*$") (throw 'result nil))
         ((looking-at-p "[ \t]*:[[:alnum:]_@#%-]+:[ \t]*$") (throw 'result t))
         ((looking-at-p "\\*+ ") (throw 'result nil))))
      nil)))

(defun my/slash--context-p ()
  "Return non-nil when a typed slash should open the menu here.
The line must be blank around point, and point must not be in a table,
a src/example/export/comment block or a drawer."
  (and (derived-mode-p 'org-mode)
       (not buffer-read-only)
       (save-excursion (skip-chars-backward " \t") (bolp))
       (save-excursion (skip-chars-forward " \t") (eolp))
       (not (org-at-table-p))
       (not (org-in-block-p '("src" "example" "export" "comment")))
       (not (my/slash--in-drawer-p))))

(defun my/slash--evil-ok-p ()
  "Return non-nil unless Evil is active outside insert state."
  (or (not (bound-and-true-p evil-local-mode))
      (and (fboundp 'evil-insert-state-p) (evil-insert-state-p))))

(defun my/slash--run (action)
  "Run slash menu ACTION, a function or a string to insert."
  (if (stringp action) (insert action) (funcall action)))

(defun my/slash-menu ()
  "Choose a slash menu item and insert it.
Quitting or an empty choice inserts a literal slash instead."
  (let* ((items my/slash-items)
         (tick (buffer-chars-modified-tick))
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      '(metadata (category . org-seq-slash)
                                 (display-sort-function . identity))
                    (complete-with-action action (mapcar #'car items)
                                          string predicate))))
         (done nil))
    (condition-case err
        (let* ((choice (completing-read "Insert: " table nil t))
               (cell (assoc choice items)))
          (when cell
            (my/slash--run (cdr cell))
            (setq done t)))
      (quit nil)
      (user-error (message "%s" (error-message-string err))))
    (unless (or done (/= tick (buffer-chars-modified-tick)))
      (insert "/"))))

(defun my/slash-trigger ()
  "Open the slash menu on an empty line, else do what \"/\" normally does."
  (interactive)
  (if (and (null current-prefix-arg)
           (not (minibufferp))
           (my/slash--evil-ok-p)
           (my/slash--context-p))
      (my/slash-menu)
    (let ((command (let ((my/slash-mode nil))
                     (key-binding (vector last-command-event) t))))
      (if (commandp command)
          (call-interactively command)
        (self-insert-command (prefix-numeric-value current-prefix-arg))))))

(defvar-keymap my/slash-mode-map
  "/" #'my/slash-trigger)

;;;###autoload
(define-minor-mode my/slash-mode
  "Open an insert menu when \"/\" is typed on an empty line of an Org buffer."
  :lighter nil
  :keymap my/slash-mode-map)

;; ---------------------------------------------------------------------------
;; Section 4: Field panel
;; ---------------------------------------------------------------------------

(defface my/node-fields-name
  '((t :inherit (shadow bold)))
  "Face for field names in the field panel."
  :group 'org-seq)

(defface my/node-fields-empty
  '((t :inherit shadow))
  "Face for the placeholder of an empty field in the field panel."
  :group 'org-seq)

(defvar-local my/node-fields--overlay nil
  "Overlay holding the field panel of the current buffer, or nil.")

(defun my/node-fields--types ()
  "Return the types of the file-level node, or nil without an ID or type."
  (org-with-wide-buffer
   (and (org-entry-get (point-min) "ID")
        (my/node-types-at (point-min)))))

(defun my/node-fields--specs (types)
  "Return the distinct field plists of TYPES."
  (let (seen result)
    (dolist (type types)
      (dolist (spec (my/node-type-fields type))
        (unless (member (plist-get spec :name) seen)
          (push (plist-get spec :name) seen)
          (push spec result))))
    (nreverse result)))

(defun my/node-fields--rows ()
  "Return the panel rows (NAME VALUE SPEC) of the file-level node, or nil."
  (when-let* ((types (my/node-fields--types)))
    (org-with-wide-buffer
     (mapcar (lambda (spec)
               (let ((value (org-entry-get (point-min) (plist-get spec :name))))
                 (list (plist-get spec :name)
                       (and value (not (string-empty-p (string-trim value)))
                            (string-trim value))
                       spec)))
             (my/node-fields--specs types)))))

(defun my/node-fields--anchor ()
  "Return the end of the title line of the file-level node, or nil.
Without a title, the end of the leading property drawer is used."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((limit (save-excursion
                  (if (re-search-forward "^\\*+ " nil t)
                      (line-beginning-position)
                    (point-max)))))
     (cond
      ((re-search-forward "^[ \t]*#\\+title:.*$" limit t) (line-end-position))
      ((progn (goto-char (point-min))
              (looking-at-p "[ \t]*:PROPERTIES:"))
       (when (re-search-forward "^[ \t]*:END:[ \t]*$" limit t)
         (line-end-position)))))))

(defun my/node-fields--text (rows)
  "Return the panel text for ROWS, ending with a newline."
  (let ((width (apply #'max (mapcar (lambda (row) (length (car row))) rows))))
    (mapconcat
     (lambda (row)
       (concat "  "
               (propertize (string-pad (capitalize (downcase (car row))) width)
                           'face 'my/node-fields-name)
               "   "
               (if (nth 1 row)
                   (nth 1 row)
                 (propertize "-" 'face 'my/node-fields-empty))
               "\n"))
     rows "")))

(defun my/node-fields--clear ()
  "Delete the field panel overlay of the current buffer."
  (when (overlayp my/node-fields--overlay)
    (delete-overlay my/node-fields--overlay))
  (setq my/node-fields--overlay nil))

(defun my/node-fields-refresh ()
  "Redraw the field panel of the current buffer.
Does nothing, and leaves no overlay, unless the file-level node has a
type."
  (interactive)
  (my/node-fields--clear)
  (when (and my/node-fields-mode (derived-mode-p 'org-mode))
    (when-let* ((rows (my/node-fields--rows))
                (anchor (my/node-fields--anchor)))
      (let* ((text (my/node-fields--text rows))
             (at-end (>= anchor (point-max)))
             (overlay (make-overlay anchor (if at-end anchor (1+ anchor))
                                    nil nil nil)))
        (overlay-put overlay 'after-string (if at-end (concat "\n" text) text))
        (overlay-put overlay 'my/node-fields t)
        (overlay-put overlay 'evaporate nil)
        (setq my/node-fields--overlay overlay)))))

(defun my/node-fields--refresh-if-on (&rest _)
  "Redraw the field panel when `my/node-fields-mode' is on here."
  (when (and (bound-and-true-p my/node-fields-mode)
             (derived-mode-p 'org-mode))
    (my/node-fields-refresh)))

;;;###autoload
(define-minor-mode my/node-fields-mode
  "Show the fields of a typed file-level node under its title.
The panel is an overlay; the property drawer stays the source of truth."
  :lighter nil
  (if my/node-fields-mode
      (progn
        (add-hook 'after-save-hook #'my/node-fields-refresh nil t)
        (add-hook 'change-major-mode-hook #'my/node-fields--clear nil t)
        (my/node-fields-refresh))
    (remove-hook 'after-save-hook #'my/node-fields-refresh t)
    (remove-hook 'change-major-mode-hook #'my/node-fields--clear t)
    (my/node-fields--clear)))

;;;###autoload
(defun my/node-fields-toggle ()
  "Toggle the field panel in this buffer."
  (interactive)
  (my/node--ensure-org-buffer)
  (my/node-fields-mode 'toggle))

(defun my/node--ensure-org-buffer ()
  "Signal a user error unless the current buffer is an Org buffer."
  (unless (derived-mode-p 'org-mode)
    (user-error "The field panel works in Org buffers")))

;;;###autoload
(defun my/node-fields-edit ()
  "Pick a field of the file-level node and set it, then redraw the panel."
  (interactive)
  (my/node--ensure-org-buffer)
  (let* ((rows (or (my/node-fields--rows)
                   (user-error "This buffer has no typed file-level node")))
         (types (my/node-fields--types))
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      `(metadata
                        (display-sort-function . identity)
                        (annotation-function
                         . ,(lambda (name)
                              (concat "  " (or (nth 1 (assoc name rows)) "-")))))
                    (complete-with-action action (mapcar #'car rows)
                                          string predicate))))
         (name (completing-read "Field: " table nil t))
         (row (or (assoc name rows) (user-error "No field %s" name)))
         (value (my/node--read-field-value name (nth 2 row) types (nth 1 row))))
    (org-with-wide-buffer
     (org-entry-put (point-min) name value))
    (my/node-fields-refresh)
    (message "%s = %s" name value)))

(dolist (command '(my/node-set-field my/node-set-type my/node-remove-type))
  (advice-add command :after #'my/node-fields--refresh-if-on))

;; Both modes do nothing outside Org buffers, and the field panel costs
;; nothing in a buffer without a typed file-level node.
(add-hook 'org-mode-hook #'my/slash-mode)
(add-hook 'org-mode-hook #'my/node-fields-mode)

(provide 'init-palette)
;;; init-palette.el ends here
