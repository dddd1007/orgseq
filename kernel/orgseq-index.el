;;; orgseq-index.el --- Node index over the Org library -*- lexical-binding: t; -*-
;;
;; Kernel file: no UI, no dependency on any module or on org-roam.
;;
;; The Org files are the only authority.  This index is a disposable copy
;; of what they say, kept in SQLite (built into Emacs) so views, searches
;; and the command line do not re-read the library:
;;
;;   Node      A file or heading with an :ID: property.
;;   Record    The plist handed to callers: :id :title :tags :file :mtime
;;             :props :todo :priority :level :olp :pos.
;;   Scope     Every .org file in the library except the reference layer,
;;             the archives, hidden directories and sync conflict copies.
;;   Refresh   Incremental: a file is re-read when its modification time
;;             or size changed.  Nothing has to watch the file system, so
;;             edits made by sync, git or another program are picked up.
;;   Text      Each node's own text goes into an FTS5 table with the
;;             trigram tokenizer, which finds substrings in any script
;;             (Chinese included) without word segmentation.
;;   Sharing   The interactive session, the daemon and the command line
;;             open the same file; SQLite serializes their writes, and
;;             every writer derives the same rows from the same files.
;;
;; Deleting the index file is always safe; the next use rebuilds it.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │ Section 1  Database                                              │
;; │ Section 2  Parsing Org text                                      │
;; │ Section 3  Writing                                               │
;; │ Section 4  Reading                                               │
;; └─────────────────────────────────────────────────────────────────┘

(require 'cl-lib)
(require 'subr-x)
(require 'sqlite)
(require 'orgseq-paths)

(defvar org-todo-keywords)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Database
;; ═══════════════════════════════════════════════════════════════════════════

(defcustom my/index-file nil
  "SQLite file holding the node index; nil derives one from the library path.
The derived name contains a hash of `my/note-home', so a session pointed
at another library (validation runs) never rewrites the real index.
Device-local, under .cache/ in the Emacs directory."
  :type '(choice (const :tag "Derived from the library path" nil) file)
  :group 'org-seq)

(defcustom my/index-sync-interval 2
  "Seconds during which a finished refresh is trusted without rechecking files."
  :type 'number
  :group 'org-seq)

(defconst my/index--schema-version 1
  "Bumped when the tables change; an older index is rebuilt.")

(defvar my/index--db nil "Open database connection, or nil.")
(defvar my/index--db-file nil "File `my/index--db' was opened on.")
(defvar my/index--fts nil "Non-nil when the text table is an FTS5 table.")
(defvar my/index--last-sync nil "Float time of the last finished refresh.")
(defvar my/index--cache nil
  "Cons (DATA-VERSION . RECORDS) of the last full read, or nil.")

(defun my/index--file ()
  "Return the index file for the current library."
  (or my/index-file
      (expand-file-name
       (format ".cache/index-%s.db"
               (substring (sha1 (expand-file-name my/note-home)) 0 10))
       user-emacs-directory)))

(defun my/index--create-tables (db)
  "Create the tables in DB, replacing any from another schema version."
  (dolist (table '("meta" "files" "nodes" "links" "text"))
    (sqlite-execute db (format "DROP TABLE IF EXISTS %s" table)))
  (sqlite-execute db "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
  (sqlite-execute db "CREATE TABLE files (path TEXT PRIMARY KEY, mtime REAL, size INTEGER)")
  (sqlite-execute db "CREATE TABLE nodes (id TEXT PRIMARY KEY, file TEXT, level INTEGER,
 pos INTEGER, title TEXT, todo TEXT, priority TEXT, tags TEXT, olp TEXT, props TEXT)")
  (sqlite-execute db "CREATE INDEX nodes_file ON nodes (file)")
  (sqlite-execute db "CREATE TABLE links (source TEXT, dest TEXT, file TEXT)")
  (sqlite-execute db "CREATE INDEX links_file ON links (file)")
  (sqlite-execute db "CREATE INDEX links_dest ON links (dest)")
  (let ((fts (condition-case nil
                 (progn
                   (sqlite-execute db "CREATE VIRTUAL TABLE text USING fts5
 (id UNINDEXED, file UNINDEXED, title, body, tokenize=\"trigram\")")
                   t)
               (error
                ;; SQLite without FTS5 or the trigram tokenizer: keep the
                ;; same columns in a plain table and search it with LIKE.
                (sqlite-execute db "CREATE TABLE text (id TEXT, file TEXT, title TEXT, body TEXT)")
                nil))))
    (sqlite-execute db "INSERT INTO meta VALUES ('schema', ?)"
                    (list (number-to-string my/index--schema-version)))
    (sqlite-execute db "INSERT INTO meta VALUES ('fts', ?)" (list (if fts "1" "0")))))

(defun my/index--meta (db key)
  "Return the meta value for KEY in DB, or nil."
  (ignore-errors
    (caar (sqlite-select db "SELECT value FROM meta WHERE key = ?" (list key)))))

(defun my/index--open ()
  "Return the database connection for the current library, opening it."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (error "This Emacs has no SQLite support; the node index needs it"))
  (let ((file (my/index--file)))
    (unless (and my/index--db (sqlitep my/index--db) (equal file my/index--db-file))
      (my/index-close)
      (make-directory (file-name-directory file) t)
      (let ((db (sqlite-open file)))
        (ignore-errors (sqlite-pragma db "journal_mode = WAL"))
        (ignore-errors (sqlite-pragma db "busy_timeout = 5000"))
        (unless (equal (my/index--meta db "schema")
                       (number-to-string my/index--schema-version))
          (my/index--create-tables db))
        (setq my/index--db db
              my/index--db-file file
              my/index--fts (equal (my/index--meta db "fts") "1")
              my/index--last-sync nil
              my/index--cache nil)))
    my/index--db))

(defun my/index-close ()
  "Close the index connection, if one is open."
  (when (and my/index--db (sqlitep my/index--db))
    (ignore-errors (sqlite-close my/index--db)))
  (setq my/index--db nil
        my/index--db-file nil
        my/index--last-sync nil
        my/index--cache nil))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Parsing Org text
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; A plain scan of the buffer text, without `org-mode': only headings,
;; property drawers, planning lines, #+title, #+filetags and id links are
;; needed, and the scan stays fast on a library of thousands of files.

(defconst my/index-default-todo-keywords
  '("PROJECT" "TODO" "NEXT" "IN-PROGRESS" "WAITING" "SOMEDAY" "DONE" "CANCELLED")
  "TODO keywords recognized when Org's own configuration is not loaded.")

(defun my/index--todo-keywords ()
  "Return the TODO keywords to recognize at the start of a heading."
  (let (keywords)
    (when (bound-and-true-p org-todo-keywords)
      (dolist (sequence org-todo-keywords)
        (dolist (entry (cdr sequence))
          (when (and (stringp entry) (not (equal entry "|")))
            (push (replace-regexp-in-string "(.*\\'" "" entry) keywords)))))
    (delete-dups (append (nreverse keywords) my/index-default-todo-keywords))))

(defun my/index--clean-title (text)
  "Return heading or title TEXT with link markup reduced to its description."
  (let* ((text (replace-regexp-in-string
                "\\[\\[[^]]+\\]\\[\\([^]]+\\)\\]\\]" "\\1" text))
         (text (replace-regexp-in-string
                "\\[\\[\\([^]]+\\)\\]\\]" "\\1" text)))
    (string-trim (replace-regexp-in-string "[ \t]+" " " text))))

(defun my/index--parse-drawer ()
  "Parse the property drawer starting on the current line.
Return an alist of (UPCASED-NAME . VALUE) and leave point after :END:."
  (let ((case-fold-search t)
        props)
    (forward-line 1)
    (while (and (not (eobp))
                (not (looking-at "^[ \t]*:END:[ \t]*$"))
                (looking-at "^[ \t]*:\\([^: \t\n]+\\):[ \t]*\\(.*\\)$"))
      (push (cons (upcase (match-string-no-properties 1))
                  (string-trim (match-string-no-properties 2)))
            props)
      (forward-line 1))
    (when (looking-at "^[ \t]*:END:")
      (forward-line 1))
    (nreverse props)))

(defun my/index--subtree-end (headings index level)
  "Return where the subtree of heading INDEX (at LEVEL) ends.
HEADINGS is a vector of (POS . LEVEL) in buffer order."
  (let ((i (1+ index))
        (count (length headings))
        end)
    (while (and (< i count) (not end))
      (when (<= (cdr (aref headings i)) level)
        (setq end (car (aref headings i))))
      (setq i (1+ i)))
    (or end (point-max))))

(defun my/index-parse-buffer (file)
  "Parse the Org text in the current buffer as the contents of FILE.
Return (NODES LINKS TEXTS): node plists in buffer order, (SOURCE . DEST)
id links, and (ID . OWN-TEXT) pairs.  A node's own text is its subtree
without the subtrees of nodes nested in it."
  (let ((keywords (my/index--todo-keywords))
        (case-fold-search t)
        file-props file-title file-tags
        headings stack nodes)
    ;; File-level property drawer: first thing after blank and comment lines.
    (goto-char (point-min))
    (while (and (not (eobp)) (looking-at "^[ \t]*\\(#[^+\n].*\\)?$"))
      (forward-line 1))
    (when (looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
      (setq file-props (my/index--parse-drawer)))
    ;; Keywords above the first heading.
    (let ((limit (save-excursion
                   (goto-char (point-min))
                   (if (re-search-forward "^\\*+[ \t]" nil t)
                       (line-beginning-position)
                     (point-max)))))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" limit t)
        (setq file-title (my/index--clean-title (match-string-no-properties 1))))
      (goto-char (point-min))
      (while (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" limit t)
        (setq file-tags
              (append file-tags
                      (split-string (match-string-no-properties 1) "[: \t]+" t)))))
    (when (assoc "ID" file-props)
      (push (list :id (cdr (assoc "ID" file-props))
                  :file file :level 0 :pos 1 :end (point-max)
                  :title (if (and file-title (not (string-empty-p file-title)))
                             file-title
                           (file-name-base file))
                  :tags (delete-dups (copy-sequence file-tags))
                  :props file-props)
            nodes))
    ;; Headings.
    (goto-char (point-min))
    (while (re-search-forward "^\\(\\*+\\)[ \t]+\\(.*\\)$" nil t)
      (let* ((level (length (match-string 1)))
             (pos (match-beginning 0))
             (text (match-string-no-properties 2))
             todo priority tags props)
        (push (cons pos level) headings)
        (let ((case-fold-search nil))
          (when (string-match "[ \t]+\\(:[[:alnum:]_@#%:]+:\\)[ \t]*\\'" text)
            ;; `split-string' replaces the match data; cut the text first.
            (let ((found (match-string 1 text)))
              (setq text (substring text 0 (match-beginning 0))
                    tags (split-string found ":" t))))
          (when (and (string-match "\\`\\([^ \t]+\\)\\(?:[ \t]+\\|\\'\\)" text)
                     (member (match-string 1 text) keywords))
            (setq todo (match-string 1 text)
                  text (substring text (match-end 0))))
          (when (string-match "\\`\\[#\\([A-Z0-9]\\)\\][ \t]*" text)
            (setq priority (match-string 1 text)
                  text (substring text (match-end 0)))))
        (while (and stack (>= (plist-get (car stack) :level) level))
          (pop stack))
        (forward-line 1)
        (let ((case-fold-search nil)
              planning)
          (when (looking-at "^[ \t]*\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\):")
            (let ((eol (line-end-position)))
              (while (re-search-forward
                      "\\(SCHEDULED\\|DEADLINE\\|CLOSED\\):[ \t]*\\([<[][^]>\n]+[]>]\\)"
                      eol t)
                (push (cons (match-string-no-properties 1)
                            (match-string-no-properties 2))
                      planning)))
            (forward-line 1))
          (when (let ((case-fold-search t))
                  (looking-at "^[ \t]*:PROPERTIES:[ \t]*$"))
            (setq props (my/index--parse-drawer)))
          (setq props (append props (nreverse planning))))
        (let ((id (cdr (assoc "ID" props)))
              (title (my/index--clean-title text))
              (inherited (apply #'append file-tags
                                (mapcar (lambda (entry) (plist-get entry :tags))
                                        (reverse stack))))
              (olp (mapcar (lambda (entry) (plist-get entry :title))
                           (reverse stack))))
          (when (and id (not (string-empty-p id)))
            (push (list :id id :file file :level level :pos pos
                        :heading (1- (length headings))
                        :title title :todo todo :priority priority
                        :tags (delete-dups (append inherited tags))
                        :olp olp :props props)
                  nodes))
          (push (list :level level :title title :tags tags) stack))))
    (setq nodes (nreverse nodes))
    ;; Subtree ends, then each node's own segments, links and text.
    (let ((headings (vconcat (nreverse headings)))
          links texts)
      (dolist (node nodes)
        (unless (plist-get node :end)
          (plist-put node :end
                     (my/index--subtree-end headings (plist-get node :heading)
                                            (plist-get node :level)))))
      (let ((rest nodes))
        (while rest
          (let* ((node (car rest))
                 (end (plist-get node :end))
                 (cursor (plist-get node :pos))
                 (parts nil))
            (dolist (inner (cdr rest))
              (let ((start (plist-get inner :pos)))
                (when (and (< start end) (>= start cursor))
                  (push (cons cursor start) parts)
                  (setq cursor (plist-get inner :end)))))
            (when (< cursor end)
              (push (cons cursor end) parts))
            (let ((own nil))
              (dolist (part (nreverse parts))
                (push (buffer-substring-no-properties (car part) (cdr part)) own)
                (goto-char (car part))
                (while (re-search-forward "\\[\\[id:\\([^]\n]+\\)\\]" (cdr part) t)
                  (push (cons (plist-get node :id)
                              (string-trim (match-string-no-properties 1)))
                        links)))
              (push (cons (plist-get node :id)
                          (string-join (nreverse own) ""))
                    texts)))
          (setq rest (cdr rest))))
      (list nodes (nreverse links) (nreverse texts)))))

(defun my/index-parse-file (file)
  "Parse FILE; see `my/index-parse-buffer'."
  (with-temp-buffer
    (insert-file-contents file)
    (my/index-parse-buffer file)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Writing
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/index--excluded-dirs ()
  "Return the library directories that are not indexed."
  (mapcar (lambda (dir) (directory-file-name (expand-file-name dir)))
          (list my/library-dir my/archives-dir)))

(defun my/index-file-p (file)
  "Return non-nil when FILE is an Org file inside the indexed scope."
  (let ((file (expand-file-name file))
        (home (file-name-as-directory (expand-file-name my/note-home))))
    (and (string-suffix-p ".org" file)
         (string-prefix-p home file)
         (not (string-match-p "\\.conflict[0-9]*\\.org\\'" file))
         (not (string-prefix-p ".#" (file-name-nondirectory file)))
         (not (cl-some (lambda (part) (string-prefix-p "." part))
                       (split-string (substring file (length home)) "/" t)))
         (not (cl-some (lambda (dir)
                         (string-prefix-p (file-name-as-directory dir) file))
                       (my/index--excluded-dirs))))))

(defun my/index-files ()
  "Return every Org file in the indexed scope."
  (let ((home (directory-file-name (expand-file-name my/note-home)))
        (excluded (my/index--excluded-dirs)))
    (when (file-directory-p home)
      (cl-remove-if-not
       #'my/index-file-p
       (directory-files-recursively
        home "\\.org\\'" nil
        (lambda (dir)
          (and (not (member dir excluded))
               (not (string-prefix-p "." (file-name-nondirectory dir))))))))))

(defun my/index--print (value)
  "Return VALUE printed so `read' restores it."
  (let ((print-length nil) (print-level nil) (print-escape-newlines t))
    (prin1-to-string value)))

(defun my/index--forget (db file)
  "Remove every row derived from FILE from DB."
  (dolist (table '("nodes" "links" "text"))
    (sqlite-execute db (format "DELETE FROM %s WHERE file = ?" table) (list file)))
  (sqlite-execute db "DELETE FROM files WHERE path = ?" (list file)))

(defun my/index--store (db file mtime size)
  "Replace the rows of FILE in DB with what the file says now."
  (pcase-let ((`(,nodes ,links ,texts) (my/index-parse-file file)))
    (my/index--forget db file)
    (dolist (node nodes)
      ;; An id used twice keeps the copy indexed last, as Org itself
      ;; resolves an id to one location only.
      (sqlite-execute db "DELETE FROM text WHERE id = ?" (list (plist-get node :id)))
      (sqlite-execute
       db "INSERT OR REPLACE INTO nodes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
       (list (plist-get node :id) file
             (plist-get node :level) (plist-get node :pos)
             (plist-get node :title)
             (plist-get node :todo) (plist-get node :priority)
             (my/index--print (plist-get node :tags))
             (my/index--print (plist-get node :olp))
             (my/index--print (plist-get node :props)))))
    (dolist (link links)
      (sqlite-execute db "INSERT INTO links VALUES (?, ?, ?)"
                      (list (car link) (cdr link) file)))
    (let ((titles (make-hash-table :test 'equal)))
      (dolist (node nodes)
        (puthash (plist-get node :id) (plist-get node :title) titles))
      (dolist (text texts)
        (sqlite-execute db "INSERT INTO text (id, file, title, body) VALUES (?, ?, ?, ?)"
                        (list (car text) file
                              (gethash (car text) titles "") (cdr text)))))
    (sqlite-execute db "INSERT OR REPLACE INTO files VALUES (?, ?, ?)"
                    (list file mtime size))))

(defun my/index-sync (&optional force)
  "Bring the index in line with the Org files; return how many files changed.
Only files whose modification time or size changed are re-read.  FORCE
is nil to trust a refresh finished within `my/index-sync-interval', the
symbol `check' to compare the files now, and anything else to re-read
every file."
  (let ((db (my/index--open))
        (reread (and force (not (eq force 'check)))))
    (if (and (not force) my/index--last-sync
             (< (- (float-time) my/index--last-sync) my/index-sync-interval))
        0
      (let ((known (make-hash-table :test 'equal))
            (seen (make-hash-table :test 'equal))
            (changed 0))
        (pcase-dolist (`(,path ,mtime ,size)
                       (sqlite-select db "SELECT path, mtime, size FROM files"))
          (puthash path (cons mtime size) known))
        (with-sqlite-transaction db
          (dolist (file (my/index-files))
            (let* ((attributes (file-attributes file))
                   (mtime (float-time (file-attribute-modification-time attributes)))
                   (size (file-attribute-size attributes))
                   (old (gethash file known)))
              (puthash file t seen)
              (unless (and old (not reread)
                           (= (car old) mtime) (= (cdr old) size))
                (condition-case err
                    (progn (my/index--store db file mtime size)
                           (setq changed (1+ changed)))
                  (file-error
                   (message "org-seq index: skipped %s: %s"
                            file (error-message-string err)))))))
          (maphash (lambda (path _)
                     (unless (gethash path seen)
                       (my/index--forget db path)
                       (setq changed (1+ changed))))
                   known))
        (setq my/index--last-sync (float-time))
        (when (> changed 0)
          (setq my/index--cache nil))
        changed))))

(defun my/index-update-file (file)
  "Re-read FILE into the index now (after a save or a programmatic edit)."
  (let ((file (expand-file-name file)))
    (when (my/index-file-p file)
      (let ((db (my/index--open)))
        (with-sqlite-transaction db
          (if (file-exists-p file)
              (let ((attributes (file-attributes file)))
                (my/index--store
                 db file
                 (float-time (file-attribute-modification-time attributes))
                 (file-attribute-size attributes)))
            (my/index--forget db file)))
        (setq my/index--cache nil)
        t))))

(defun my/index-rebuild ()
  "Throw the index away and build it again from the Org files."
  (interactive)
  (let ((db (my/index--open)))
    (my/index--create-tables db)
    (setq my/index--fts (equal (my/index--meta db "fts") "1")
          my/index--cache nil))
  (let ((count (my/index-sync 'force)))
    (when (called-interactively-p 'interactive)
      (message "org-seq index: rebuilt from %d files" count))
    count))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Reading
;; ═══════════════════════════════════════════════════════════════════════════

(defconst my/index--record-columns
  "nodes.id, nodes.title, nodes.tags, nodes.file, files.mtime, nodes.props,
 nodes.todo, nodes.priority, nodes.level, nodes.olp, nodes.pos"
  "Columns read to build a record, in the order `my/index--record' expects.")

(defun my/index--record (row)
  "Return the record plist for database ROW."
  (pcase-let ((`(,id ,title ,tags ,file ,mtime ,props ,todo ,priority ,level ,olp ,pos)
               row))
    (list :id id
          :title (or title "")
          :tags (and tags (car (read-from-string tags)))
          :file file
          :mtime (and mtime (seconds-to-time mtime))
          :props (and props (car (read-from-string props)))
          :todo todo
          :priority priority
          :level (or level 0)
          :olp (and olp (car (read-from-string olp)))
          :pos (or pos 1))))

(defun my/index--data-version (db)
  "Return SQLite's change counter for writes made by other connections."
  (caar (sqlite-select db "PRAGMA data_version")))

(defun my/index-records ()
  "Return every node as a record plist, after refreshing the index.
Callers get their own copies and may modify them."
  (my/index-sync)
  (let* ((db (my/index--open))
         (version (my/index--data-version db)))
    (unless (and my/index--cache (equal (car my/index--cache) version))
      (setq my/index--cache
            (cons version
                  (mapcar #'my/index--record
                          (sqlite-select
                           db (format "SELECT %s FROM nodes LEFT JOIN files
 ON files.path = nodes.file ORDER BY nodes.file, nodes.pos"
                                      my/index--record-columns))))))
    (mapcar #'copy-sequence (cdr my/index--cache))))

(defun my/index-node (id)
  "Return the record of node ID, or nil.  Refreshes the index first."
  (my/index-sync)
  (when-let* ((row (car (sqlite-select
                         (my/index--open)
                         (format "SELECT %s FROM nodes LEFT JOIN files
 ON files.path = nodes.file WHERE nodes.id = ?" my/index--record-columns)
                         (list id)))))
    (my/index--record row)))

(defun my/index-links ()
  "Return every id link between nodes as a list of (SOURCE DEST)."
  (my/index-sync)
  (sqlite-select (my/index--open) "SELECT source, dest FROM links"))

(defun my/index-search (query &optional limit)
  "Return nodes whose title or own text contains QUERY, best match first.
Each element is (ID . SNIPPET).  Matching ignores case and works on
substrings in any script.  LIMIT defaults to 50."
  (my/index-sync)
  (let ((db (my/index--open))
        (query (string-trim query))
        (limit (or limit 50)))
    (cond
     ((string-empty-p query) nil)
     ;; The trigram tokenizer needs three characters; shorter queries and
     ;; an index without FTS5 scan with LIKE instead.
     ((and my/index--fts (>= (length query) 3))
      (mapcar (lambda (row) (cons (car row) (or (cadr row) "")))
              (sqlite-select
               db "SELECT id, snippet(text, -1, '', '', ' ... ', 16) FROM text
 WHERE text MATCH ? ORDER BY bm25(text, 0.0, 0.0, 8.0, 1.0) LIMIT ?"
               (list (concat "\"" (string-replace "\"" "\"\"" query) "\"")
                     limit))))
     (t
      (let ((pattern (concat "%"
                             (replace-regexp-in-string "[\\%_]" "\\\\\\&" query)
                             "%")))
        (mapcar (lambda (row) (cons (car row) ""))
                (sqlite-select
                 db "SELECT id FROM text WHERE title LIKE ? ESCAPE '\\'
 OR body LIKE ? ESCAPE '\\' ORDER BY (title LIKE ? ESCAPE '\\') DESC LIMIT ?"
                 (list pattern pattern pattern limit))))))))

(defun my/index-stats ()
  "Return a plist describing the index: :file :files :nodes :links :fts."
  (my/index-sync)
  (let ((db (my/index--open)))
    (list :file my/index--db-file
          :files (caar (sqlite-select db "SELECT count(*) FROM files"))
          :nodes (caar (sqlite-select db "SELECT count(*) FROM nodes"))
          :links (caar (sqlite-select db "SELECT count(*) FROM links"))
          :fts my/index--fts)))

(provide 'orgseq-index)
;;; orgseq-index.el ends here
