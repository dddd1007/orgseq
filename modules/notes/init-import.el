;;; init-import.el --- Import Notion and Tana exports as Org nodes -*- lexical-binding: t; -*-
;;
;; Notion exports a workspace as "Markdown & CSV": one .md file per page,
;; named "Title <32 hex digits>.md", one "Name <id>_all.csv" per database
;; beside the folder that holds its rows, and uploaded files under
;; attachments/.  Tana exports one JSON file ("Tana Intermediate Format").
;; This module turns either into Org notes:
;;
;;   Identity   Each note records where it came from in NOTION_ID or
;;              TANA_ID, so a second run skips what was imported before
;;              and nothing is overwritten.
;;   Places     Routes send a part of the export to a layer, to the
;;              private zone, or nowhere: (PREFIX . DEST), PREFIX a path
;;              inside the export by titles, DEST "area", "ai/Skills",
;;              "private/x" or "skip".  The longest prefix wins and the
;;              folders below it are kept, so the page tree of the
;;              workspace becomes the folder tree of the library.
;;   Body       Markdown is converted to Org by `my/notion-md-to-org'
;;              (headings, lists, checkboxes, quotes, code, tables,
;;              emphasis, links, images).  No external converter.
;;   Links      A link to another exported page becomes an id link.  A
;;              library note never links into the private zone: the words
;;              stay, the link does not.
;;   Fields     For a database row, the "Name: value" lines under the
;;              title become Org properties.  Only names that are columns
;;              of the database's .csv are read.
;;   Databases  A database becomes a note of its own that shows its rows
;;              through an `orgseq-view' block filtered by folder.
;;   Types      Types are the user's decision and live in types.org; the
;;              import never creates one.  It applies existing types to
;;              the rows of a database or the nodes of a Tana supertag.
;;   Tana       A day becomes a heading in that day's Daily file, a node
;;              with a supertag a note with its fields as properties, a
;;              top-level node a note; everything else is outline text.
;;
;; The export is only read.  A snapshot is taken before the first note is
;; written.
;;
;; Section 1  Profile, routes and destinations
;; Section 2  Reading a Notion export
;; Section 3  Markdown to Org
;; Section 4  Values and names
;; Section 5  Notion: plan and import
;; Section 6  Tana
;; Section 7  Commands

;; Requires: init-org     (library paths)
;; Requires: init-nodes   (node types)
;; Requires: init-views   (orgseq-view blocks of database notes)
;; Requires: init-sync    (my/storage-snapshot)
;; Requires: init-private (my/private-snapshot)
(defvar my/note-home)
(defvar my/inbox-dir)
(defvar my/library-dir)
(defvar my/private-dir)
(defvar my/node-types)

(require 'cl-lib)
(require 'subr-x)
(require 'url-util)
(require 'orgseq-paths)
(require 'orgseq-index)
(require 'orgseq-note)

(declare-function my/node-types--find "init-nodes" (ref types))
(declare-function my/node-type-name "init-nodes" (type) t)
(declare-function my/node-type-tag "init-nodes" (type) t)
(declare-function my/node-type-fields "init-nodes" (type) t)
(declare-function my/node-type-dir "init-nodes" (type))
(declare-function my/storage-snapshot "init-sync" ())
(declare-function my/private-snapshot "init-private" ())
(declare-function org-id-new "org-id" (&optional prefix))
(declare-function org-update-all-dblocks "org" ())

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Profile, routes and destinations
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; A profile is a text file that holds the choices of one migration, so a
;; long import is repeatable:
;;
;;   # comment
;;   route Area/Teaching = area
;;   route Area/Counseling = private/counseling
;;   route Getting Started = skip
;;   route * = inbox/notion
;;   type Course material = CourseDoc
;;   map Last edited = EDITED

(defun my/import-profile-read (file)
  "Read the import profile FILE; return a plist (:routes :types :map).
Each is an alist in file order."
  (let (routes types map)
    (dolist (line (split-string (my/notion--read file) "[\r\n]+" t))
      (let ((line (string-trim line)))
        (cond
         ((or (string-empty-p line) (string-prefix-p "#" line)))
         ((string-match
           "\\`\\(route\\|type\\|map\\)[ \t]+\\(.+?\\)[ \t]*=[ \t]*\\(.+\\)\\'"
           line)
          (let ((pair (cons (string-trim (match-string 2 line))
                            (string-trim (match-string 3 line)))))
            (pcase (match-string 1 line)
              ("route" (push pair routes))
              ("type" (push pair types))
              (_ (push pair map)))))
         (t (user-error "Import profile %s: cannot read line: %s" file line)))))
    (list :routes (nreverse routes) :types (nreverse types)
          :map (nreverse map))))

(defconst my/import--layers
  '("inbox" "project" "area" "resource" "archive" "ai")
  "Layer names a destination may start with.")

(defun my/import--dir-name (name)
  "Return NAME as a folder name that is safe on every platform."
  (let ((clean (string-trim
                (replace-regexp-in-string "[/\\\\:*?\"<>|\n\t]+" "_" name)
                "[ ._]+" "[ ._]+")))
    (if (string-empty-p clean)
        "untitled"
      (truncate-string-to-width clean 80))))

(defun my/import--route (path routes)
  "Return (DEST . REST) for the longest of ROUTES that matches PATH, or nil.
PATH is a list of names: the folders of an item, then its title.  REST
is the folders below the matched prefix."
  (let (best best-length)
    (dolist (route routes)
      (let* ((prefix (if (equal (car route) "*")
                         nil
                       (mapcar #'string-trim
                               (split-string (car route) "/" t))))
             (length (length prefix)))
        (when (and (<= length (length path))
                   (equal prefix (cl-subseq path 0 length))
                   (or (null best-length) (> length best-length)))
          (setq best route
                best-length length))))
    (and best
         (cons (cdr best) (nthcdr best-length (butlast path))))))

(defun my/import--place (dest rest)
  "Return (DIR . PRIVATE) for destination DEST and the folders REST.
DEST is a layer name or \"private\", optionally followed by folders;
\"skip\" returns the symbol `skip'."
  (let* ((parts (split-string dest "/" t "[ \t]+"))
         (head (downcase (or (car parts) ""))))
    (cond
     ((equal head "skip") 'skip)
     ((not (or (equal head "private") (member head my/import--layers)))
      (user-error "Unknown destination %s (%s, private or skip, then folders)"
                  dest (string-join my/import--layers ", ")))
     (t
      (let* ((private (equal head "private"))
             (base (file-name-as-directory
                    (expand-file-name
                     (if private my/private-dir
                       (my/note-layer-dir (intern head))))))
             (below (mapconcat #'my/import--dir-name
                               (append (cdr parts) rest) "/")))
        (cons (file-name-as-directory (expand-file-name below base))
              private))))))

(defun my/import--top (dir private)
  "Return the top-level place DIR belongs to, for reports."
  (if private
      (file-name-as-directory (expand-file-name my/private-dir))
    (let* ((home (file-name-as-directory (expand-file-name my/note-home)))
           (below (file-relative-name dir home)))
      (file-name-as-directory
       (expand-file-name (car (split-string below "/" t)) home)))))

(defconst my/import--notion-url-regexp
  "\\`https?://\\(?:[a-z]+\\.\\)?notion\\.\\(?:so\\|com\\)/.*?\\([0-9a-f]\\{32\\}\\)\\(?:[?#].*\\)?\\'"
  "A web address of a Notion page; group 1 is the page id.")

(defun my/import--org-link (target label)
  "Return an Org link to TARGET described by LABEL."
  (let ((label (replace-regexp-in-string "[][]" "" (or label ""))))
    (if (string-empty-p label)
        (format "[[%s]]" target)
      (format "[[%s][%s]]" target label))))

(defun my/import--new-id (taken)
  "Return a new Org id that is neither indexed nor in the hash table TAKEN."
  (require 'org-id)
  (let ((id (org-id-new)))
    (while (or (gethash id taken) (my/index-node id))
      (setq id (format "%s-%04x" (org-id-new) (random 65536))))
    (puthash id t taken)
    id))

(defun my/import--target-file (title dir taken)
  "Return a free file name for a note titled TITLE in DIR.
TAKEN is a hash table of names given out earlier in the same run."
  (let* ((base (expand-file-name (my/note-slug title) dir))
         (file (concat base ".org"))
         (n 1))
    (while (or (gethash file taken) (file-exists-p file))
      (setq file (format "%s-%d.org" base (cl-incf n))))
    (puthash file t taken)
    file))

(defun my/import--private-org-files ()
  "Return the Org files in the private zone."
  (let ((dir (expand-file-name my/private-dir)))
    (and (file-directory-p dir)
         (directory-files-recursively dir "\\.org\\'"))))

(defun my/import--known (property)
  "Return a hash table of the items imported before under PROPERTY.
PROPERTY is NOTION_ID or TANA_ID.  The value is the Org id of the node
in the library, or (file . FILE) for a note in the private zone."
  (let ((known (make-hash-table :test #'equal))
        (line (format "^:%s:[ \t]+\\(.+\\)$" (regexp-quote property))))
    (dolist (record (my/index-records))
      (when-let* ((key (cdr (assoc property (plist-get record :props))))
                  ((not (string-empty-p key))))
        (puthash key (plist-get record :id) known)))
    (dolist (file (my/import--private-org-files))
      (with-temp-buffer
        (insert-file-contents file nil 0 4096)
        (when (re-search-forward line nil t)
          (puthash (string-trim (match-string 1)) (cons 'file file) known))))
    known))

(defun my/import--types (types)
  "Return TYPES, an alist of (NAME . TYPE-NAME), with the types looked up."
  (mapcar (lambda (pair)
            (cons (car pair) (my/notion--find-type (cdr pair))))
          types))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Reading a Notion export
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/notion--split-name (name)
  "Split an export file or folder NAME into (TITLE . ID).
NAME has no extension.  ID is the 32 hex digit page id at its end, or
nil when the name carries none."
  (if (string-match "\\`\\(.*?\\)[ _-]*\\([0-9a-f]\\{32\\}\\)\\(?:_all\\)?\\'" name)
      (cons (string-trim (match-string 1 name)) (match-string 2 name))
    (cons (string-trim (string-remove-suffix "_all" name)) nil)))

(defun my/notion--read (file)
  "Return the text of FILE, read as UTF-8 without a byte order mark."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (goto-char (point-min))
    (when (eq (char-after) #xfeff) (delete-char 1))
    (buffer-string)))

(defun my/notion--csv-row (line)
  "Split one CSV LINE into its fields."
  (let ((pos 0)
        (len (length line))
        fields)
    (while (<= pos len)
      (if (and (< pos len) (eq (aref line pos) ?\"))
          (let ((start (1+ pos))
                (text "")
                done)
            (setq pos start)
            (while (not done)
              (let ((quote (string-search "\"" line pos)))
                (cond
                 ((null quote)
                  (setq text (concat text (substring line start))
                        pos len done t))
                 ((and (< (1+ quote) len) (eq (aref line (1+ quote)) ?\"))
                  (setq text (concat text (substring line start quote) "\"")
                        start (+ quote 2) pos (+ quote 2)))
                 (t
                  (setq text (concat text (substring line start quote))
                        pos (1+ quote) done t)))))
            (push text fields)
            (let ((comma (string-search "," line pos)))
              (setq pos (if comma (1+ comma) (1+ len)))))
        (let ((comma (string-search "," line pos)))
          (push (substring line pos (or comma len)) fields)
          (setq pos (if comma (1+ comma) (1+ len))))))
    (nreverse fields)))

(defun my/notion--csv-columns (csv)
  "Return the column names of the database file CSV."
  (let ((text (my/notion--read csv)))
    (mapcar #'string-trim
            (my/notion--csv-row
             (car (split-string text "[\r\n]+" t))))))

(defun my/notion--folder-title (name)
  "Split an export folder NAME into (TITLE . HINT).
Notion shortens the id of a folder whose title is not unique to its
first and last four digits (\"Memories 4108-63d6\"); HINT is then
\(FIRST . LAST), else nil."
  (let ((name (car (my/notion--split-name name))))
    (if (string-match "\\`\\(.+?\\) \\([0-9a-f]\\{4\\}\\)-\\([0-9a-f]\\{4\\}\\)\\'"
                      name)
        (cons (string-trim (match-string 1 name))
              (cons (match-string 2 name) (match-string 3 name)))
      (cons name nil))))

(defun my/notion--csv-count (csv)
  "Return the number of records in the database file CSV."
  (with-temp-buffer
    (insert (my/notion--read csv))
    (goto-char (point-min))
    (let ((count 0)
          (quoted nil))
      ;; A record ends at a line end outside a quoted field.
      (while (not (eobp))
        (let ((line (buffer-substring (point) (line-end-position)))
              (start 0))
          (while (string-match "\"" line start)
            (setq quoted (not quoted)
                  start (match-end 0)))
          (unless (or quoted (string-empty-p (string-trim line)))
            (cl-incf count)))
        (forward-line 1))
      (max 0 (1- count)))))

(defun my/notion--scan-databases (root)
  "Return the databases of the export ROOT, one plist per .csv file.
Keys: :csv, :name, :id, :titles (the names in the file name; a database
inside a page is called \"Page <id>_Database <id>_all.csv\"), :columns
and :dir.  Files without a page id are attachments, not databases."
  (let (databases)
    (dolist (csv (directory-files-recursively root "\\.csv\\'"))
      (let ((base (string-remove-suffix "_all" (file-name-base csv)))
            (start 0)
            parts)
        (while (string-match "\\(.*?\\)[ _-]*\\([0-9a-f]\\{32\\}\\)\\(?:_\\|\\'\\)"
                             base start)
          (push (cons (string-trim (match-string 1 base))
                      (match-string 2 base))
                parts)
          (setq start (match-end 0)))
        (when (and parts (= start (length base)))
          (push (list :csv csv
                      :name (car (car parts))
                      :id (cdr (car parts))
                      :titles (mapcar #'car parts)
                      :columns (my/notion--csv-columns csv)
                      :dir (file-name-directory csv))
                databases))))
    (nreverse databases)))

(defun my/notion--databases-of (folder databases cache)
  "Return the DATABASES whose rows the export FOLDER holds.
CACHE is a hash table of folders already looked up."
  (let ((cached (gethash folder cache 'none)))
    (if (not (eq cached 'none))
        cached
      (let* ((parent (file-name-directory folder))
             (name (my/notion--folder-title (file-name-nondirectory folder)))
             (beside (cl-remove-if-not
                      (lambda (database)
                        (equal (plist-get database :dir) parent))
                      databases))
             (exact (cl-remove-if-not
                     (lambda (database)
                       (equal (plist-get database :name) (car name)))
                     beside))
             (found (or exact
                        (cl-remove-if-not
                         (lambda (database)
                           (member (car name) (plist-get database :titles)))
                         beside)))
             (hinted (and (cdr name)
                          (cl-remove-if-not
                           (lambda (database)
                             (let ((id (plist-get database :id)))
                               (and (string-prefix-p (cadr name) id)
                                    (string-suffix-p (cddr name) id))))
                           found))))
        (puthash folder (or hinted found) cache)))))

(defun my/notion--database (file databases cache)
  "Return the database the page FILE is a row of, or nil.
When the folder of FILE holds the rows of several DATABASES, the one
whose columns name the most property lines of the page wins."
  (let ((found (my/notion--databases-of
                (directory-file-name (file-name-directory file))
                databases cache)))
    (if (null (cdr found))
        (car found)
      (let* ((columns (delete-dups
                       (cl-mapcan (lambda (database)
                                    (copy-sequence (plist-get database :columns)))
                                  found)))
             (names (mapcar #'car (plist-get (my/notion--parse-page file columns)
                                             :props)))
             best best-score)
        (dolist (database found)
          (let ((score (cl-count-if
                        (lambda (name)
                          (member name (plist-get database :columns)))
                        names)))
            (when (or (null best-score) (> score best-score))
              (setq best database
                    best-score score))))
        best))))

(defun my/notion--path (file root)
  "Return the folder titles between ROOT and the export file FILE."
  (mapcar (lambda (name) (car (my/notion--folder-title name)))
          (split-string (or (file-name-directory (file-relative-name file root))
                            "")
                        "/" t)))

(defun my/notion--root (dir)
  "Return the folder that holds the pages of the extracted export DIR.
An archive unpacks into one \"Export-...\" folder; that folder is the
root when DIR holds nothing else."
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (entries (and (file-directory-p dir)
                       (directory-files dir t
                                        directory-files-no-dot-files-regexp))))
    (if (and (= (length entries) 1)
             (file-directory-p (car entries))
             (string-prefix-p "Export-" (file-name-nondirectory (car entries))))
        (file-name-as-directory (car entries))
      dir)))

(defun my/notion--strip-view-lines (text)
  "Return the page TEXT without the settings of embedded database views.
An export writes \"sort:\" and \"filters:\" and the lines that belong to
them after the link of an embedded view."
  (let (out skipping)
    (dolist (line (split-string text "\n"))
      (cond
       ((string-match-p "\\`\\(?:sort\\|filters\\):[ \t]*\\'" line)
        (setq skipping t))
       ((and skipping (not (string-empty-p (string-trim line)))
             (not (string-match-p "\\`[ \t]*[#[!>|-]" line))))
       (t (setq skipping nil)
          (push line out))))
    (string-join (nreverse out) "\n")))

(defun my/notion--parse-page (file columns)
  "Read the exported page FILE; return (:title :props :body).
COLUMNS are the property names of its database, nil for an ordinary
page.  PROPS is an alist of (NAME . VALUE) in file order; BODY is the
Markdown after them."
  (let* ((lines (split-string (my/notion--read file) "\r?\n"))
         (title (car (my/notion--split-name (file-name-base file))))
         props)
    (while (and lines (string-empty-p (string-trim (car lines))))
      (pop lines))
    (when (and lines (string-match "\\`# +\\(.*?\\)[ \t]*\\'" (car lines)))
      (setq title (match-string 1 (car lines)))
      (pop lines))
    (when columns
      (while (and lines (string-empty-p (string-trim (car lines))))
        (pop lines))
      (while (and lines
                  (string-match "\\`\\([^:\n]+\\): \\(.*\\)\\'" (car lines))
                  (member (match-string 1 (car lines)) columns))
        (push (cons (match-string 1 (car lines))
                    (string-trim (match-string 2 (car lines))))
              props)
        (pop lines)))
    (while (and lines (string-empty-p (string-trim (car lines))))
      (pop lines))
    (list :title (if (string-empty-p title) "Untitled" title)
          :props (nreverse props)
          :body (string-join lines "\n"))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Markdown to Org
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; The subset Notion writes.  Links and images are handed to a function
;; (KIND LABEL TARGET) so the importer can turn page links into id links
;; and copy attachments; KIND is `link' or `image'.

(defalias 'my/notion--org-link #'my/import--org-link)

(defun my/notion--default-link (kind label target)
  "Return LABEL and TARGET as a plain Org link; KIND `image' has no label."
  (my/notion--org-link target (and (not (eq kind 'image)) label)))

(defconst my/notion--inline-regexp
  (concat "\\(`[^`\n]+`\\)"
          "\\|\\(!\\)?\\[\\([^]\n]*\\)\\](\\(\\(?:[^()\n]\\|([^()\n]*)\\)+\\))"
          "\\|\\*\\*\\(.+?\\)\\*\\*"
          "\\|~~\\(.+?\\)~~"
          "\\|\\*\\([^* \t\n][^*\n]*\\)\\*")
  "Inline Markdown: 1 code, 2 image mark, 3 link text, 4 link target,
5 bold, 6 strike-through, 7 italic.")

(defun my/notion--inline (text link-fn)
  "Convert the inline Markdown in TEXT to Org; LINK-FN renders links."
  (let ((start 0)
        parts)
    (while (string-match my/notion--inline-regexp text start)
      (let ((begin (match-beginning 0))
            (end (match-end 0))
            (code (match-string 1 text))
            (image (match-beginning 2))
            (label (match-string 3 text))
            (target (match-string 4 text))
            (bold (match-string 5 text))
            (strike (match-string 6 text))
            (italic (match-string 7 text)))
        (push (substring text start begin) parts)
        (push (cond
               (code (format "~%s~" (substring code 1 -1)))
               (target (funcall link-fn (if image 'image 'link)
                                (or label "") (string-trim target)))
               (bold (format "*%s*" (my/notion--inline bold link-fn)))
               (strike (format "+%s+" (my/notion--inline strike link-fn)))
               (t (format "/%s/" (my/notion--inline italic link-fn))))
              parts)
        (setq start end)))
    (push (substring text start) parts)
    (apply #'concat (nreverse parts))))

(defun my/notion--line (line link-fn &optional shift)
  "Convert one Markdown LINE outside a code block to Org.
SHIFT is the number of levels headings move up."
  (cond
   ((string-match "\\`\\(#\\{1,6\\}\\) +\\(.*?\\)[ \t#]*\\'" line)
    (let ((stars (make-string (max 1 (- (length (match-string 1 line))
                                        (or shift 0)))
                              ?*))
          (text (match-string 2 line)))
      (concat stars " " (my/notion--inline text link-fn))))
   ((string-match-p "\\`[ \t]*\\(?:-\\{3,\\}\\|\\*\\{3,\\}\\|_\\{3,\\}\\)[ \t]*\\'" line)
    "-----")
   ((string-match-p "\\`[ \t]*<aside>[ \t]*\\'" line) "#+begin_quote")
   ((string-match-p "\\`[ \t]*</aside>[ \t]*\\'" line) "#+end_quote")
   ((and (string-match-p "\\`[ \t]*|[ \t:|-]+\\'" line)
         (string-match-p "-" line))
    "|-")
   ((string-match "\\`\\([ \t]*\\)[-*+] \\(?:\\[\\([ xX]\\)\\] \\)?\\(.*\\)\\'" line)
    (let ((indent (match-string 1 line))
          (box (match-string 2 line))
          (text (match-string 3 line)))
      (concat indent "- "
              (cond ((null box) "")
                    ((equal box " ") "[ ] ")
                    (t "[X] "))
              (my/notion--inline text link-fn))))
   ((string-match "\\`\\([ \t]*[0-9]+\\)[.)] \\(.*\\)\\'" line)
    (let ((number (match-string 1 line))
          (text (match-string 2 line)))
      (concat number ". " (my/notion--inline text link-fn))))
   (t (my/notion--inline line link-fn))))

(defun my/notion-md-to-org (text &optional link-fn)
  "Return the Markdown TEXT of a Notion page as Org text.
LINK-FN is called with (KIND LABEL TARGET) for each link and image and
returns the Org text for it; the default writes a plain Org link."
  (let* ((link-fn (or link-fn #'my/notion--default-link))
         (lines (split-string text "\r?\n"))
         ;; Notion pages often start their headings at level two; the
         ;; shallowest heading of the page becomes a top-level heading.
         (shift (let ((inside nil) (least nil))
                  (dolist (line lines)
                    (cond
                     ((string-match-p "\\`[ \t]*```" line)
                      (setq inside (not inside)))
                     ((and (not inside)
                           (string-match "\\`\\(#\\{1,6\\}\\) " line))
                      (setq least (min (or least 6)
                                       (length (match-string 1 line)))))))
                  (if least (1- least) 0)))
         fence quote out)
    (dolist (line lines)
      (cond
       (fence
        (if (string-match-p "\\`[ \t]*```[ \t]*\\'" line)
            (progn (push (concat (car fence) (cdr fence)) out)
                   (setq fence nil))
          ;; A line that Org would read as a heading or a keyword is
          ;; protected with a comma, as Org does itself.
          (push (if (string-match "\\`\\([ \t]*\\)\\(\\*\\|#\\+\\)" line)
                    (concat (match-string 1 line) ","
                            (substring line (match-end 1)))
                  line)
                out)))
       ((string-match "\\`\\([ \t]*\\)```[ \t]*\\([^ \t`]*\\)[ \t]*\\'" line)
        (let ((indent (match-string 1 line))
              (language (match-string 2 line)))
          (when quote
            (push "#+end_quote" out)
            (setq quote nil))
          (if (string-empty-p language)
              (progn (push (concat indent "#+begin_example") out)
                     (setq fence (cons indent "#+end_example")))
            (push (concat indent "#+begin_src " (downcase language)) out)
            (setq fence (cons indent "#+end_src")))))
       (t
        (let ((quoted (and (string-match "\\`> ?\\(.*\\)\\'" line)
                           (match-string 1 line))))
          (when (and quote (not quoted))
            (push "#+end_quote" out)
            (setq quote nil))
          (when (and quoted (not quote))
            (push "#+begin_quote" out)
            (setq quote t))
          (push (my/notion--line (or quoted line) link-fn shift) out)))))
    (when fence (push (concat (car fence) (cdr fence)) out))
    (when quote (push "#+end_quote" out))
    (string-join (nreverse out) "\n")))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Values and names
;; ═══════════════════════════════════════════════════════════════════════════

(defconst my/notion--months
  '("january" "february" "march" "april" "may" "june" "july" "august"
    "september" "october" "november" "december")
  "English month names, as Notion writes dates in an English workspace.")

(defun my/notion--iso (year month day &optional hour minute)
  "Return YEAR MONTH DAY (and HOUR MINUTE) as YYYY-MM-DD[ HH:MM]."
  (concat (format "%04d-%02d-%02d" year month day)
          (if hour (format " %02d:%02d" hour (or minute 0)) "")))

(defun my/notion--date (value)
  "Return the Notion date VALUE as YYYY-MM-DD[ HH:MM], or nil.
Reads \"November 5, 2026\", \"November 5, 2026 3:30 PM\", 2026/11/05,
2026-11-05 and the Chinese year-month-day form."
  (let ((case-fold-search t)
        (number (lambda (n) (string-to-number (match-string n value)))))
    (cond
     ((string-match
       (concat "\\`\\([[:alpha:]]+\\) \\([0-9]\\{1,2\\}\\), \\([0-9]\\{4\\}\\)"
               "\\(?: \\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\(?: ?\\([AP]\\)M\\)?\\)?"
               "\\(?: ([^)]*)\\)?\\'")
       value)
      (let ((month (cl-position (downcase (match-string 1 value))
                                my/notion--months :test #'equal))
            (half (match-string 6 value)))
        (when month
          (my/notion--iso
           (funcall number 3) (1+ month) (funcall number 2)
           (and (match-string 4 value)
                (let ((hour (funcall number 4)))
                  (cond ((null half) hour)
                        ((string-equal-ignore-case half "P")
                         (if (< hour 12) (+ hour 12) hour))
                        ((= hour 12) 0)
                        (t hour))))
           (and (match-string 5 value) (funcall number 5))))))
     ((or (string-match
           (concat "\\`\\([0-9]\\{4\\}\\)[/-]\\([0-9]\\{1,2\\}\\)[/-]\\([0-9]\\{1,2\\}\\)"
                   "\\(?: \\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\)?\\'")
           value)
          (string-match
           (concat "\\`\\([0-9]\\{4\\}\\)\u5e74\\([0-9]\\{1,2\\}\\)\u6708\\([0-9]\\{1,2\\}\\)\u65e5"
                   "\\(?: \\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\)?\\'")
           value))
      (my/notion--iso (funcall number 1) (funcall number 2) (funcall number 3)
                      (and (match-string 4 value) (funcall number 4))
                      (and (match-string 5 value) (funcall number 5)))))))

(defun my/notion--value (value link-fn &optional here)
  "Return the exported property VALUE as an Org property value.
Checkbox values become yes/no, dates and date ranges ISO dates, and
\"Title (target)\" references go through LINK-FN when the target is a
page, a web address or a file that exists below the folder HERE."
  (let ((value (string-trim value)))
    (cond
     ((member value '("Yes" "No")) (downcase value))
     ((my/notion--date value))
     ((let ((ends (split-string value " \u2192 ")))
        (and (= (length ends) 2)
             (my/notion--date (car ends))
             (my/notion--date (cadr ends))
             (concat (my/notion--date (car ends)) "--"
                     (my/notion--date (cadr ends))))))
     ((string-match-p "(.+)" value)
      (let ((start 0)
            parts)
        ;; One reference may have commas in its title; several are
        ;; separated by "), ".
        (while (string-match
                (if (string-search "), " value)
                    "\\([^,(]+?\\) (\\([^()\n]+\\))\\(?:, \\)?"
                  "\\(.+?\\) (\\([^()\n]+\\))\\'")
                value start)
          (let* ((begin (match-beginning 0))
                 (end (match-end 0))
                 (raw-label (match-string 1 value))
                 (raw-target (match-string 2 value))
                 (label (string-trim raw-label))
                 (target (string-trim raw-target))
                 (reference
                  (or (string-match-p "\\`https?://" target)
                      (string-match-p "\\.\\(?:md\\|csv\\)\\'" target)
                      (and here
                           (not (string-match-p "[ \t]" target))
                           (file-regular-p
                            (expand-file-name
                             (decode-coding-string (url-unhex-string target)
                                                   'utf-8)
                             here))))))
            (push (substring value start begin) parts)
            (push (if reference
                      (concat (funcall link-fn 'link label target) " ")
                    (substring value begin end))
                  parts)
            (setq start end)))
        (push (substring value start) parts)
        (string-trim (apply #'concat (nreverse parts)))))
     (t value))))

(defconst my/notion--reserved-names
  '("ID" "ITEM" "TODO" "TAGS" "ALLTAGS" "CATEGORY" "PRIORITY" "FILE"
    "DEADLINE" "SCHEDULED" "CLOSED" "TIMESTAMP" "TIMESTAMP_IA" "BLOCKED"
    "NOTION_ID" "TANA_ID")
  "Property names Org or the import itself gives a meaning to.")

(defun my/notion--property-name (name map)
  "Return the Org property name for the Notion property NAME.
MAP is an alist of (NOTION-NAME . FIELD) chosen by the user.  Without
an entry the name is upcased and runs of spaces and colons become _."
  (let ((mapped (cdr (cl-assoc name map :test #'string-equal-ignore-case))))
    (if (and mapped (not (string-empty-p mapped)))
        (upcase mapped)
      (let ((plain (upcase (string-trim
                            (replace-regexp-in-string "[[:space:]:]+" "_" name)
                            "_+" "_+"))))
        (cond ((string-empty-p plain) "NOTION_PROPERTY")
              ((member plain my/notion--reserved-names)
               (concat "NOTION_" plain))
              (t plain))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Notion: plan and import
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/notion--page-key (file root)
  "Return the NOTION_ID value for the exported page FILE under ROOT.
The page id from the file name; a page exported without one is known by
its path inside the export."
  (or (cdr (my/notion--split-name (file-name-base file)))
      (concat "path:" (file-name-sans-extension (file-relative-name file root)))))

(defun my/notion--target-dir (type-def layer folder private)
  "Return the directory imported notes are written to without a route.
PRIVATE selects the private zone, LAYER a library layer by name; else
the layer of TYPE-DEF, else the resource layer.  FOLDER is a directory
inside it (default \"notion\" unless a type decides the place)."
  (let* ((layer (and layer (not (string-empty-p layer)) (downcase layer)))
         (base (cond
                (private my/private-dir)
                (layer
                 (unless (member layer my/import--layers)
                   (user-error "Unknown layer %s (%s)" layer
                               (string-join my/import--layers ", ")))
                 (my/note-layer-dir (intern layer)))
                ((and type-def (my/node-type-dir type-def)))
                (t my/library-dir)))
         (folder (cond ((and folder (not (string-empty-p folder))) folder)
                       ((or private (not type-def)) "notion")))
         (base (file-name-as-directory (expand-file-name base)))
         (dir (file-name-as-directory
               (if folder (expand-file-name folder base) base))))
    (unless (string-prefix-p base dir)
      (user-error "Folder %s leaves %s" folder (abbreviate-file-name base)))
    dir))

(defun my/notion--find-type (name)
  "Return the node type called NAME, or signal a user error."
  (or (my/node-types--find name my/node-types)
      (user-error "Unknown type: %s (types are defined in types.org)" name)))

(cl-defun my/notion-import-plan (dir &key type types layer folder private map
                                     routes lenient)
  "Describe what importing the Notion export DIR would do; change nothing.
TYPE names an existing node type applied to every page.  TYPES is an
alist of (DATABASE . TYPE-NAME) giving the rows of the databases with
that name their own type; a name no database has is an error unless
LENIENT is non-nil (a profile shared with another source names things
this export does not have).  ROUTES is an alist of (PREFIX . DEST), see
`my/import--route'; a page no route matches goes where LAYER, FOLDER
and PRIVATE say (see `my/notion--target-dir').  MAP is an alist of
\(NOTION-PROPERTY . FIELD) renames.

Return a plist: :source, :target (where pages without a route or a
database type go), :targets (the top-level places written to), :pages
\(a list of plists :file :key :title :props :body :database :db :type
:dir :private :status, STATUS being `new', `exists' or `skip'), :new,
:new-private, :existing and :left-out (counts) and :databases (a list
of plists :name :pages :type :properties :unmapped)."
  (let* ((root (my/notion--root dir))
         (_ (unless (file-directory-p root)
              (user-error "Not a folder: %s (extract the Notion export first)"
                          root)))
         (type-def (and type (not (string-empty-p type))
                        (my/notion--find-type type)))
         (database-types (my/import--types types))
         (target (my/notion--target-dir type-def layer folder private))
         (dirs (make-hash-table :test #'eq))
         (known (my/import--known "NOTION_ID"))
         (cache (make-hash-table :test #'equal))
         (found (my/notion--scan-databases root))
         (by-id (make-hash-table :test #'equal))
         (counts (make-hash-table :test #'equal))
         (uploads (expand-file-name "attachments/" root))
         (place
          (lambda (path own)
            (let* ((route (my/import--route path routes))
                   (place (and route
                               (my/import--place (car route) (cdr route)))))
              (cond
               ((eq place 'skip) 'skip)
               (place place)
               (own (cons (or (gethash own dirs)
                              (puthash own
                                       (my/notion--target-dir own layer folder
                                                              private)
                                       dirs))
                          (and private t)))
               (t (cons target (and private t)))))))
         pages names)
    (dolist (database found)
      (puthash (plist-get database :id) database by-id))
    (dolist (file (sort (directory-files-recursively root "\\.md\\'") #'string<))
      ;; Markdown files under attachments/ are uploads, not pages.
      (unless (string-prefix-p uploads file)
        (let* ((database (my/notion--database file found cache))
               (name (plist-get database :name))
               (page (my/notion--parse-page file (plist-get database :columns)))
               (key (my/notion--page-key file root))
               (own (cdr (assoc name database-types)))
               (where (funcall place
                               (append (my/notion--path file root)
                                       (list (plist-get page :title)))
                               own)))
          (when (and database (not (eq where 'skip)))
            (unless (gethash name counts) (push name names))
            (cl-incf (gethash name counts 0)))
          (push (append (list :file file :key key
                              :database name :db database
                              :columns (plist-get database :columns)
                              :type (or own type-def)
                              :dir (car-safe where)
                              :private (cdr-safe where)
                              :home (gethash key by-id)
                              :status (cond ((eq where 'skip) 'skip)
                                            ((gethash key known) 'exists)
                                            (t 'new)))
                        page)
                pages))))
    ;; A database without a page of its own gets one, so links to it have a
    ;; target and its rows have a table.
    (dolist (database found)
      (let ((id (plist-get database :id)))
        (when (and (cl-some (lambda (page)
                              (and (eq (plist-get page :db) database)
                                   (not (eq (plist-get page :status) 'skip))))
                            pages)
                   (not (cl-find id pages :test #'equal
                                 :key (lambda (page) (plist-get page :key)))))
          (let ((where (funcall place
                                (append (my/notion--path (plist-get database :csv)
                                                         root)
                                        (list (plist-get database :name)))
                                nil)))
            (push (list :file (plist-get database :csv) :key id
                        :home database
                        :dir (car-safe where) :private (cdr-safe where)
                        :status (cond ((eq where 'skip) 'skip)
                                      ((gethash id known) 'exists)
                                      (t 'new))
                        :title (plist-get database :name) :props nil :body "")
                  pages)))))
    (setq pages (nreverse pages))
    (dolist (pair (and (not lenient) types))
      (unless (cl-find (car pair) found :test #'equal
                       :key (lambda (database) (plist-get database :name)))
        (user-error "The export has no database named %s (it has: %s)"
                    (car pair)
                    (if found
                        (string-join
                         (delete-dups
                          (mapcar (lambda (database) (plist-get database :name))
                                  found))
                         ", ")
                      "none"))))
    (let ((new (cl-remove-if-not
                (lambda (page) (eq (plist-get page :status) 'new)) pages)))
      (list :source root
            :target target
            :targets (delete-dups
                      (mapcar (lambda (page)
                                (my/import--top (plist-get page :dir)
                                                (plist-get page :private)))
                              new))
            :private (and private t)
            :map map
            :pages pages
            :new (length new)
            :new-private (cl-count-if (lambda (page) (plist-get page :private))
                                      new)
            :existing (cl-count 'exists pages
                                :key (lambda (p) (plist-get p :status)))
            :left-out (cl-count 'skip pages
                                :key (lambda (p) (plist-get p :status)))
            :databases
            (mapcar
             (lambda (name)
               (let* ((columns (plist-get
                                (cl-find name pages
                                         :key (lambda (p) (plist-get p :database))
                                         :test #'equal)
                                :columns))
                      ;; The first column is the title, which is the note title.
                      (properties (cdr columns))
                      (row-type (or (cdr (assoc name database-types)) type-def))
                      (fields (and row-type
                                   (mapcar (lambda (field) (plist-get field :name))
                                           (my/node-type-fields row-type)))))
                 (list :name name
                       :pages (gethash name counts)
                       :type (and row-type (my/node-type-name row-type))
                       :properties properties
                       :unmapped
                       (and row-type
                            (cl-remove-if
                             (lambda (property)
                               (member (my/notion--property-name property map)
                                       fields))
                             properties)))))
             (nreverse names))))))

(defun my/notion--copy-asset (source page stats)
  "Copy the attachment SOURCE of PAGE beside its note; return the new file.
Nothing is overwritten.  STATS is the list of running counters."
  (let* ((folder (expand-file-name
                  (concat "assets/"
                          (my/note-slug (file-name-base (plist-get page :target))))
                  (file-name-directory (plist-get page :target))))
         (target (expand-file-name (file-name-nondirectory source) folder)))
    (unless (file-exists-p target)
      (if (plist-get page :private)
          (with-file-modes #o700 (make-directory folder t))
        (make-directory folder t))
      (with-file-modes (if (plist-get page :private) #o600 (default-file-modes))
        (copy-file source target nil t))
      (cl-incf (nth 0 stats)))
    target))

(defun my/notion--link-fn (page by-file by-key known stats)
  "Return the link renderer for PAGE.
BY-FILE and BY-KEY map the exported files and the page ids of this run
to their page plists; KNOWN is the table of `my/import--known'.  Notes
in the private zone have no index, so links between them are file
links; a library note gets no link into the zone, only the words.
STATS is a list of counters (ASSETS UNRESOLVED WITHHELD)."
  (let ((here (file-name-directory (plist-get page :file)))
        (note-dir (file-name-directory (plist-get page :target)))
        (private (plist-get page :private)))
    (cl-labels
        ((to-page (other label)
           (setq label (if (member label '("" "Untitled"))
                           (plist-get other :title)
                         label))
           (cond
            ;; A database page links to its own table.
            ((eq other page) "")
            ((not (plist-get other :private))
             (my/import--org-link (concat "id:" (plist-get other :id)) label))
            (private
             (my/import--org-link
              (concat "file:" (file-relative-name (plist-get other :target)
                                                  note-dir))
              label))
            (t (cl-incf (nth 2 stats)) label)))
         (to-known (seen label)
           (cond
            ((stringp seen) (my/import--org-link (concat "id:" seen) label))
            (private
             (my/import--org-link
              (concat "file:" (file-relative-name (cdr seen) note-dir)) label))
            (t (cl-incf (nth 2 stats)) label)))
         (by-id (id label)
           (let ((other (gethash id by-key))
                 (seen (gethash id known)))
             (cond (other (to-page other label))
                   (seen (to-known seen label))))))
      (lambda (kind label target)
        (cond
         ((string-match-p "\\`about:" target) label)
         ((string-match my/import--notion-url-regexp target)
          (or (by-id (match-string 1 target) label)
              (my/import--org-link target label)))
         ((string-match-p "\\`\\(?:[a-zA-Z][a-zA-Z0-9+.-]*:\\|#\\)" target)
          (my/import--org-link target (and (not (eq kind 'image)) label)))
         (t
          (let* ((path (decode-coding-string (url-unhex-string target) 'utf-8))
                 (file (expand-file-name path here))
                 (other (gethash file by-file))
                 (id (cdr (my/notion--split-name (file-name-base file)))))
            (cond
             (other (to-page other label))
             ((and id (by-id id label)))
             ((and (string-match-p "\\.\\(?:md\\|csv\\)\\'" file)
                   (or id (not (file-regular-p file))))
              ;; A page that is not part of the export: keep the words.
              (cl-incf (nth 1 stats))
              label)
             ((file-regular-p file)
              (my/import--org-link
               (concat "file:" (file-relative-name
                                (my/notion--copy-asset file page stats)
                                note-dir))
               (and (not (eq kind 'image)) label)))
             (t label)))))))))

(defun my/notion--database-body (page pages map)
  "Return the Org text that shows the rows of the database of PAGE.
PAGES are the pages of this run.  In the library this is an
`orgseq-view' block over the folder of the rows; the private zone has
no index, so there it is a list of file links."
  (let* ((database (plist-get page :home))
         (rows (cl-remove-if-not
                (lambda (other) (eq (plist-get other :db) database))
                pages))
         (dir (and rows (plist-get (car rows) :dir)))
         (type-def (and rows (plist-get (car rows) :type))))
    (cond
     ((null rows) "")
     ((plist-get page :private)
      (mapconcat
       (lambda (row)
         (concat "- "
                 (my/import--org-link
                  (concat "file:"
                          (file-relative-name
                           (plist-get row :target)
                           (file-name-directory (plist-get page :target))))
                  (plist-get row :title))))
       rows "\n"))
     ;; Rows of several databases in one folder cannot be told apart by
     ;; folder, and rows sent to the private zone are not indexed.
     ((or (plist-get (car rows) :private)
          (cl-some (lambda (other)
                     (and (plist-get other :db)
                          (not (eq (plist-get other :db) database))
                          (equal (plist-get other :dir) dir)))
                   pages))
      "")
     (t
      (format "#+BEGIN: orgseq-view%s :filter (folder %S) :columns %S :layout table\n#+END:"
              (if type-def (format " :type %S" (my/node-type-tag type-def)) "")
              (directory-file-name
               (file-relative-name dir (expand-file-name my/note-home)))
              (mapcar (lambda (name) (my/notion--property-name name map))
                      (seq-take (cdr (plist-get database :columns)) 6)))))))

(defun my/import--refresh-blocks (files)
  "Fill the dynamic blocks of the note FILES; errors are reported, not raised."
  (dolist (file files)
    (condition-case err
        (with-current-buffer (find-file-noselect file)
          (let ((inhibit-message t))
            (org-update-all-dblocks)
            (save-buffer))
          (kill-buffer))
      (error (message "org-seq: could not fill the table in %s: %s"
                      (abbreviate-file-name file) (error-message-string err))))))

(cl-defun my/notion-import (dir &key type types layer folder private map routes
                                lenient)
  "Import the pages of the Notion export DIR that are not imported yet.
The arguments are those of `my/notion-import-plan'.  A snapshot of the
library, and a copy of the private zone when notes go there, is taken
first.  Return a plist: :created, :private (how many of them went to
the private zone), :skipped, :left-out, :assets, :unresolved (links to
pages outside the export, kept as plain text), :withheld (links from
the library into the private zone, kept as plain text), :snapshot,
:target and :targets."
  (let* ((plan (my/notion-import-plan dir :type type :types types
                                      :layer layer :folder folder
                                      :private private :map map
                                      :routes routes :lenient lenient))
         (pages (cl-remove-if-not
                 (lambda (page) (eq (plist-get page :status) 'new))
                 (plist-get plan :pages)))
         (known (my/import--known "NOTION_ID"))
         (by-file (make-hash-table :test #'equal))
         (by-key (make-hash-table :test #'equal))
         (ids (make-hash-table :test #'equal))
         (files (make-hash-table :test #'equal))
         (stats (list 0 0 0))
         (to-private (cl-count-if (lambda (page) (plist-get page :private))
                                  pages))
         (snapshot (and (< to-private (length pages)) (my/storage-snapshot)))
         (private-copy (and (> to-private 0) (my/private-snapshot)))
         (created 0)
         tables)
    ;; Every page gets its id and file name before any body is converted,
    ;; so links between pages of the same run resolve in one pass.
    (setq pages
          (mapcar (lambda (page)
                    (let ((page (append
                                 (list :id (my/import--new-id ids)
                                       :target (my/import--target-file
                                                (plist-get page :title)
                                                (plist-get page :dir) files))
                                 page)))
                      (puthash (plist-get page :file) page by-file)
                      (puthash (plist-get page :key) page by-key)
                      ;; Links to a database name its .csv file.
                      (when-let* ((database (plist-get page :home)))
                        (puthash (plist-get database :csv) page by-file))
                      page))
                  pages))
    (dolist (page pages)
      (let* ((link-fn (my/notion--link-fn page by-file by-key known stats))
             (here (file-name-directory (plist-get page :file)))
             (type-def (plist-get page :type))
             (fields (and type-def
                          (mapcar (lambda (field) (plist-get field :name))
                                  (my/node-type-fields type-def))))
             (tags (and type-def (list (my/node-type-tag type-def))))
             (props (mapcar
                     (lambda (prop)
                       (cons (my/notion--property-name (car prop) map)
                             (my/notion--value (cdr prop) link-fn here)))
                     (plist-get page :props)))
             (missing (cl-remove-if (lambda (name) (assoc name props)) fields))
             (body (my/notion-md-to-org
                    (my/notion--strip-view-lines (plist-get page :body))
                    link-fn))
             (table (if (plist-get page :home)
                        (my/notion--database-body page pages map)
                      "")))
        (my/note-create
         :title (plist-get page :title)
         :file (plist-get page :target)
         :id (plist-get page :id)
         :private (plist-get page :private)
         :tags tags
         :props (append (list (cons "NOTION_ID" (plist-get page :key)))
                        props
                        (mapcar (lambda (name) (cons name "")) missing))
         :body (string-trim
                (concat body (if (string-empty-p table) "" "\n\n") table)))
        (when (string-prefix-p "#+BEGIN:" table)
          (push (plist-get page :target) tables))
        (cl-incf created)))
    (my/import--refresh-blocks (nreverse tables))
    (list :created created
          :private to-private
          :skipped (plist-get plan :existing)
          :left-out (plist-get plan :left-out)
          :assets (nth 0 stats)
          :unresolved (nth 1 stats)
          :withheld (nth 2 stats)
          :snapshot (or snapshot private-copy)
          :target (plist-get plan :target)
          :targets (plist-get plan :targets))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: Tana
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; A Tana export is one JSON file, a tree of nodes.  Three kinds of node
;; become an item of their own:
;;
;;   daily   a day of the journal that has content: a "Tana" heading
;;           appended to that day's Daily file
;;   tagged  a node with a supertag: a note; its fields are properties
;;   page    a top-level node of the workspace or the library: a note
;;
;; Every other node is a list item in the body of the item above it.
;; Route paths are tag/SUPERTAG/TITLE and page/TITLE; without a route a
;; note goes to tana/ in the Inbox (tana/SUPERTAG/ when it has one).  An
;; item below a private or left-out item shares its fate.

(defun my/tana--read (file)
  "Return the contents of the Tana export FILE as nested alists."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (goto-char (point-min))
    (let ((data (condition-case nil
                    (json-parse-buffer :object-type 'alist :array-type 'list
                                       :null-object nil :false-object nil)
                  (error (user-error "Not a Tana JSON export: %s" file)))))
      (or (alist-get 'contents data)
          (user-error "Not a Tana JSON export: %s" file)))))

(defun my/tana--register (node nodes)
  "Record NODE and everything below it in the hash table NODES by id.
A full node wins over a reference to it."
  (when (and (consp node) (consp (car node)))
    (when-let* ((id (alist-get 'id node)))
      (let ((seen (gethash id nodes)))
        (when (or (null seen)
                  (and (alist-get 'isRef seen) (not (alist-get 'isRef node))))
          (puthash id node nodes))))
    (dolist (key '(children values content replies))
      (dolist (child (alist-get key node))
        (my/tana--register child nodes)))
    (dolist (pair (alist-get 'inlineNodes node))
      (my/tana--register (cdr pair) nodes))))

(defun my/tana--date (value)
  "Return the Tana date VALUE as YYYY-MM-DD[ HH:MM], a range with --."
  (mapconcat
   (lambda (part)
     (if (string-match
          "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\(?:T\\([0-9]\\{2\\}:[0-9]\\{2\\}\\)\\)?"
          part)
         (concat (match-string 1 part)
                 (if (match-string 2 part)
                     (concat " " (match-string 2 part))
                   ""))
       part))
   ;; A time carries its zone as "[Asia/Shanghai]".
   (split-string (replace-regexp-in-string "\\[[^]]*\\]" "" value) "/" t)
   "--"))

(defun my/tana--plain (node nodes &optional depth)
  "Return the name of NODE as plain text; NODES resolves references."
  (let ((depth (or depth 0)))
    (string-trim
     (mapconcat
      (lambda (part)
        (pcase (alist-get 'type part)
          ("text" (or (alist-get 'text part) ""))
          ("link" (or (alist-get 'text part) (alist-get 'url part) ""))
          ("date" (my/tana--date (or (alist-get 'date part) "")))
          ("node" (let ((other (gethash (alist-get 'nodeId part) nodes)))
                    (if (and other (< depth 3))
                        (my/tana--plain other nodes (1+ depth))
                      "")))
          (_ "")))
      (alist-get 'nameParts node) ""))))

(defun my/tana--tag-names (node nodes)
  "Return the supertag names of NODE."
  (delq nil
        (mapcar (lambda (tag)
                  (let ((name (my/tana--plain
                               (if (stringp tag) (gethash tag nodes) tag)
                               nodes)))
                    (and (not (string-empty-p name)) name)))
                (alist-get 'tags node))))

(defun my/tana--org-tag (name)
  "Return the supertag NAME as an Org tag."
  (string-trim (replace-regexp-in-string "[^[:alnum:]_@#%]+" "_" name)
               "_+" "_+"))

(defun my/tana--place (kind title tags parent state)
  "Return (DIR . PRIVATE) or `skip' for an item of KIND.
TITLE and TAGS describe it, PARENT is the item above it and STATE the
plist of the run."
  (let ((routes (plist-get state :routes)))
    (cond
     ((and parent (eq (plist-get parent :status) 'skip)) 'skip)
     ((and parent (plist-get parent :private))
      (cons (plist-get parent :dir) t))
     ((eq kind 'daily) (cons (my/daily-dir) nil))
     ((eq kind 'page)
      (let ((route (my/import--route (list "page" title) routes)))
        (if route
            (my/import--place (car route) (cdr route))
          (my/import--place "inbox/tana" nil))))
     (t
      (let (places)
        (dolist (tag tags)
          (when-let* ((route (my/import--route (list "tag" tag title) routes)))
            (push (my/import--place (car route) (cdr route)) places)))
        (setq places (nreverse places))
        (or (cl-find-if (lambda (place) (cdr-safe place)) places)
            (car places)
            ;; Tana is a staging area: what no route places waits in
            ;; the Inbox, whatever layer its type has.
            (my/import--place "inbox/tana" (list (car tags)))))))))

(defun my/tana--collect (node top parent state)
  "Find the items in NODE and below; add them to STATE.
TOP is non-nil for a top-level node, PARENT is the item above."
  (when (and (consp node) (consp (car node)))
    (let* ((units (plist-get state :units))
           (nodes (plist-get state :nodes))
           (type (alist-get 'type node))
           (id (alist-get 'id node))
           (children (alist-get 'children node))
           (title (my/tana--plain node nodes))
           (tags (and (equal type "node") (my/tana--tag-names node nodes)))
           (kind
            (cond
             ((or (alist-get 'isRef node) (null id) (gethash id units)) nil)
             ((and (equal type "journalPart")
                   (equal (alist-get 'granularity node) "day")
                   children)
              'daily)
             ((and tags (or children (not (string-empty-p title)))) 'tagged)
             ((and top (equal type "node") children
                   (not (string-empty-p title))
                   (not (cl-every (lambda (child)
                                    (equal (alist-get 'type child) "journalPart"))
                                  children)))
              'page)))
           (unit
            (and kind
                 (let* ((title (cond ((eq kind 'daily) (alist-get 'date node))
                                     ((string-empty-p title) "Untitled")
                                     (t title)))
                        (place (my/tana--place kind title tags parent state))
                        (types (and (eq kind 'tagged)
                                    (delq nil
                                          (mapcar (lambda (tag)
                                                    (cdr (assoc tag (plist-get
                                                                     state :types))))
                                                  tags))))
                        (seen (gethash id (plist-get state :known))))
                   (list :node node :key id :kind kind :title title
                         :tags tags :types types
                         :dir (car-safe place) :private (cdr-safe place)
                         :status (cond ((eq place 'skip) 'skip)
                                       (seen 'exists)
                                       (t 'new)))))))
      (when unit
        (puthash id unit units)
        (plist-put state :order (cons id (plist-get state :order))))
      (unless (alist-get 'isRef node)
        (dolist (child children)
          (my/tana--collect child nil (or unit parent) state))
        (dolist (value (alist-get 'values node))
          (my/tana--collect value nil (or unit parent) state))))))

(cl-defun my/tana-import-plan (file &key types map routes)
  "Describe what importing the Tana export FILE would do; change nothing.
TYPES is an alist of (SUPERTAG . TYPE-NAME); a supertag without an
entry gets the type of the same name when there is one.  ROUTES is an
alist of (PREFIX . DEST) over the paths tag/SUPERTAG/TITLE and
page/TITLE.  MAP is an alist of (TANA-FIELD . FIELD) renames.

Return a plist: :source, :state (for `my/tana-import'), :units (a list
of plists :key :kind :title :tags :types :dir :private :status), :new,
:new-private, :existing, :left-out, :daily and :tags (a list of plists
:name :count :type)."
  (let* ((file (expand-file-name file))
         (_ (unless (file-regular-p file)
              (user-error "Not a file: %s" file)))
         (contents (my/tana--read file))
         (nodes (make-hash-table :test #'equal))
         (given (my/import--types types))
         (state (list :order nil
                      :nodes nodes
                      :units (make-hash-table :test #'equal)
                      :known (my/import--known "TANA_ID")
                      :notion (my/import--known "NOTION_ID")
                      :withheld 0
                      ;; "*" is the default of a Notion export in a
                      ;; shared profile; Tana has its own default.
                      :routes (cl-remove "*" routes :key #'car :test #'equal)
                      :map map
                      :types nil))
         (counts (make-hash-table :test #'equal))
         names)
    (dolist (part '(workspace library schema inbox))
      (my/tana--register (alist-get part contents) nodes))
    ;; Every supertag in use: its given type, else the type of that name.
    (maphash
     (lambda (_id node)
       (dolist (tag (my/tana--tag-names node nodes))
         (unless (assoc tag (plist-get state :types))
           (plist-put state :types
                      (cons (cons tag (or (cdr (assoc tag given))
                                          (my/node-types--find tag my/node-types)))
                            (plist-get state :types))))))
     nodes)
    (dolist (part '(workspace library))
      (dolist (child (alist-get 'children (alist-get part contents)))
        (my/tana--collect child t nil state)))
    (plist-put state :order (nreverse (plist-get state :order)))
    (let* ((units (mapcar (lambda (id) (gethash id (plist-get state :units)))
                          (plist-get state :order)))
           (new (cl-remove-if-not
                 (lambda (unit) (eq (plist-get unit :status) 'new)) units)))
      (dolist (unit units)
        (unless (eq (plist-get unit :status) 'skip)
          (dolist (tag (plist-get unit :tags))
            (unless (gethash tag counts) (push tag names))
            (cl-incf (gethash tag counts 0)))))
      (list :source file
            :state state
            :units units
            :new (length new)
            :new-private (cl-count-if (lambda (unit) (plist-get unit :private))
                                      new)
            :existing (cl-count 'exists units
                                :key (lambda (unit) (plist-get unit :status)))
            :left-out (cl-count 'skip units
                                :key (lambda (unit) (plist-get unit :status)))
            :daily (cl-count 'daily new
                             :key (lambda (unit) (plist-get unit :kind)))
            :targets (delete-dups
                      (mapcar (lambda (unit)
                                (my/import--top (plist-get unit :dir)
                                                (plist-get unit :private)))
                              new))
            :tags (mapcar
                   (lambda (name)
                     (let ((type (cdr (assoc name (plist-get state :types)))))
                       (list :name name
                             :count (gethash name counts)
                             :type (and type (my/node-type-name type)))))
                   (sort names #'string<))))))

(defun my/tana--ref (id label unit state)
  "Return Org text that points from UNIT to the Tana node ID.
LABEL is used when the node is not an item of its own.  A library note
gets no link into the private zone and does not show the title."
  (let* ((other (gethash id (plist-get state :units)))
         (seen (gethash id (plist-get state :known)))
         (private (plist-get unit :private))
         (title (or (and other (plist-get other :title)) label))
         (here (file-name-directory (plist-get unit :target)))
         (withheld (lambda ()
                     (plist-put state :withheld
                                (1+ (or (plist-get state :withheld) 0)))
                     "(private note)")))
    (cond
     ((and other (plist-get other :target))
      (cond
       ((not (plist-get other :private))
        (my/import--org-link (concat "id:" (plist-get other :id)) title))
       (private
        (my/import--org-link
         (concat "file:" (file-relative-name (plist-get other :target) here))
         title))
       (t (funcall withheld))))
     ((stringp seen) (my/import--org-link (concat "id:" seen) title))
     ((consp seen)
      (if private
          (my/import--org-link
           (concat "file:" (file-relative-name (cdr seen) here)) title)
        (funcall withheld)))
     ((and other (plist-get other :private) (not private))
      (funcall withheld))
     (t label))))

(defun my/tana--url (url label unit state)
  "Return Org text for the web address URL described by LABEL in UNIT.
The address of a Notion page that was imported becomes a link to that
note."
  (let ((seen (and (string-match my/import--notion-url-regexp url)
                   (gethash (match-string 1 url)
                            (plist-get state :notion)))))
    (cond
     ((stringp seen)
      (my/import--org-link (concat "id:" seen)
                           (if (member label (list nil "" url))
                               "Notion page"
                             label)))
     ((and (consp seen) (plist-get unit :private))
      (my/import--org-link
       (concat "file:"
               (file-relative-name (cdr seen)
                                   (file-name-directory
                                    (plist-get unit :target))))
       (if (member label (list nil "" url)) "Notion page" label)))
     ((consp seen)
      (plist-put state :withheld (1+ (or (plist-get state :withheld) 0)))
      "(private note)")
     (t (my/import--org-link url (and (not (equal label url)) label))))))

(defun my/tana--text (node unit state)
  "Return the name of NODE as Org text inside UNIT."
  (let ((nodes (plist-get state :nodes)))
    (string-trim
     (mapconcat
      (lambda (part)
        (pcase (alist-get 'type part)
          ("text"
           (let* ((text (replace-regexp-in-string
                         "[\r\n]+" " " (or (alist-get 'text part) "")))
                  (formats (alist-get 'formats part))
                  (inner (string-trim text)))
             (cond
              ((string-match-p my/import--notion-url-regexp inner)
               (my/tana--url inner nil unit state))
              ((or (null formats) (string-empty-p inner)) text)
              (t
               (let ((mark (cond ((member "code" formats) "~")
                                 ((member "bold" formats) "*")
                                 ((member "italic" formats) "/")
                                 ((member "striked" formats) "+")
                                 (t ""))))
                 (concat (if (string-match-p "\\`[ \t]" text) " " "")
                         mark inner mark
                         (if (string-match-p "[ \t]\\'" text) " " "")))))))
          ("link" (my/tana--url (or (alist-get 'url part) "")
                                (alist-get 'text part) unit state))
          ("date" (my/tana--date (or (alist-get 'date part) "")))
          ("node"
           (let* ((id (alist-get 'nodeId part))
                  (other (gethash id nodes)))
             (my/tana--ref id (if other (my/tana--plain other nodes) "")
                           unit state)))
          (_ "")))
      (alist-get 'nameParts node) ""))))

(defun my/tana--item-p (node state)
  "Return non-nil when NODE is an item of its own or a reference."
  (or (alist-get 'isRef node)
      (when-let* ((id (alist-get 'id node))
                  (unit (gethash id (plist-get state :units))))
        (eq (plist-get unit :node) node))))

(defun my/tana--item-text (node unit state)
  "Return the Org text of the list item for NODE inside UNIT."
  (let ((type (alist-get 'type node)))
    (cond
     ((equal type "checkbox") (if (alist-get 'checked node) "yes" "no"))
     ((my/tana--item-p node state)
      (my/tana--ref (alist-get 'id node)
                    (my/tana--plain node (plist-get state :nodes))
                    unit state))
     ((equal type "url")
      (let ((text (my/tana--text node unit state)))
        (if (string-empty-p text) (or (alist-get 'url node) "") text)))
     (t
      (let ((text (my/tana--text node unit state))
            (description (alist-get 'description node)))
        (if (and (stringp description) (not (string-empty-p description)))
            (concat text " -- "
                    (replace-regexp-in-string "[\r\n]+" " " description))
          text))))))

(defun my/tana--field-name (field state)
  "Return the name of the field node FIELD."
  (let ((definition (alist-get 'field field)))
    (my/tana--plain (if (stringp definition)
                        (gethash definition (plist-get state :nodes))
                      definition)
                    (plist-get state :nodes))))

(defun my/tana--outline (children depth unit state)
  "Return the Org list lines for the Tana nodes CHILDREN at DEPTH in UNIT."
  (let ((indent (make-string (* 2 depth) ?\s))
        lines)
    (dolist (child children)
      (when (and (consp child) (consp (car child)))
        (pcase (alist-get 'type child)
          ("field"
           (let* ((values (alist-get 'values child))
                  (texts (cl-remove-if
                          #'string-empty-p
                          (mapcar (lambda (value)
                                    (my/tana--item-text value unit state))
                                  values)))
                  (below (cl-mapcan
                          (lambda (value)
                            (and (not (my/tana--item-p value state))
                                 (my/tana--outline (alist-get 'children value)
                                                   (1+ depth) unit state)))
                          values)))
             (when (or texts below)
               (push (format "%s- %s :: %s" indent
                             (my/tana--field-name child state)
                             (string-join texts ", "))
                     lines)
               (setq lines (append (reverse below) lines)))))
          ("search"
           (push (format "%s- (Tana search) %s" indent
                         (my/tana--plain child (plist-get state :nodes)))
                 lines))
          ("chat"
           (push (format "%s- (Tana AI chat)" indent) lines)
           (setq lines
                 (append (reverse
                          (my/tana--outline
                           (append (alist-get 'content child)
                                   (alist-get 'replies child))
                           (1+ depth) unit state))
                         lines)))
          (_
           (let ((text (my/tana--item-text child unit state))
                 (below (and (not (my/tana--item-p child state))
                             (my/tana--outline (alist-get 'children child)
                                               (1+ depth) unit state))))
             (when (or below (not (string-empty-p text)))
               (push (concat indent "- "
                             (cond ((not (assq 'isDone child)) "")
                                   ((alist-get 'isDone child) "[X] ")
                                   (t "[ ] "))
                             (if (string-empty-p text) "(untitled)" text))
                     lines)
               (setq lines (append (reverse below) lines))))))))
    (nreverse lines)))

(defun my/tana--unit-parts (unit state)
  "Return (PROPS . BODY) for UNIT: its fields and its outline."
  (let* ((node (plist-get unit :node))
         (map (plist-get state :map))
         props rest)
    (dolist (child (alist-get 'children node))
      (if (and (equal (alist-get 'type child) "field")
               (not (cl-some (lambda (value)
                               (and (not (my/tana--item-p value state))
                                    (alist-get 'children value)))
                             (alist-get 'values child))))
          (let ((name (my/notion--property-name
                       (my/tana--field-name child state) map))
                (text (string-join
                       (cl-remove-if
                        #'string-empty-p
                        (mapcar (lambda (value)
                                  (my/tana--item-text value unit state))
                                (alist-get 'values child)))
                       ", ")))
            (unless (string-empty-p text)
              (if-let* ((cell (assoc name props)))
                  (setcdr cell (concat (cdr cell) ", " text))
                (push (cons name text) props))))
        (push child rest)))
    (cons (nreverse props)
          (string-join (my/tana--outline (nreverse rest) 0 unit state) "\n"))))

(defun my/tana--write-daily (unit state)
  "Append the content of the day UNIT to its Daily file."
  (let* ((date (plist-get unit :title))
         (parts (my/tana--unit-parts unit state))
         (coding-system-for-write 'utf-8-unix)
         (file (plist-get unit :target)))
    (unless (string-match
             "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'" date)
      (user-error "Tana day without a date: %s" date))
    (my/daily-ensure-file
     (encode-time (list 0 0 12
                        (string-to-number (match-string 3 date))
                        (string-to-number (match-string 2 date))
                        (string-to-number (match-string 1 date))
                        nil -1 nil)))
    (write-region
     (concat "\n* Tana\n:PROPERTIES:\n"
             (format ":ID:       %s\n" (plist-get unit :id))
             (format ":TANA_ID:  %s\n" (plist-get unit :key))
             (mapconcat (lambda (prop) (format ":%s: %s\n" (car prop) (cdr prop)))
                        (car parts) "")
             ":END:\n"
             (cdr parts) "\n")
     nil file 'append 'silent)
    (my/index-update-file file)))

(defun my/tana--write-note (unit state)
  "Write the note for the tagged or page UNIT."
  (let* ((node (plist-get unit :node))
         (parts (my/tana--unit-parts unit state))
         (types (plist-get unit :types))
         (all-types (plist-get state :types))
         (tags (delete-dups
                (cl-remove-if
                 #'string-empty-p
                 (mapcar (lambda (tag)
                           (let ((type (cdr (assoc tag all-types))))
                             (if type
                                 (my/node-type-tag type)
                               (my/tana--org-tag tag))))
                         (plist-get unit :tags)))))
         (props (car parts))
         (missing (cl-remove-if
                   (lambda (name) (assoc name props))
                   (delete-dups
                    (cl-mapcan (lambda (type)
                                 (mapcar (lambda (field) (plist-get field :name))
                                         (my/node-type-fields type)))
                               types))))
         (description (alist-get 'description node)))
    (my/note-create
     :title (plist-get unit :title)
     :file (plist-get unit :target)
     :id (plist-get unit :id)
     :private (plist-get unit :private)
     :tags tags
     :props (append (list (cons "TANA_ID" (plist-get unit :key)))
                    props
                    (and (assq 'isDone node)
                         (list (cons "TANA_DONE"
                                     (if (alist-get 'isDone node) "yes" "no"))))
                    (mapcar (lambda (name) (cons name "")) missing))
     :body (string-trim
            (concat (if (and (stringp description)
                             (not (string-empty-p description)))
                        (concat (replace-regexp-in-string "[\r\n]+" " "
                                                          description)
                                "\n\n")
                      "")
                    (cdr parts))))))

(cl-defun my/tana-import (file &key types map routes)
  "Import the items of the Tana export FILE that are not imported yet.
The arguments are those of `my/tana-import-plan'.  A snapshot of the
library, and a copy of the private zone when notes go there, is taken
first.  Return a plist: :created (notes), :daily (days added to Daily
files), :private, :skipped, :left-out, :withheld (references from the
library into the private zone, replaced by a placeholder), :snapshot
and :targets."
  (let* ((plan (my/tana-import-plan file :types types :map map :routes routes))
         (state (plist-get plan :state))
         (units (plist-get state :units))
         (new (cl-remove-if-not
               (lambda (unit) (eq (plist-get unit :status) 'new))
               (plist-get plan :units)))
         (to-private (plist-get plan :new-private))
         (snapshot (and (< to-private (length new)) (my/storage-snapshot)))
         (private-copy (and (> to-private 0) (my/private-snapshot)))
         (ids (make-hash-table :test #'equal))
         (files (make-hash-table :test #'equal))
         (created 0)
         (daily 0))
    ;; Ids and file names first, so references resolve in one pass.
    (setq new
          (mapcar
           (lambda (unit)
             (let ((unit (append
                          (list :id (my/import--new-id ids)
                                :target
                                (if (eq (plist-get unit :kind) 'daily)
                                    (expand-file-name
                                     (concat (plist-get unit :title) ".org")
                                     (plist-get unit :dir))
                                  (my/import--target-file
                                   (plist-get unit :title)
                                   (plist-get unit :dir) files)))
                          unit)))
               (puthash (plist-get unit :key) unit units)
               unit))
           new))
    (dolist (unit new)
      (if (eq (plist-get unit :kind) 'daily)
          (progn (my/tana--write-daily unit state)
                 (cl-incf daily))
        (my/tana--write-note unit state)
        (cl-incf created)))
    (list :created created
          :daily daily
          :private to-private
          :skipped (plist-get plan :existing)
          :left-out (plist-get plan :left-out)
          :withheld (or (plist-get state :withheld) 0)
          :snapshot (or snapshot private-copy)
          :targets (plist-get plan :targets))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 7: Commands
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/import--read-profile ()
  "Ask for an import profile; return its plist, or nil for none."
  (let ((file (read-file-name "Import profile (empty: none): " nil "" nil "")))
    (and (not (string-empty-p file))
         (file-regular-p file)
         (my/import-profile-read file))))

(defun my/notion-import-folder (dir &optional type private profile)
  "Import the extracted Notion export in DIR after showing what it holds.
TYPE is the name of a node type for every page, PRIVATE sends the notes
to the private zone.  PROFILE is the plist of an import profile (routes,
database types, renames); `orgseq import-notion' takes the same file."
  (interactive
   (let* ((dir (read-directory-name "Extracted Notion export: " nil nil t))
          (profile (my/import--read-profile))
          (private (and (not profile)
                        (equal (completing-read
                                "Import into: " '("library" "private zone") nil t)
                               "private zone")))
          (type (if profile
                    ""
                  (completing-read
                   "Type for every page (empty: none): "
                   (mapcar #'my/node-type-name my/node-types) nil t))))
     (list dir (and (not (string-empty-p type)) type) private profile)))
  (let* ((options (list :type type :private private :lenient (and profile t)
                        :types (plist-get profile :types)
                        :map (plist-get profile :map)
                        :routes (plist-get profile :routes)))
         (plan (apply #'my/notion-import-plan dir options)))
    (cond
     ((zerop (plist-get plan :new))
      (message "org-seq: nothing to import; %d pages were imported before"
               (plist-get plan :existing)))
     ((y-or-n-p (format "Import %d pages (%d into the private zone; %d imported before)? "
                        (plist-get plan :new) (plist-get plan :new-private)
                        (plist-get plan :existing)))
      (let ((result (apply #'my/notion-import dir options)))
        (message "org-seq: imported %d pages, %d attachments; %d links point outside the export"
                 (plist-get result :created) (plist-get result :assets)
                 (plist-get result :unresolved))
        result)))))

(defun my/tana-import-file (file &optional profile)
  "Import the Tana JSON export FILE after showing what it holds.
PROFILE is the plist of an import profile."
  (interactive
   (list (read-file-name "Tana JSON export: " nil nil t)
         (my/import--read-profile)))
  (let* ((options (list :types (plist-get profile :types)
                        :map (plist-get profile :map)
                        :routes (plist-get profile :routes)))
         (plan (apply #'my/tana-import-plan file options)))
    (cond
     ((zerop (plist-get plan :new))
      (message "org-seq: nothing to import; %d items were imported before"
               (plist-get plan :existing)))
     ((y-or-n-p (format "Import %d items (%d days, %d into the private zone; %d imported before)? "
                        (plist-get plan :new) (plist-get plan :daily)
                        (plist-get plan :new-private) (plist-get plan :existing)))
      (let ((result (apply #'my/tana-import file options)))
        (message "org-seq: imported %d notes and %d days from Tana"
                 (plist-get result :created) (plist-get result :daily))
        result)))))

(provide 'init-import)
;;; init-import.el ends here
