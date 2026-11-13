;;; orgseq-cli.el --- Command line and MCP server for org-seq -*- lexical-binding: t; -*-
;;
;; Loaded by bin/orgseq in a batch Emacs, after init.el.  It is not an
;; init module and is never loaded by an interactive session.
;;
;;   API      `my/api-*' functions: search, read, create and edit nodes,
;;            run views, sync, self-check.  They return plain alists and
;;            vectors that serialize to JSON.
;;   CLI      `my/cli-main' maps subcommands to the API (orgseq add,
;;            search, query, sync, doctor, update, ...).
;;   MCP      `my/mcp-serve' exposes the same API as Model Context
;;            Protocol tools over standard input and output.
;;
;; Every write goes through the same path as the interactive commands
;; (`my/node-call-at-id', plain Org files), so Org text stays the only
;; authority.
;;
;; The batch process reads the kernel node index (kernel/orgseq-index.el),
;; the same file the interactive session uses.  It is derived from the Org
;; files and refreshed on demand, so it needs no backup and no sync.

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'org)
(require 'org-id)
(require 'orgseq-index)
(require 'orgseq-note)

(defvar my/note-home)
(defvar my/inbox-dir)
(defvar my/library-dir)
(defvar my/archives-dir)
(defvar my/orgseq-dir)
(defvar my/types-file)
(defvar my/views-file)
(defvar my/node-types)
(defvar my/sync-remote)
(defvar my/view--ctx)
(defvar my/--init-errors)

(declare-function my/node-types-reload "init-nodes" ())
(declare-function my/node-type-by-tag "init-nodes" (tag))
(declare-function my/node-types--find "init-nodes" (ref types))
(declare-function my/node-type-name "init-nodes" (type))
(declare-function my/node-type-tag "init-nodes" (type))
(declare-function my/node-type-fields "init-nodes" (type))
(declare-function my/node-type-choices "init-nodes" (type))
(declare-function my/node-type-template "init-nodes" (type))
(declare-function my/node-type-template-body "init-nodes" (type &optional template))
(declare-function my/node-type-templates "init-nodes" (type))
(declare-function my/node-type-formulas "init-nodes" (type))
(declare-function my/node-type-parent "init-nodes" (type))
(declare-function my/node-set-type "init-nodes" (type &optional replace))
(declare-function my/node-file-into "init-nodes" (id layer &optional type folder))
(declare-function my/node-type-dir "init-nodes" (type))
(declare-function my/node-call-at-id "init-nodes" (id fn))
(declare-function my/node-set-field-by-id "init-nodes" (id name value))
(declare-function my/view--records "init-views" ())
(declare-function my/view--make-ctx "init-views" (records &optional current links))
(declare-function my/view--record "init-views" (id))
(declare-function my/view--links "init-views" ())
(declare-function my/view-run "init-views" (view))
(declare-function my/view-value "init-views" (record column))
(declare-function my/view-from-params "init-views" (params))
(declare-function my/views-load "init-views" ())
(declare-function my/view--format-sort "init-views" (sort))
(declare-function my/node-types-ensure-file "init-nodes" ())
(declare-function my/sync-run "init-sync" (&optional dry-run callback synchronous))
(declare-function my/sync-status "init-sync" ())
(declare-function my/sync-conflict-files "init-sync" ())
(declare-function my/storage-import "init-sync" (dir))
(declare-function my/storage-export "init-sync" (dir))
(declare-function my/storage-snapshot "init-sync" ())
(declare-function my/storage-info "init-sync" ())
(declare-function my/private-info "init-private" ())
(declare-function my/notion-import-plan "init-import" (dir &rest keys))
(declare-function my/notion-import "init-import" (dir &rest keys))
(declare-function my/tana-import-plan "init-import" (file &rest keys))
(declare-function my/tana-import "init-import" (file &rest keys))
(declare-function my/import-profile-read "init-import" (file))
(declare-function my/storage-snapshots "init-sync" ())
(declare-function my/storage--files "init-sync" (dir))
(declare-function my/storage-restore "init-sync" (snapshot))
(declare-function my/storage-restore-plan "init-sync" (snapshot))
(declare-function my/storage-layout-plan "init-sync" (&optional dir))
(declare-function my/storage-migrate-layout "init-sync" ())
(declare-function my/doctor-run "init-doctor" ())
(declare-function my/package-update-all "init-update" ())

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Index
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/api--prepared nil
  "Non-nil once the type registry has been loaded in this process.")

(defun my/api-refresh ()
  "Bring the node index in line with the Org files.
The command line reads the same kernel index as the interactive session
\(kernel/orgseq-index.el); a refresh re-reads only files that changed."
  (unless my/api--prepared
    (make-directory my/note-home t)
    ;; A library first touched from the command line gets the same
    ;; starter types as one first opened in the interactive session.
    (my/node-types-ensure-file)
    (my/node-types-reload)
    (setq my/api--prepared t))
  (my/index-sync 'check))

(defmacro my/api--with-ctx (&rest body)
  "Run BODY with a fresh index and a view context over all nodes."
  (declare (indent 0))
  `(progn
     (my/api-refresh)
     (let ((my/view--ctx (my/view--make-ctx (my/view--records))))
       ,@body)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: API
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/api--relative (file)
  "Return FILE relative to the library root."
  (file-relative-name file my/note-home))

(defun my/api--record-summary (record &optional columns)
  "Return RECORD as an alist with id, title, tags, file and COLUMNS."
  (append
   (list (cons 'id (plist-get record :id))
         (cons 'title (plist-get record :title))
         (cons 'tags (vconcat (plist-get record :tags)))
         (cons 'file (my/api--relative (plist-get record :file))))
   (and (plist-get record :todo)
        (list (cons 'todo (plist-get record :todo))))
   (and columns
        (list (cons 'fields
                    (or (mapcar (lambda (column)
                                  (cons (intern column)
                                        (my/view-value record column)))
                                columns)
                        (make-hash-table)))))))

(defun my/api-search (query &optional limit)
  "Search the library for QUERY.
Return an alist with `nodes' (title matches) and `text' (matching lines
from ripgrep), each limited to LIMIT entries (default 20)."
  (let ((limit (or limit 20))
        (needle (downcase query)))
    (my/api--with-ctx
      (let* ((titled (cl-remove-if-not
                      (lambda (record)
                        (string-search needle (downcase (plist-get record :title))))
                      (plist-get my/view--ctx :records)))
             ;; Title matches first, then nodes whose own text matches
             ;; (full-text index; substrings in any script).
             (nodes (append
                     titled
                     (delq nil
                           (mapcar
                            (lambda (hit)
                              (let ((record (my/view--record (car hit))))
                                (and record (not (memq record titled)) record)))
                            (my/index-search query (* 2 limit))))))
             (lines (and (executable-find "rg")
                         (process-lines-ignore-status
                          "rg" "--line-number" "--no-heading" "--fixed-strings"
                          "--ignore-case" "--max-count" "3" "--glob" "*.org"
                          "--glob" "*.md" "--" query
                          (directory-file-name (expand-file-name my/note-home))))))
        (list
         (cons 'nodes (vconcat (mapcar #'my/api--record-summary
                                       (seq-take nodes limit))))
         (cons 'text
               (vconcat
                (cl-loop for line in (seq-take lines limit)
                         when (string-match "\\`\\(.+?\\):\\([0-9]+\\):\\(.*\\)\\'" line)
                         collect (list (cons 'file (my/api--relative
                                                    (match-string 1 line)))
                                       (cons 'line (string-to-number
                                                    (match-string 2 line)))
                                       (cons 'text (string-trim
                                                    (match-string 3 line))))))))))))

(defun my/api--node-text (node)
  "Return the Org text of record NODE: its file, or its subtree for a heading."
  (with-temp-buffer
    (insert-file-contents (plist-get node :file))
    (if (= 0 (plist-get node :level))
        (buffer-string)
      (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
      (goto-char (or (org-find-property "ID" (plist-get node :id))
                     (plist-get node :pos)))
      (buffer-substring-no-properties
       (point) (save-excursion (org-end-of-subtree t t) (point))))))

(defun my/api-node (id)
  "Return node ID with its fields, links and Org text."
  (my/api--with-ctx
    (let* ((record (or (my/view--record id)
                       (user-error "No node with id %s" id)))
           (links (my/view--links))
           (titles (lambda (ids)
                     (vconcat
                      (delq nil
                            (mapcar (lambda (other)
                                      (when-let* ((r (my/view--record other)))
                                        (list (cons 'id other)
                                              (cons 'title (plist-get r :title)))))
                                    (delete-dups (copy-sequence ids))))))))
      (append
       (my/api--record-summary record)
       (list (cons 'properties
                   (or (cl-loop for (key . value) in (plist-get record :props)
                                unless (member key '("ID" "CATEGORY" "FILE" "ITEM"
                                                     "ALLTAGS" "TAGS" "PRIORITY"
                                                     "BLOCKED" "TODO"))
                                collect (cons (intern key) (format "%s" value)))
                       (make-hash-table)))
             (cons 'links_to (funcall titles (gethash id (cdr links))))
             (cons 'linked_from (funcall titles (gethash id (car links))))
             (cons 'content (my/api--node-text record)))))))

(defalias 'my/api--slug #'my/note-slug
  "Return a file-name slug for a title; see `my/note-slug'.")

(defvar my/api-inbox-only nil
  "Non-nil makes `my/api-create' write to the Inbox whatever the type says.
Bound by the MCP server for clients that may only add to the Inbox.")

(defun my/api-create (title &optional type fields body tags template)
  "Create a note titled TITLE in the Inbox capture directory.
A type with TYPE_LAYER puts the note in that layer instead.
TYPE is a type name or tag; FIELDS an alist of (NAME . VALUE); BODY the
Org text (default: the type's template, or its \"Template: NAME\"
template when TEMPLATE names one); TAGS extra tags.  Return an
alist with the new node's id and file.  The file is written by
`my/note-create', the same function interactive capture uses."
  (when (string-empty-p (string-trim title))
    (user-error "A note needs a title"))
  (my/api-refresh)
  (let* ((type-def (and type
                        (or (my/node-types--find type my/node-types)
                            (user-error "Unknown type: %s (see `orgseq types')"
                                        type))))
         (template (and template (not (string-empty-p template)) template))
         (_ (when (and template (not type-def))
              (user-error "A template needs a type (--type)")))
         (all-tags (delete-dups
                    (append (and type-def (list (my/node-type-tag type-def)))
                            tags)))
         (names (delete-dups
                 (append (and type-def
                              (mapcar (lambda (f) (plist-get f :name))
                                      (my/node-type-fields type-def)))
                         (mapcar (lambda (f) (upcase (format "%s" (car f))))
                                 fields))))
         (text (cond
                ((and body (not (string-empty-p body))) body)
                (type-def (replace-regexp-in-string
                           "%\\?" ""
                           (my/node-type-template-body type-def template) t t))
                (t "")))
         (dir (and type-def (not my/api-inbox-only)
                   (my/node-type-dir type-def)))
         (note (my/note-create
                :title title :tags all-tags :body text
                :file (and dir
                           (expand-file-name
                            (format "%s-%s.org"
                                    (format-time-string "%Y%m%dT%H%M%S")
                                    (my/note-slug title))
                            dir))
                :props (mapcar
                        (lambda (name)
                          (cons name
                                (or (cdr (cl-assoc name fields
                                                   :test (lambda (a b)
                                                           (string-equal-ignore-case
                                                            a (format "%s" b)))))
                                    "")))
                        names))))
    (list (cons 'id (plist-get note :id))
          (cons 'title title)
          (cons 'file (my/api--relative (plist-get note :file))))))

(defun my/api-append-daily (text)
  "Append TEXT as a timestamped heading to today's Daily note."
  (list (cons 'file (my/api--relative (plist-get (my/daily-append text) :file)))))

(defun my/api-append (id text)
  "Append Org TEXT to the end of node ID."
  (my/api-refresh)
  (my/node-call-at-id
   id (lambda (pos)
        (goto-char pos)
        (if (org-before-first-heading-p)
            (goto-char (point-max))
          (org-end-of-subtree t t))
        (unless (bolp) (insert "\n"))
        (insert (string-trim-right text) "\n")))
  (list (cons 'id id)))

(defun my/api-set-field (id name value)
  "Set field NAME of node ID to VALUE (empty clears the field)."
  (my/api-refresh)
  (my/node-set-field-by-id id name value)
  (list (cons 'id id) (cons 'field (upcase name)) (cons 'value (or value ""))))

(defun my/api-set-type (id type)
  "Make node ID an instance of TYPE, replacing its previous type."
  (my/api-refresh)
  (let ((type-def (or (my/node-types--find type my/node-types)
                      (user-error "Unknown type: %s" type))))
    (my/node-call-at-id
     id (lambda (pos)
          (goto-char pos)
          (let ((inhibit-message t))
            (my/node-set-type type-def 'replace))))
    (list (cons 'id id) (cons 'type (my/node-type-tag type-def)))))

(defun my/api-file (id layer &optional type folder)
  "File node ID into library LAYER; see `my/node-file-into'."
  (my/api-refresh)
  (let ((result (let ((inhibit-message t))
                  (my/node-file-into id layer type folder))))
    (list (cons 'id id)
          (cons 'layer (symbol-name (plist-get result :layer)))
          (cons 'file (my/api--relative (plist-get result :file))))))

(defun my/api-query (params)
  "Run the view described by plist PARAMS and return its groups.
PARAMS takes :view (a saved view), :type, :filter (a filter form), :group,
:columns (list), :sort (string) and :limit."
  (my/api--with-ctx
    (let* ((type (plist-get params :type))
           ;; Accept a type by name as well as by tag, as `my/api-create' does.
           (params (if-let* ((found (and type (my/node-types--find
                                               type my/node-types))))
                       (plist-put (copy-sequence params)
                                  :type (my/node-type-tag found))
                     params))
           (view (my/view-from-params params))
           (result (my/view-run view))
           (columns (plist-get result :columns)))
      (list
       (cons 'count (plist-get result :count))
       (cons 'columns (vconcat columns))
       (cons 'groups
             (vconcat
              (mapcar (lambda (group)
                        (list (cons 'group (or (car group) ""))
                              (cons 'nodes
                                    (vconcat
                                     (mapcar (lambda (record)
                                               (my/api--record-summary
                                                record columns))
                                             (cdr group))))))
                      (plist-get result :groups))))))))

(defun my/api-types ()
  "Return the node types with their fields and choices."
  (my/node-types-reload)
  (vconcat
   (mapcar
    (lambda (type)
      (list (cons 'name (my/node-type-name type))
            (cons 'tag (my/node-type-tag type))
            (cons 'extends (or (my/node-type-parent type) ""))
            (cons 'templates (vconcat (mapcar #'car (my/node-type-templates type))))
            (cons 'formulas
                  (vconcat (mapcar (lambda (spec)
                                     (list (cons 'name (plist-get spec :name))
                                           (cons 'expr (plist-get spec :expr))))
                                   (my/node-type-formulas type))))
            (cons 'fields
                  (vconcat
                   (mapcar
                    (lambda (field)
                      (let ((name (plist-get field :name)))
                        (list (cons 'name name)
                              (cons 'kind (symbol-name (plist-get field :kind)))
                              (cons 'choices
                                    (vconcat
                                     (cdr (assoc name
                                                 (my/node-type-choices type))))))))
                    (my/node-type-fields type))))))
    my/node-types)))

(defun my/api-views ()
  "Return the saved views."
  (vconcat
   (mapcar (lambda (view)
             (list (cons 'name (plist-get view :name))
                   (cons 'type (or (plist-get view :type) ""))
                   (cons 'layout (symbol-name (plist-get view :layout)))
                   (cons 'group (or (plist-get view :group) ""))
                   (cons 'columns (vconcat (plist-get view :columns)))
                   (cons 'sort (my/view--format-sort (plist-get view :sort)))
                   (cons 'filter (if (plist-get view :filter)
                                     (prin1-to-string (plist-get view :filter))
                                   ""))))
           (my/views-load))))

(defun my/api-sync (&optional preview)
  "Sync the library now; PREVIEW only reports.  Return status details."
  (let* ((inhibit-message t)
         (ok (my/sync-run preview nil t)))
    (list (cons 'ok (if ok t :false))
          (cons 'status (my/sync-status))
          (cons 'conflicts (vconcat (mapcar #'my/api--relative
                                            (my/sync-conflict-files)))))))

(defun my/api-doctor ()
  "Run the self-check and return its results."
  (vconcat
   (mapcar (lambda (result)
             (list (cons 'check (format "%s" (plist-get result :label)))
                   (cons 'status (symbol-name (plist-get result :status)))
                   (cons 'detail (format "%s" (or (plist-get result :detail) "")))
                   (cons 'remedy (format "%s" (or (plist-get result :remedy) "")))))
           (my/doctor-run))))

(defun my/api-import (dir)
  "Copy notes from folder DIR into the library; return what was done."
  (let* ((inhibit-message t)
         (count (my/storage-import dir)))
    (my/api-refresh)
    (list (cons 'copied count)
          (cons 'source (expand-file-name dir)))))

(defun my/api-import-notion (dir confirmed &rest options)
  "Import the extracted Notion export DIR when CONFIRMED, else describe it.
OPTIONS are the keywords of `my/notion-import-plan' (:type :types
:layer :folder :private :map :routes).  Page titles are not part of the
result, so a plan that fills the private zone can be shown anywhere."
  (my/api-refresh)
  (let* ((inhibit-message t)
         (plan (apply #'my/notion-import-plan dir options))
         (summary
          (list (cons 'source (plist-get plan :source))
                (cons 'targets (vconcat (plist-get plan :targets)))
                (cons 'new (plist-get plan :new))
                (cons 'new_private (plist-get plan :new-private))
                (cons 'existing (plist-get plan :existing))
                (cons 'left_out (plist-get plan :left-out))
                (cons 'databases
                      (vconcat
                       (mapcar
                        (lambda (database)
                          (list (cons 'name (plist-get database :name))
                                (cons 'pages (plist-get database :pages))
                                (cons 'type (or (plist-get database :type) ""))
                                (cons 'properties
                                      (vconcat (plist-get database :properties)))
                                (cons 'not_in_type
                                      (vconcat (plist-get database :unmapped)))))
                        (plist-get plan :databases)))))))
    (if (or (not confirmed) (zerop (plist-get plan :new)))
        (cons (cons 'imported nil) summary)
      (let ((result (apply #'my/notion-import dir options)))
        (my/api-refresh)
        (append (list (cons 'imported t)
                      (cons 'created (plist-get result :created))
                      (cons 'private (plist-get result :private))
                      (cons 'assets (plist-get result :assets))
                      (cons 'unresolved_links (plist-get result :unresolved))
                      (cons 'withheld_links (plist-get result :withheld))
                      (cons 'snapshot (or (plist-get result :snapshot) "")))
                summary)))))

(defun my/api-import-tana (file confirmed &rest options)
  "Import the Tana JSON export FILE when CONFIRMED, else describe it.
OPTIONS are the keywords of `my/tana-import-plan' (:types :map :routes).
Titles are not part of the result."
  (my/api-refresh)
  (let* ((inhibit-message t)
         (plan (apply #'my/tana-import-plan file options))
         (summary
          (list (cons 'source (plist-get plan :source))
                (cons 'targets (vconcat (plist-get plan :targets)))
                (cons 'new (plist-get plan :new))
                (cons 'new_private (plist-get plan :new-private))
                (cons 'days (plist-get plan :daily))
                (cons 'existing (plist-get plan :existing))
                (cons 'left_out (plist-get plan :left-out))
                (cons 'tags
                      (vconcat
                       (mapcar (lambda (tag)
                                 (list (cons 'name (plist-get tag :name))
                                       (cons 'count (plist-get tag :count))
                                       (cons 'type (or (plist-get tag :type) ""))))
                               (plist-get plan :tags)))))))
    (if (or (not confirmed) (zerop (plist-get plan :new)))
        (cons (cons 'imported nil) summary)
      (let ((result (apply #'my/tana-import file options)))
        (my/api-refresh)
        (append (list (cons 'imported t)
                      (cons 'created (plist-get result :created))
                      (cons 'days_written (plist-get result :daily))
                      (cons 'private (plist-get result :private))
                      (cons 'withheld_links (plist-get result :withheld))
                      (cons 'snapshot (or (plist-get result :snapshot) "")))
                summary)))))

(defun my/api-export (dir)
  "Copy the library into a new dated folder inside DIR; return its path."
  (let ((inhibit-message t))
    (list (cons 'folder (my/storage-export dir)))))

(defun my/api-snapshot ()
  "Take a snapshot of the library; return its folder, empty when none."
  (let ((inhibit-message t))
    (list (cons 'folder (or (my/storage-snapshot) "")))))

(defun my/cli--installed-version ()
  "Return the deployed org-seq version line, or \"unversioned\"."
  (let ((file (expand-file-name ".org-seq-version" user-emacs-directory)))
    (or (and (file-readable-p file)
             (let ((text (string-trim
                          (with-temp-buffer
                            (insert-file-contents file)
                            (buffer-string)))))
               (and (not (string-empty-p text)) text)))
        "unversioned")))

(defun my/api-snapshots ()
  "List the snapshots, newest first, with their file counts and sizes."
  (vconcat
   (mapcar (lambda (dir)
             (let ((files (my/storage--files dir)))
               (list (cons 'name (file-name-nondirectory (directory-file-name dir)))
                     (cons 'folder (file-name-as-directory dir))
                     (cons 'files (length files))
                     (cons 'bytes
                           (apply #'+ (mapcar
                                       (lambda (file)
                                         (or (file-attribute-size
                                              (file-attributes file))
                                             0))
                                       files))))))
           (my/storage-snapshots))))

(defun my/api-restore (name confirmed)
  "Return the library to snapshot NAME when CONFIRMED, else only describe it.
The result lists the files that would be (or were) written and deleted."
  (let ((inhibit-message t))
    (if (not confirmed)
        (let ((plan (my/storage-restore-plan name)))
          (list (cons 'restored nil)
                (cons 'snapshot (directory-file-name (plist-get plan :snapshot)))
                (cons 'would_write (length (plist-get plan :copy)))
                (cons 'would_delete (length (plist-get plan :delete)))
                (cons 'delete (vconcat (plist-get plan :delete)))))
      (let ((result (my/storage-restore name)))
        (my/api-refresh)
        (list (cons 'restored t)
              (cons 'files (plist-get result :restored))
              (cons 'deleted (plist-get result :deleted))
              (cons 'snapshot (plist-get result :snapshot))
              (cons 'undo_snapshot (or (plist-get result :undo-snapshot) "")))))))

(defun my/api-migrate (confirmed)
  "Move the library to the current layout when CONFIRMED, else describe it.
See `my/storage-migrate-layout'."
  (let ((inhibit-message t)
        (plan (my/storage-layout-plan)))
    (if (or (not confirmed) (null plan))
        (list (cons 'migrated nil)
              (cons 'would_move (length plan))
              (cons 'moves (vconcat
                            (mapcar (lambda (move)
                                      (list (cons 'from (car move))
                                            (cons 'to (cdr move))))
                                    plan))))
      (let ((result (my/storage-migrate-layout)))
        (my/api-refresh)
        (list (cons 'migrated t)
              (cons 'moved (plist-get result :moved))
              (cons 'skipped (plist-get result :skipped))
              (cons 'snapshot (plist-get result :snapshot)))))))

(defun my/api-info ()
  "Return where the library lives, how it syncs and how it is protected."
  (let ((storage (my/storage-info)))
    (list (cons 'version (my/cli--installed-version))
          (cons 'library (expand-file-name my/note-home))
          (cons 'notes (plist-get storage :notes))
          (cons 'files (plist-get storage :files))
          (cons 'types_file (expand-file-name my/types-file))
          (cons 'views_file (expand-file-name my/views-file))
          (cons 'sync (my/sync-status))
          (cons 'snapshot_dir (plist-get storage :snapshot-dir))
          (cons 'snapshots (plist-get storage :snapshots))
          (cons 'last_snapshot (or (plist-get storage :last-snapshot) ""))
          (cons 'legacy_library (or (plist-get storage :legacy) ""))
          (cons 'private_dir (if (fboundp 'my/private-info)
                                 (plist-get (my/private-info) :dir)
                               ""))
          (cons 'private_files (if (fboundp 'my/private-info)
                                   (plist-get (my/private-info) :files)
                                 0))
          (cons 'failed_modules
                (vconcat (mapcar (lambda (entry) (symbol-name (car entry)))
                                 my/--init-errors))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Command line
;; ═══════════════════════════════════════════════════════════════════════════

(defconst my/cli-usage
  "Usage: orgseq COMMAND [ARGS]

Notes
  add TITLE [--type T [--template NAME]] [--field NAME=VALUE]... [--tag TAG]...
      [--body TEXT]      create a note (--body - reads standard input)
  daily TEXT             append a timestamped line to today's Daily note
  search QUERY [--limit N]
                         find nodes by title and lines by text
  show ID                print a node with its fields, links and text
  set ID FIELD VALUE     set a field on a node (empty VALUE clears it)
  retype ID TYPE         make a node an instance of TYPE
  file ID LAYER [--type T] [--folder F]
                         move a node out of the Inbox into a layer: project,
                         area, resource, archive or ai (keeps its id)
  append ID TEXT         append Org text to a node

Structure
  types                  list node types and their fields
  views                  list saved views
  query [--view NAME] [--type T] [--filter FORM] [--group FIELD]
        [--columns A,B] [--sort \"YEAR desc\"] [--limit N]
                         run a saved or ad-hoc view

Maintenance
  import DIR             copy notes in from a folder (never overwrites)
  import-notion DIR [--type T] [--db-type DATABASE=T]... [--layer L]
        [--folder F] [--map NAME=FIELD]... [--private] --yes
                         turn an extracted Notion export (Markdown & CSV)
                         into notes; pages imported before are skipped.
                         --type applies an existing type to every page,
                         --db-type to the rows of one database, --map
                         renames a Notion property to a field, --private
                         writes to the private zone (not indexed, not
                         synced); without --yes only shows what would
                         happen
        [--route PREFIX=DEST]... [--profile FILE]
                         --route sends the pages below a path of the
                         export (by titles) to DEST: a layer (inbox,
                         project, area, resource, archive, ai) or
                         private, then folders, or skip; the folders
                         below the path are kept.  --profile reads
                         \"route A = B\", \"type DATABASE = T\" and
                         \"map NAME = FIELD\" lines from a file
  import-tana FILE [--db-type SUPERTAG=T]... [--map NAME=FIELD]...
        [--route PREFIX=DEST]... [--profile FILE] --yes
                         turn a Tana JSON export into notes: days go to
                         Daily files, nodes with a supertag become notes
                         with their fields as properties.  Route paths
                         are tag/SUPERTAG and page/TITLE
  export DIR             copy the library into a new dated folder in DIR
  snapshot               take a local snapshot of the library now
  snapshots              list the snapshots, newest first
  restore NAME --yes     return the library to snapshot NAME (a snapshot of
                         the current library is taken first; without --yes
                         only shows what would happen)
  migrate --yes          rename an old library layout (00_Roam/ becomes
                         00_Inbox/, AI context files move to 50_AI/; a
                         snapshot is taken first; without --yes only shows
                         what would move)
  sync [--preview]       sync the library with the configured remote
  doctor                 self-check; exits 1 when a required check fails
  update                 upgrade installed packages (snapshot first)
  reindex                rebuild the command-line node index
  info                   show version, library location, sync status and snapshots
  version                print the installed org-seq version
  upgrade [--check] [--from DIR_OR_URL] [--ref REF] [--no-backup|--full-backup]
                         update this installation from its source checkout or
                         remote (Linux/macOS only; --check exits 10 when an
                         upgrade is available)
  mcp [--access LEVEL]   serve the Model Context Protocol on stdin/stdout.
                         LEVEL limits the client: read, inbox (also add to
                         the Inbox), write (default; also change and file
                         nodes), structure (also sync)

Add --json to any command for machine-readable output."
  "Help text of the command line.")

(defun my/cli--print (text)
  "Write TEXT and a newline to standard output as UTF-8."
  (princ (encode-coding-string (concat text "\n") 'utf-8)))

(defun my/cli--json (value)
  "Return VALUE serialized as JSON text."
  (decode-coding-string
   (json-serialize value :null-object :null :false-object :false)
   'utf-8))

(defun my/cli--options (args spec)
  "Split ARGS into (OPTIONS . POSITIONAL) according to SPEC.
SPEC is an alist of (\"--name\" . KIND), KIND one of `flag', `value' or
`multi'.  OPTIONS is an alist of (\"--name\" . VALUE)."
  (let (options positional)
    (while args
      (let* ((arg (pop args))
             (kind (cdr (assoc arg spec))))
        (pcase kind
          ('flag (push (cons arg t) options))
          ('value
           (unless args (user-error "%s needs a value" arg))
           (push (cons arg (pop args)) options))
          ('multi
           (unless args (user-error "%s needs a value" arg))
           (let ((cell (assoc arg options)))
             (if cell
                 (setcdr cell (append (cdr cell) (list (pop args))))
               (push (cons arg (list (pop args))) options))))
          (_
           (when (string-prefix-p "--" arg)
             (user-error "Unknown option %s" arg))
           (push arg positional)))))
    (cons options (nreverse positional))))

(defun my/cli--read-stdin ()
  "Return all of standard input as a string."
  (let (lines)
    (condition-case nil
        (while t (push (read-string "") lines))
      (error nil))
    (decode-coding-string
     (encode-coding-string (string-join (nreverse lines) "\n") 'utf-8 t)
     'utf-8)))

(defun my/cli--query-params (options)
  "Build `my/api-query' parameters from command line OPTIONS."
  (let ((get (lambda (name) (cdr (assoc name options))))
        params)
    (when (funcall get "--view")
      (setq params (plist-put params :view (funcall get "--view"))))
    (when (funcall get "--type")
      (setq params (plist-put params :type (funcall get "--type"))))
    (when (funcall get "--filter")
      (setq params (plist-put params :filter
                              (car (read-from-string (funcall get "--filter"))))))
    (when (funcall get "--group")
      (setq params (plist-put params :group (funcall get "--group"))))
    (when (funcall get "--columns")
      (setq params (plist-put params :columns
                              (split-string (funcall get "--columns") "," t
                                            "[ \t]+"))))
    (when (funcall get "--sort")
      (setq params (plist-put params :sort (funcall get "--sort"))))
    (when (funcall get "--limit")
      (setq params (plist-put params :limit
                              (string-to-number (funcall get "--limit")))))
    params))

(defun my/cli--show-nodes (nodes)
  "Print NODES, a vector of node summaries, one per line."
  (seq-doseq (node nodes)
    (my/cli--print
     (format "%s  %s%s%s"
             (alist-get 'id node)
             (if (alist-get 'todo node) (concat (alist-get 'todo node) " ") "")
             (alist-get 'title node)
             (let ((fields (alist-get 'fields node)))
               (if (and (listp fields) fields)
                   (concat "   "
                           (mapconcat (lambda (f) (format "%s=%s" (car f) (cdr f)))
                                      (cl-remove-if (lambda (f)
                                                      (string-empty-p (cdr f)))
                                                    fields)
                                      "  "))
                 ""))))))

(defun my/cli--run (command args)
  "Run COMMAND with ARGS; return the process exit code."
  (pcase-let* ((`(,options . ,rest)
                (my/cli--options
                 args '(("--json" . flag) ("--preview" . flag) ("--yes" . flag)
                        ("--type" . value) ("--body" . value)
                        ("--template" . value) ("--folder" . value)
                        ("--access" . value) ("--layer" . value)
                        ("--private" . flag) ("--map" . multi)
                        ("--db-type" . multi) ("--route" . multi)
                        ("--profile" . value)
                        ("--limit" . value) ("--view" . value)
                        ("--filter" . value) ("--group" . value)
                        ("--columns" . value) ("--sort" . value)
                        ("--field" . multi) ("--tag" . multi))))
               (json (cdr (assoc "--json" options)))
               (emit (lambda (value text-fn)
                       (if json
                           (my/cli--print (my/cli--json value))
                         (funcall text-fn value))
                       0)))
    (pcase command
      ((or "help" "--help" "-h") (my/cli--print my/cli-usage) 0)
      ("add"
       (unless rest (user-error "Usage: orgseq add TITLE [--type T] ..."))
       (let ((body (cdr (assoc "--body" options))))
         (funcall
          emit
          (my/api-create
           (string-join rest " ")
           (cdr (assoc "--type" options))
           (mapcar (lambda (pair)
                     (unless (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" pair)
                       (user-error "--field expects NAME=VALUE, got %s" pair))
                     (cons (match-string 1 pair) (match-string 2 pair)))
                   (cdr (assoc "--field" options)))
           (if (equal body "-") (my/cli--read-stdin) body)
           (cdr (assoc "--tag" options))
           (cdr (assoc "--template" options)))
          (lambda (value)
            (my/cli--print (format "%s  %s" (alist-get 'id value)
                                   (alist-get 'file value)))))))
      ("daily"
       (unless rest (user-error "Usage: orgseq daily TEXT"))
       (funcall emit (my/api-append-daily (string-join rest " "))
                (lambda (value)
                  (my/cli--print (format "Added to %s" (alist-get 'file value))))))
      ("search"
       (unless rest (user-error "Usage: orgseq search QUERY"))
       (funcall
        emit
        (my/api-search (string-join rest " ")
                       (and (assoc "--limit" options)
                            (string-to-number (cdr (assoc "--limit" options)))))
        (lambda (value)
          (my/cli--show-nodes (alist-get 'nodes value))
          (seq-doseq (hit (alist-get 'text value))
            (my/cli--print (format "%s:%d: %s" (alist-get 'file hit)
                                   (alist-get 'line hit) (alist-get 'text hit)))))))
      ("show"
       (unless rest (user-error "Usage: orgseq show ID"))
       (funcall
        emit (my/api-node (car rest))
        (lambda (value)
          (my/cli--print (format "%s  [%s]  %s" (alist-get 'title value)
                                 (string-join (alist-get 'tags value) " ")
                                 (alist-get 'file value)))
          (seq-doseq (other (alist-get 'linked_from value))
            (my/cli--print (format "<- %s  %s" (alist-get 'id other)
                                   (alist-get 'title other))))
          (my/cli--print "")
          (my/cli--print (alist-get 'content value)))))
      ("set"
       (unless (>= (length rest) 2)
         (user-error "Usage: orgseq set ID FIELD VALUE"))
       (funcall emit
                (my/api-set-field (car rest) (cadr rest)
                                  (string-join (cddr rest) " "))
                (lambda (value)
                  (my/cli--print (format "%s = %s" (alist-get 'field value)
                                         (alist-get 'value value))))))
      ("retype"
       (unless (= (length rest) 2) (user-error "Usage: orgseq retype ID TYPE"))
       (funcall emit (my/api-set-type (car rest) (cadr rest))
                (lambda (value)
                  (my/cli--print (format "Type: %s" (alist-get 'type value))))))
      ("file"
       (unless (= (length rest) 2)
         (user-error "Usage: orgseq file ID LAYER [--type TYPE] [--folder FOLDER]"))
       (funcall emit (my/api-file (car rest) (cadr rest)
                                  (cdr (assoc "--type" options))
                                  (cdr (assoc "--folder" options)))
                (lambda (value)
                  (my/cli--print (format "Filed into %s" (alist-get 'file value))))))
      ("append"
       (unless (>= (length rest) 2) (user-error "Usage: orgseq append ID TEXT"))
       (funcall emit
                (my/api-append (car rest)
                               (let ((text (string-join (cdr rest) " ")))
                                 (if (equal text "-") (my/cli--read-stdin) text)))
                (lambda (_value) (my/cli--print "Appended"))))
      ("types"
       (funcall
        emit (my/api-types)
        (lambda (value)
          (seq-doseq (type value)
            (my/cli--print
             (format "%s (#%s%s): %s"
                     (alist-get 'name type) (alist-get 'tag type)
                     (if (string-empty-p (alist-get 'extends type)) ""
                       (format ", extends %s" (alist-get 'extends type)))
                     (mapconcat
                      (lambda (field)
                        (concat (alist-get 'name field)
                                (if (equal (alist-get 'kind field) "text") ""
                                  (concat ":" (alist-get 'kind field)))))
                      (alist-get 'fields type) " ")))))))
      ("views"
       (funcall
        emit (my/api-views)
        (lambda (value)
          (seq-doseq (view value)
            (my/cli--print (format "%s  [%s%s]  %s" (alist-get 'name view)
                                   (alist-get 'layout view)
                                   (if (string-empty-p (alist-get 'group view)) ""
                                     (concat " by " (alist-get 'group view)))
                                   (alist-get 'type view)))))))
      ("query"
       (funcall
        emit (my/api-query (my/cli--query-params options))
        (lambda (value)
          (seq-doseq (group (alist-get 'groups value))
            (unless (string-empty-p (alist-get 'group group))
              (my/cli--print (format "== %s (%d)" (alist-get 'group group)
                                     (length (alist-get 'nodes group)))))
            (my/cli--show-nodes (alist-get 'nodes group)))
          (my/cli--print (format "%d nodes" (alist-get 'count value))))))
      ("import"
       (unless (= (length rest) 1) (user-error "Usage: orgseq import DIR"))
       (funcall emit (my/api-import (car rest))
                (lambda (value)
                  (my/cli--print (format "Copied %d files from %s"
                                         (alist-get 'copied value)
                                         (alist-get 'source value))))))
      ((or "import-notion" "import-tana")
       (unless (= (length rest) 1)
         (user-error "Usage: orgseq %s %s [--profile FILE] [--route PREFIX=DEST]... [--yes]"
                     command (if (equal command "import-tana") "FILE" "DIR")))
       (let* ((yes (cdr (assoc "--yes" options)))
              (tana (equal command "import-tana"))
              (profile (and (cdr (assoc "--profile" options))
                            (my/import-profile-read
                             (cdr (assoc "--profile" options)))))
              (pairs (lambda (option what key)
                       (append
                        (mapcar
                         (lambda (pair)
                           (unless (string-match "\\`\\([^=]+\\)=\\(.+\\)\\'" pair)
                             (user-error "%s expects %s, got %s" option what pair))
                           (cons (match-string 1 pair) (match-string 2 pair)))
                         (cdr (assoc option options)))
                        (plist-get profile key))))
              (types (funcall pairs "--db-type" "NAME=TYPE" :types))
              (map (funcall pairs "--map" "NAME=FIELD" :map))
              (routes (funcall pairs "--route" "PREFIX=DEST" :routes))
              (value
               (if tana
                   (my/api-import-tana (car rest) yes
                                       :types types :map map :routes routes)
                 (my/api-import-notion
                  (car rest) yes
                  :type (cdr (assoc "--type" options))
                  :types types
                  :layer (cdr (assoc "--layer" options))
                  :folder (cdr (assoc "--folder" options))
                  :private (cdr (assoc "--private" options))
                  :lenient (and profile t)
                  :map map :routes routes)))
              (what (if tana "items" "pages"))
              (places (lambda (v)
                        (mapconcat #'identity (alist-get 'targets v) ", "))))
         (funcall
          emit value
          (lambda (v)
            (seq-doseq (database (alist-get 'databases v))
              (my/cli--print
               (format "  database %s%s: %d pages; properties: %s%s"
                       (alist-get 'name database)
                       (if (string-empty-p (alist-get 'type database)) ""
                         (format " as %s" (alist-get 'type database)))
                       (alist-get 'pages database)
                       (mapconcat #'identity
                                  (alist-get 'properties database) ", ")
                       (if (zerop (length (alist-get 'not_in_type database)))
                           ""
                         (format "; not fields of the type: %s"
                                 (mapconcat #'identity
                                            (alist-get 'not_in_type database)
                                            ", "))))))
            (seq-doseq (tag (alist-get 'tags v))
              (my/cli--print
               (format "  supertag %s%s: %d nodes"
                       (alist-get 'name tag)
                       (if (string-empty-p (alist-get 'type tag)) ""
                         (format " as %s" (alist-get 'type tag)))
                       (alist-get 'count tag))))
            (cond
             ((eq (alist-get 'imported v) t)
              (my/cli--print
               (if tana
                   (format "Imported %d notes and %d days into %s (%d notes in the private zone); skipped %d imported before; %d references into the private zone withheld"
                           (alist-get 'created v) (alist-get 'days_written v)
                           (funcall places v) (alist-get 'private v)
                           (alist-get 'existing v) (alist-get 'withheld_links v))
                 (format "Imported %d pages and %d attachments into %s (%d pages in the private zone); skipped %d imported before; %d links point outside the export; %d links into the private zone withheld"
                         (alist-get 'created v) (alist-get 'assets v)
                         (funcall places v) (alist-get 'private v)
                         (alist-get 'existing v)
                         (alist-get 'unresolved_links v)
                         (alist-get 'withheld_links v)))))
             ((zerop (alist-get 'new v))
              (my/cli--print
               (format "Nothing to import; %d %s were imported before"
                       (alist-get 'existing v) what)))
             (t
              (my/cli--print
               (format "Would import %d %s into %s (%d of them into the private zone; %d left out by a route; %d imported before); nothing changed, add --yes to import"
                       (alist-get 'new v) what (funcall places v)
                       (alist-get 'new_private v) (alist-get 'left_out v)
                       (alist-get 'existing v)))))))
         (if (or yes (zerop (alist-get 'new value))) 0 1)))
      ("export"
       (unless (= (length rest) 1) (user-error "Usage: orgseq export DIR"))
       (funcall emit (my/api-export (car rest))
                (lambda (value)
                  (my/cli--print (format "Exported to %s"
                                         (alist-get 'folder value))))))
      ("snapshot"
       (funcall emit (my/api-snapshot)
                (lambda (value)
                  (my/cli--print
                   (if (string-empty-p (alist-get 'folder value))
                       "The library is empty; nothing to snapshot"
                     (format "Snapshot in %s" (alist-get 'folder value)))))))
      ("snapshots"
       (funcall emit (my/api-snapshots)
                (lambda (value)
                  (if (zerop (length value))
                      (my/cli--print "No snapshots yet")
                    (seq-doseq (snapshot value)
                      (my/cli--print
                       (format "%s  %d files  %s" (alist-get 'name snapshot)
                               (alist-get 'files snapshot)
                               (file-size-human-readable
                                (alist-get 'bytes snapshot)))))))))
      ("restore"
       (unless (= (length rest) 1)
         (user-error "Usage: orgseq restore NAME --yes (see `orgseq snapshots')"))
       (let* ((yes (cdr (assoc "--yes" options)))
              (value (my/api-restore (car rest) yes)))
         (funcall emit value
                  (lambda (v)
                    (if (eq (alist-get 'restored v) t)
                        (progn
                          (my/cli--print
                           (format "Restored %d files from %s, deleted %d"
                                   (alist-get 'files v) (alist-get 'snapshot v)
                                   (alist-get 'deleted v)))
                          (my/cli--print
                           (format "Undo with: orgseq restore %s --yes"
                                   (if (string-empty-p (alist-get 'undo_snapshot v))
                                       "(none; the library was empty)"
                                     (file-name-nondirectory
                                      (alist-get 'undo_snapshot v))))))
                      (my/cli--print
                       (format "Would restore %d files from %s and delete %d library files not in it"
                               (alist-get 'would_write v) (alist-get 'snapshot v)
                               (alist-get 'would_delete v)))
                      (seq-doseq (rel (alist-get 'delete v))
                        (my/cli--print (format "  delete %s" rel)))
                      (my/cli--print "Nothing changed; add --yes to restore"))))
         (if yes 0 1)))
      ("migrate"
       (let* ((yes (cdr (assoc "--yes" options)))
              (value (my/api-migrate yes)))
         (funcall emit value
                  (lambda (v)
                    (cond
                     ((eq (alist-get 'migrated v) t)
                      (my/cli--print
                       (format "Moved %d files, left %d in place; the state before is snapshot %s"
                               (alist-get 'moved v) (alist-get 'skipped v)
                               (file-name-nondirectory (alist-get 'snapshot v)))))
                     ((zerop (alist-get 'would_move v))
                      (my/cli--print "The library already has the current layout"))
                     (t
                      (seq-doseq (move (alist-get 'moves v))
                        (my/cli--print (format "  %s -> %s" (alist-get 'from move)
                                               (alist-get 'to move))))
                      (my/cli--print
                       (format "Would move %d files; nothing changed, add --yes to migrate"
                               (alist-get 'would_move v)))))))
         (if (or yes (zerop (alist-get 'would_move value))) 0 1)))
      ("sync"
       (let ((value (my/api-sync (cdr (assoc "--preview" options)))))
         (funcall emit value
                  (lambda (v)
                    (my/cli--print (alist-get 'status v))
                    (seq-doseq (file (alist-get 'conflicts v))
                      (my/cli--print (format "conflict copy: %s" file)))))
         (if (eq (alist-get 'ok value) t) 0 1)))
      ("doctor"
       (let ((value (my/api-doctor)))
         (funcall emit value
                  (lambda (v)
                    (seq-doseq (result v)
                      (my/cli--print
                       (format "%-5s %-24s %s%s"
                               (upcase (alist-get 'status result))
                               (alist-get 'check result)
                               (alist-get 'detail result)
                               (if (string-empty-p (alist-get 'remedy result)) ""
                                 (format "\n      -> %s"
                                         (alist-get 'remedy result))))))))
         (if (seq-some (lambda (r) (equal (alist-get 'status r) "fail")) value)
             1 0)))
      ("update"
       (my/package-update-all)
       (my/cli--print "Packages updated; restart Emacs to load them")
       0)
      ("reindex"
       (my/api-refresh)
       (my/cli--print (format "Index rebuilt from %d files" (my/index-rebuild)))
       0)
      ("info"
       (funcall emit (my/api-info)
                (lambda (value)
                  (my/cli--print (format "version: %s" (alist-get 'version value)))
                  (my/cli--print (format "library: %s (%d Org files)"
                                         (alist-get 'library value)
                                         (alist-get 'notes value)))
                  (my/cli--print (format "types:   %s" (alist-get 'types_file value)))
                  (my/cli--print (format "views:   %s" (alist-get 'views_file value)))
                  (my/cli--print (format "sync:    %s" (alist-get 'sync value)))
                  (my/cli--print
                   (format "backup:  %d snapshots in %s%s"
                           (alist-get 'snapshots value)
                           (alist-get 'snapshot_dir value)
                           (if (string-empty-p (alist-get 'last_snapshot value)) ""
                             (format ", newest %s"
                                     (alist-get 'last_snapshot value)))))
                  (unless (string-empty-p (alist-get 'private_dir value))
                    (my/cli--print
                     (format "private: %s (%d files; not indexed, not synced)"
                             (alist-get 'private_dir value)
                             (alist-get 'private_files value))))
                  (unless (string-empty-p (alist-get 'legacy_library value))
                    (my/cli--print
                     (format "old library not imported: %s (orgseq import DIR)"
                             (alist-get 'legacy_library value)))))))
      ("mcp"
       (let ((level (or (cdr (assoc "--access" options))
                        (let ((env (getenv "ORG_SEQ_MCP_ACCESS")))
                          (and env (not (string-empty-p env)) env)))))
         (when level
           (my/mcp--level level)
           (setq my/mcp-access level)))
       (my/mcp-serve) 0)
      (_ (user-error "Unknown command %s; run `orgseq help'" command)))))

(defun my/cli-main ()
  "Entry point of bin/orgseq: run the command given on the command line."
  (let* ((args (cl-remove "--" command-line-args-left :test #'equal :count 1))
         (code 0))
    (setq command-line-args-left nil)
    (condition-case err
        (setq code (if args
                       (my/cli--run (car args) (cdr args))
                     (progn (my/cli--print my/cli-usage) 0)))
      (error
       (message "orgseq: %s" (error-message-string err))
       (setq code 2)))
    (kill-emacs code)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: MCP server
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Transport: newline-delimited JSON-RPC 2.0 on standard input and output
;; (the MCP stdio transport).  Standard output carries protocol messages
;; only; diagnostics go to standard error through `message'.

(defconst my/mcp-protocol-version "2025-06-18"
  "MCP protocol revision this server speaks when the client names none.")

(defun my/mcp--schema (properties &optional required)
  "Return a JSON schema object with PROPERTIES and REQUIRED names.
PROPERTIES is a list of (NAME TYPE DESCRIPTION)."
  (list (cons 'type "object")
        (cons 'properties
              (or (mapcar (lambda (p)
                            (cons (intern (nth 0 p))
                                  (append
                                   (list (cons 'type (nth 1 p))
                                         (cons 'description (nth 2 p)))
                                   (and (equal (nth 1 p) "array")
                                        (list (cons 'items
                                                    (list (cons 'type "string"))))))))
                          properties)
                  (make-hash-table)))
        (cons 'required (vconcat required))))

(defun my/mcp--arg (arguments name)
  "Return argument NAME from ARGUMENTS, an alist with symbol keys."
  (alist-get (intern name) arguments))

(defconst my/mcp--filter-help
  "Filter form, an s-expression: (type \"reading\"), (tag \"x\"), (todo \"NEXT\"), (field \"YEAR\" > 2020) with ops = != < > <= >= contains has, (field \"STATUS\" \"read\"), (field \"TOPIC\" empty|set), (modified-within 7), (created-within 7), (links-to \"ID\"), (linked-from \"ID\"), (under \"ID\"), (title \"str\"), (text \"str\"), (layer inbox|project|area|resource|archive|ai) (the archive layer is left out unless a layer is named), combined with (and ...), (or ...), (not ...)."
  "Filter syntax summary included in tool descriptions.")

(defun my/mcp-tools ()
  "Return the MCP tools as a list of (NAME DESCRIPTION SCHEMA HANDLER)."
  (list
   (list "search_notes"
         "Find notes by title and matching lines by text across the library."
         (my/mcp--schema '(("query" "string" "Text to look for")
                           ("limit" "integer" "Maximum results per kind (default 20)"))
                         '("query"))
         (lambda (a) (my/api-search (my/mcp--arg a "query") (my/mcp--arg a "limit"))))
   (list "get_node"
         "Read one node: tags, fields, links in both directions and its Org text."
         (my/mcp--schema '(("id" "string" "Node id")) '("id"))
         (lambda (a) (my/api-node (my/mcp--arg a "id"))))
   (list "create_node"
         "Create a note.  With a type it gets the type's tag, fields and template."
         (my/mcp--schema
          '(("title" "string" "Note title")
            ("type" "string" "Type name or tag (see list_types)")
            ("fields" "object" "Field values, e.g. {\"STATUS\": \"queued\"}")
            ("body" "string" "Org text of the note")
            ("tags" "array" "Extra tags")
            ("template" "string" "Named template of the type (see list_types)"))
          '("title"))
         (lambda (a)
           (my/api-create (my/mcp--arg a "title") (my/mcp--arg a "type")
                          (mapcar (lambda (f) (cons (symbol-name (car f))
                                                    (format "%s" (cdr f))))
                                  (my/mcp--arg a "fields"))
                          (my/mcp--arg a "body") (my/mcp--arg a "tags")
                          (my/mcp--arg a "template"))))
   (list "append_daily"
         "Append a timestamped line to today's Daily note (quick capture)."
         (my/mcp--schema '(("text" "string" "Text to record")) '("text"))
         (lambda (a) (my/api-append-daily (my/mcp--arg a "text"))))
   (list "append_to_node"
         "Append Org text to the end of a node."
         (my/mcp--schema '(("id" "string" "Node id")
                           ("text" "string" "Org text to append"))
                         '("id" "text"))
         (lambda (a) (my/api-append (my/mcp--arg a "id") (my/mcp--arg a "text"))))
   (list "set_field"
         "Set a field (Org property) on a node; an empty value clears it.  For a node-link field pass [[id:ID][Title]]."
         (my/mcp--schema '(("id" "string" "Node id")
                           ("field" "string" "Field name")
                           ("value" "string" "New value"))
                         '("id" "field" "value"))
         (lambda (a) (my/api-set-field (my/mcp--arg a "id") (my/mcp--arg a "field")
                                       (my/mcp--arg a "value"))))
   (list "set_type"
         "Make a node an instance of a type, replacing its previous type.  Field values stay."
         (my/mcp--schema '(("id" "string" "Node id")
                           ("type" "string" "Type name or tag"))
                         '("id" "type"))
         (lambda (a) (my/api-set-type (my/mcp--arg a "id") (my/mcp--arg a "type"))))
   (list "file_node"
         "Move a node out of the Inbox (staging) into a library layer once it is worth keeping.  The id stays the same.  A heading becomes a file of its own and a link is left in its place."
         (my/mcp--schema '(("id" "string" "Node id")
                           ("layer" "string" "project, area, resource, archive or ai")
                           ("type" "string" "Optional type name or tag to apply")
                           ("folder" "string" "Optional folder inside the layer, such as a project name"))
                         '("id" "layer"))
         (lambda (a) (my/api-file (my/mcp--arg a "id") (my/mcp--arg a "layer")
                                  (my/mcp--arg a "type") (my/mcp--arg a "folder"))))
   (list "list_types"
         "List node types (supertags) with their fields, field kinds and allowed values."
         (my/mcp--schema nil)
         (lambda (_a) (my/api-types)))
   (list "list_views"
         "List saved views (query plus table, list or board layout)."
         (my/mcp--schema nil)
         (lambda (_a) (my/api-views)))
   (list "query_nodes"
         (concat "Run a saved view or an ad-hoc structured query and return the nodes, optionally grouped.  "
                 my/mcp--filter-help
                 "  Columns may be field names, formula names, multi-hop paths like TOPIC.AREA, reverse relations like <-reading or <-task.HOURS, rollups like count(<-reading) sum(<-task.HOURS) latest(<-meeting.@modified), or @title @todo @tags @modified @created @in @out.")
         (my/mcp--schema
          '(("view" "string" "Name of a saved view to run")
            ("type" "string" "Type tag; also matches types extending it")
            ("filter" "string" "Filter form as text")
            ("group" "string" "Field to group by")
            ("columns" "array" "Columns to return")
            ("sort" "string" "Sort keys, e.g. \"YEAR desc, @title\"")
            ("limit" "integer" "Maximum number of nodes")))
         (lambda (a)
           (let (params)
             (dolist (key '("view" "type" "group" "columns" "sort" "limit"))
               (when (my/mcp--arg a key)
                 (setq params (plist-put params (intern (concat ":" key))
                                         (my/mcp--arg a key)))))
             (when-let* ((filter (my/mcp--arg a "filter")))
               (unless (string-empty-p filter)
                 (setq params (plist-put params :filter
                                         (car (read-from-string filter))))))
             (my/api-query params))))
   (list "sync_library"
         "Sync the library with the configured cloud remote; preview only reports."
         (my/mcp--schema '(("preview" "boolean" "Report without changing anything")))
         (lambda (a) (my/api-sync (my/mcp--arg a "preview"))))
   (list "library_info"
         "Show where the library lives, the sync status and module load failures."
         (my/mcp--schema nil)
         (lambda (_a) (my/api-info)))
   (list "doctor"
         "Run the org-seq self-check (Emacs build, tools, packages, library)."
         (my/mcp--schema nil)
         (lambda (_a) (my/api-doctor)))))

(defconst my/mcp-access-levels '("read" "inbox" "write" "structure")
  "Access levels of an MCP client, each including the ones before it.
read: search and read.  inbox: also add notes to the Inbox and append
to today's Daily.  write: also change, retype and file existing nodes
and create notes in any layer.  structure: also run library-wide
operations such as sync.")

(defvar my/mcp-access "write"
  "Access level of the MCP server being served; see `my/mcp-access-levels'.
Set by `orgseq mcp --access LEVEL' or ORG_SEQ_MCP_ACCESS.")

(defconst my/mcp--tool-access
  '(("search_notes" . "read") ("get_node" . "read") ("list_types" . "read")
    ("list_views" . "read") ("query_nodes" . "read") ("library_info" . "read")
    ("doctor" . "read")
    ("create_node" . "inbox") ("append_daily" . "inbox")
    ("append_to_node" . "write") ("set_field" . "write") ("set_type" . "write")
    ("file_node" . "write")
    ("sync_library" . "structure"))
  "Lowest access level that may call each MCP tool.
A tool missing from this list needs the highest level.")

(defun my/mcp--level (name)
  "Return the rank of access level NAME, or signal a user error."
  (or (cl-position name my/mcp-access-levels :test #'equal)
      (user-error "Unknown access level %s (one of: %s)" name
                  (string-join my/mcp-access-levels ", "))))

(defun my/mcp--allowed-p (tool-name)
  "Return non-nil when the current access level may call TOOL-NAME."
  (>= (my/mcp--level my/mcp-access)
      (my/mcp--level (or (cdr (assoc tool-name my/mcp--tool-access))
                         "structure"))))

(defun my/mcp--tool-result (value &optional is-error)
  "Wrap VALUE as an MCP tool result; IS-ERROR marks a failed call."
  (list (cons 'content
              (vector (list (cons 'type "text")
                            (cons 'text (if (stringp value)
                                            value
                                          (my/cli--json value))))))
        (cons 'isError (if is-error t :false))))

(defun my/mcp-handle (request)
  "Handle JSON-RPC REQUEST (an alist) and return the response alist.
Return nil for notifications, which get no response."
  (let* ((id (alist-get 'id request))
         (method (alist-get 'method request))
         (params (alist-get 'params request))
         (reply (lambda (result)
                  (list (cons 'jsonrpc "2.0") (cons 'id id) (cons 'result result))))
         (fail (lambda (code text)
                 (list (cons 'jsonrpc "2.0") (cons 'id id)
                       (cons 'error (list (cons 'code code)
                                          (cons 'message text)))))))
    (cond
     ((null (assq 'id request)) nil)
     ((equal method "initialize")
      (funcall reply
               (list (cons 'protocolVersion
                           (or (alist-get 'protocolVersion params)
                               my/mcp-protocol-version))
                     (cons 'capabilities
                           (list (cons 'tools (make-hash-table))))
                     (cons 'serverInfo (list (cons 'name "org-seq")
                                             (cons 'version "1.0.0")))
                     (cons 'instructions
                           "org-seq note library.  Notes are Org nodes with ids; types (supertags) give nodes fields; views are saved queries.  Call list_types before creating typed notes, and query_nodes for structured questions."))))
     ((equal method "ping") (funcall reply (make-hash-table)))
     ((equal method "tools/list")
      (funcall reply
               (list (cons 'tools
                           (vconcat
                            (mapcar (lambda (tool)
                                      (list (cons 'name (nth 0 tool))
                                            (cons 'description (nth 1 tool))
                                            (cons 'inputSchema (nth 2 tool))))
                                    (cl-remove-if-not
                                     (lambda (tool)
                                       (my/mcp--allowed-p (car tool)))
                                     (my/mcp-tools))))))))
     ((equal method "tools/call")
      (let ((tool (assoc (alist-get 'name params) (my/mcp-tools))))
        (cond
         ((null tool)
          (funcall fail -32602
                   (format "Unknown tool: %s" (alist-get 'name params))))
         ((not (my/mcp--allowed-p (car tool)))
          (funcall reply
                   (my/mcp--tool-result
                    (format "Tool %s needs access level %s; this server runs with %s"
                            (car tool)
                            (or (cdr (assoc (car tool) my/mcp--tool-access))
                                "structure")
                            my/mcp-access)
                    t)))
         (t
          (funcall reply
                   (condition-case err
                       (my/mcp--tool-result
                        (let ((my/api-inbox-only (equal my/mcp-access "inbox")))
                          (funcall (nth 3 tool) (alist-get 'arguments params))))
                     (error
                      (my/mcp--tool-result (error-message-string err) t))))))))
     (t (funcall fail -32601 (format "Method not found: %s" method))))))

(defun my/mcp--read-line ()
  "Return the next line of standard input decoded as UTF-8, or nil at EOF."
  (condition-case nil
      (let ((line (read-string "")))
        (decode-coding-string (encode-coding-string line 'utf-8 t) 'utf-8))
    (error nil)))

(defun my/mcp-serve ()
  "Serve MCP requests from standard input until it closes."
  (let (line)
    (while (setq line (my/mcp--read-line))
      (unless (string-empty-p (string-trim line))
        (let ((response
               (condition-case err
                   (my/mcp-handle
                    (json-parse-string line :object-type 'alist
                                       :array-type 'list
                                       :null-object nil :false-object nil))
                 (error
                  (list (cons 'jsonrpc "2.0") (cons 'id :null)
                        (cons 'error
                              (list (cons 'code -32700)
                                    (cons 'message
                                          (error-message-string err)))))))))
          (when response
            (my/cli--print (my/cli--json response))))))))

(provide 'orgseq-cli)
;;; orgseq-cli.el ends here
