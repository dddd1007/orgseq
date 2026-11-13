;;; test-init-capture.el --- Tests for capture, Daily, node find and id links -*- lexical-binding: t; -*-
;;
;; Everything here runs without org-roam: the last test checks that none
;; of it loaded org-roam.

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar my/node-types)
(defvar my/types-file)
(defvar my/capture-templates-file)
(defvar my/user-capture-templates)
(defvar my/capture--user-loaded)
(defvar org-id-locations-file)
(defvar org-id-track-globally)

(let ((dir (file-name-directory load-file-name)))
  (dolist (sub '("../kernel" "../core" "../modules/notes"))
    (add-to-list 'load-path (expand-file-name sub dir)))
  (load-file (expand-file-name "../kernel/orgseq-paths.el" dir))
  (load-file (expand-file-name "../kernel/orgseq-index.el" dir))
  (load-file (expand-file-name "../kernel/orgseq-note.el" dir))
  (load-file (expand-file-name "../modules/notes/init-capture.el" dir))
  (load-file (expand-file-name "../modules/notes/init-nodes.el" dir))
  (load-file (expand-file-name "../core/orgseq-cli.el" dir)))

(defun my/test-capture--write (file text)
  "Write TEXT to FILE, creating parent directories."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file file (insert text))))

(defun my/test-capture--contents (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro my/test-capture--with-library (&rest body)
  "Run BODY with a temporary library, index and template files; binds `root'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "org-seq-capture-" t)))
          (my/note-home (expand-file-name "notes/" root))
          (my/inbox-dir (expand-file-name "00_Inbox/" my/note-home))
          (my/library-dir (expand-file-name "30_Library/" my/note-home))
          (my/archives-dir (expand-file-name "40_Archives/" my/note-home))
          (my/orgseq-dir (expand-file-name ".orgseq/" my/note-home))
          (my/types-file (expand-file-name "types.org" my/orgseq-dir))
          (my/capture-templates-file (expand-file-name "capture-templates.el"
                                                       my/orgseq-dir))
          (my/index-file (expand-file-name "index.db" root))
          (my/index-sync-interval 0)
          (org-id-locations-file (expand-file-name "org-id-locations" root))
          (org-id-track-globally nil)
          (my/node-types nil)
          (my/user-capture-templates nil)
          (my/capture--user-loaded t)
          (my/capture--warned (make-hash-table :test 'equal))
          (inhibit-message t))
     (unwind-protect
         (progn (make-directory my/inbox-dir t) ,@body)
       (dolist (buffer (buffer-list))
         (let ((file (buffer-file-name buffer)))
           (when (and file (string-prefix-p root file))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer))))
       (my/index-close)
       (delete-directory root t))))

(defconst my/test-capture--types
  "* Reading
:PROPERTIES:
:TYPE_TAG:    reading
:TYPE_KEY:    r
:TYPE_FIELDS: AUTHORS YEAR STATUS
:END:
** Summary
%?
** Key points
")

;; ---- Template expansion ----

(ert-deftest my/note-template-expand-title-slug-time-and-cursor ()
  (let* ((system-time-locale "C")
         (time (encode-time 5 4 3 2 1 2026))
         (result (my/note-template-expand
                  "<%<%Y%m%d>-${slug}> ${title} 100%% %?end %U"
                  "Working Memory" time)))
    (should (equal (car result)
                   "<20260102-working_memory> Working Memory 100% end [2026-01-02 Fri 03:04]"))
    (should (= (cdr result) (string-match "end" (car result))))
    (should-not (cdr (my/note-template-expand "no mark" "T")))))

(ert-deftest my/note-template-expand-rejects-what-it-cannot-expand ()
  (should-error (my/note-template-expand "${author}" "T")
                :type 'my/note-template-unsupported)
  (should-error (my/note-template-expand "%^{Prompt}" "T")
                :type 'my/note-template-unsupported)
  (should-error (my/note-template-expand "%a" "T")
                :type 'my/note-template-unsupported)
  ;; A percent sign before a space or digit is plain text.
  (should (equal (car (my/note-template-expand "50% done" "T")) "50% done")))

(ert-deftest my/note-template-parse-accepts-the-common-shapes ()
  (should-not (my/note-template-parse '("t" "Typed note")))
  (let ((parts (my/note-template-parse
                '("m" "Meeting" plain "%?"
                  :target (file+head "meet/${slug}.org" "#+title: ${title}\n")
                  :unnarrowed t))))
    (should (equal (plist-get parts :path) "meet/${slug}.org"))
    (should (equal (plist-get parts :head) "#+title: ${title}\n")))
  (should (equal (plist-get (my/note-template-parse
                             '("f" "File" plain "x" :target (file "f/${slug}.org")))
                            :path)
                 "f/${slug}.org"))
  ;; No :target means the default target.
  (should (plist-get (my/note-template-parse '("n" "No target" plain "%?")) :head))
  (dolist (bad '(("e" "Entry" entry "* %?" :target (file+head "x.org" "h"))
                 ("o" "Olp" plain "%?" :target (file+head+olp "x.org" "h" ("A")))
                 ("b" "Body file" plain (file "tpl.org") :target (file "x.org"))
                 "not a list"))
    (should-error (my/note-template-parse bad) :type 'my/note-template-unsupported)))

(ert-deftest my/capture-usable-templates-skip-unsupported-with-one-warning ()
  (my/test-capture--with-library
    (let ((warnings nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type message &rest _) (push message warnings))))
        (let ((templates '(("t" "Group")
                           ("a" "Good" plain "%?" :target (file "a/${slug}.org"))
                           ("x" "Datetree" plain "%?"
                            :target (file+datetree "x.org")))))
          (should (equal (mapcar #'car (my/capture-usable-templates templates)) '("a")))
          (my/capture-usable-templates templates)))
      (should (= (length warnings) 1))
      (should (string-match-p "\"x Datetree\" skipped" (car warnings))))))

;; ---- Creating notes ----

(ert-deftest my/note-capture-writes-the-note-from-a-roam-template ()
  (my/test-capture--with-library
    (let* ((template '("m" "Meeting" plain "* Notes\n%?\n* Decisions\n"
                       :target (file+head "meetings/%<%Y>-${slug}.org"
                                          "#+title: ${title}\n#+filetags: :meeting:\n")))
           (note (my/note-capture "Kick-off call" template nil t))
           (file (plist-get note :file))
           (text (my/test-capture--contents file)))
      (should (equal file (expand-file-name
                           (format-time-string "meetings/%Y-kick_off_call.org")
                           my/inbox-dir)))
      (should (string-prefix-p (format ":PROPERTIES:\n:ID:       %s\n:END:\n"
                                       (plist-get note :id))
                               text))
      (should (string-match-p "^#\\+title: Kick-off call$" text))
      (should (string-match-p "^#\\+filetags: :meeting:$" text))
      (should-not (string-match-p "%\\?" text))
      ;; The cursor lands where %? was: right after "* Notes\n".
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (plist-get note :cursor))
        (should (looking-at-p "\n\\* Decisions")))
      ;; The new note is in the index at once, and a second capture with
      ;; the same title never overwrites the first.
      (should (equal (plist-get (my/index-node (plist-get note :id)) :title)
                     "Kick-off call"))
      (let ((again (my/note-capture "Kick-off call" template nil t)))
        (should-not (equal (plist-get again :file) file))
        (should-not (equal (plist-get again :id) (plist-get note :id)))))))

(ert-deftest my/note-capture-visits-the-note-at-the-cursor-mark ()
  (my/test-capture--with-library
    (let ((note (my/note-capture "Visit me"
                                 '("d" "Default" plain "Before %?after"
                                   :target (file+head "capture/${slug}.org"
                                                      "#+title: ${title}\n")))))
      (should (equal (buffer-file-name) (plist-get note :file)))
      (should (looking-at-p "after")))))

(ert-deftest my/note-capture-reads-the-user-template-file ()
  (my/test-capture--with-library
    (my/test-capture--write
     my/capture-templates-file
     ";;; -*- lexical-binding: t; -*-\n(setq my/user-capture-templates
  '((\"u\" \"User\" plain \"%?\"
     :target (file+head \"user/${slug}.org\" \"#+title: ${title}\\n\"))
    (\"z\" \"Prompting\" plain \"%^{Who}\"
     :target (file+head \"z/${slug}.org\" \"#+title: ${title}\\n\"))))\n")
    (let ((warnings nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type message &rest _) (push message warnings))))
        (my/reload-capture-templates)
        (should (equal (mapcar #'car (my/capture-usable-templates)) '("d" "u"))))
      (should (= (length warnings) 1))
      (should (string-match-p "\"z Prompting\"" (car warnings))))))

(ert-deftest my/node-capture-creates-typed-note-with-fields ()
  (my/test-capture--with-library
    (my/test-capture--write my/types-file my/test-capture--types)
    (my/node-types-reload)
    (let* ((note (my/node-capture (car my/node-types) "Baddeley 2000"
                                  '(("STATUS" . "queued") ("TOPIC" . "memory"))))
           (text (my/test-capture--contents (plist-get note :file))))
      (should (string-match-p "^:AUTHORS: $" text))
      (should (string-match-p "^:STATUS: queued$" text))
      (should (string-match-p "^:TOPIC: memory$" text))
      (should (string-match-p "^#\\+filetags: :reading:$" text))
      (should (string-match-p "^\\* Summary$" text))
      (should (looking-at-p "\n\\* Key points"))
      (let ((record (my/index-node (plist-get note :id))))
        (should (member "reading" (plist-get record :tags)))
        (should (equal (cdr (assoc "STATUS" (plist-get record :props))) "queued"))))))

(ert-deftest my/api-create-and-capture-share-the-file-layout ()
  (my/test-capture--with-library
    (my/test-capture--write my/types-file my/test-capture--types)
    (let* ((created (my/api-create "From CLI" "reading" '(("YEAR" . "2001"))))
           (file (expand-file-name (alist-get 'file created) my/note-home))
           (text (my/test-capture--contents file)))
      (should (string-match-p (format "\\`:PROPERTIES:\n:ID:       %s\n:AUTHORS: \n:YEAR: 2001\n:STATUS: \n:END:\n#\\+title: From CLI\n#\\+filetags: :reading:\n\n\\* Summary"
                                      (regexp-quote (alist-get 'id created)))
                              text))
      (should (string-prefix-p (expand-file-name "capture/" my/inbox-dir) file)))))

(ert-deftest my/node-capture-region-replaces-the-region-with-a-link ()
  (my/test-capture--with-library
    (let ((source (expand-file-name "source.org" my/inbox-dir)))
      (my/test-capture--write source ":PROPERTIES:\n:ID:       src-1\n:END:\n#+title: Source\n\nKeep this. Move this part.\n")
      (with-current-buffer (find-file-noselect source)
        (org-mode)
        (goto-char (point-min))
        (search-forward "Move")
        (let ((beg (match-beginning 0)))
          (end-of-line)
          (transient-mark-mode 1)
          (set-mark beg)
          (activate-mark)
          (let* ((note (my/node-capture-region-as-note "Moved part"))
                 (text (my/test-capture--contents (plist-get note :file))))
            (should (string-match-p "Move this part\\." text))
            (should (string-match-p "\\[\\[id:src-1\\]\\]" text))
            (should (string-match-p
                     (regexp-quote (format "Keep this. [[id:%s][Moved part]]"
                                           (plist-get note :id)))
                     (buffer-string)))))))))

;; ---- Daily ----

(ert-deftest my/daily-file-and-append-create-the-daily-note ()
  (my/test-capture--with-library
    (let* ((time (encode-time 0 30 9 14 7 2026))
           (file (my/daily-file-for-date time)))
      (should (equal file (expand-file-name "daily/2026-07-14.org" my/inbox-dir)))
      (should-not (file-exists-p file))
      (let ((entry (my/daily-append "first thought" time)))
        (should (equal (plist-get entry :file) file))
        (should (equal (my/test-capture--contents file)
                       "#+title: 2026-07-14\n#+filetags: :daily:\n* 09:30 first thought\n")))
      ;; A visiting buffer is edited in place and saved.
      (with-current-buffer (find-file-noselect file)
        (let ((entry (my/daily-append "" time)))
          (should-not (buffer-modified-p))
          (goto-char (plist-get entry :pos))
          (should (looking-back "^\\* 09:30" (line-beginning-position)))))
      (should (string-suffix-p "first thought\n* 09:30\n"
                               (my/test-capture--contents file))))))

(ert-deftest my/daily-open-and-step-between-existing-days ()
  (my/test-capture--with-library
    (dolist (date '("2026-07-01" "2026-07-03" "2026-07-09"))
      (my/test-capture--write (expand-file-name (concat "daily/" date ".org") my/inbox-dir)
                              (format "#+title: %s\n" date)))
    (should (equal (mapcar #'file-name-base (my/daily-files))
                   '("2026-07-01" "2026-07-03" "2026-07-09")))
    (should (equal (file-name-base (my/daily-neighbor-file 'previous "2026-07-03"))
                   "2026-07-01"))
    (should (equal (file-name-base (my/daily-neighbor-file 'next "2026-07-03"))
                   "2026-07-09"))
    (should (equal (file-name-base (my/daily-neighbor-file 'previous "2026-07-05"))
                   "2026-07-03"))
    (should-not (my/daily-neighbor-file 'next "2026-07-09"))
    (my/daily-open-date (encode-time 0 0 12 3 7 2026))
    (my/daily-goto-next-note)
    (should (equal (file-name-base (buffer-file-name)) "2026-07-09"))
    (my/daily-goto-previous-note)
    (should (equal (file-name-base (buffer-file-name)) "2026-07-03"))
    (my/daily-open-date (encode-time 0 0 12 20 7 2026))
    (should (equal (my/test-capture--contents (buffer-file-name))
                   "#+title: 2026-07-20\n#+filetags: :daily:\n"))))

;; ---- Node find, backlinks, id links ----

(defconst my/test-capture--graph
  '(("a.org" . ":PROPERTIES:\n:ID:       node-a\n:ROAM_ALIASES: \"WM\" \"short term store\"\n:END:\n#+title: Working memory\n\nSee [[id:node-b][B]].\n")
    ("b.org" . ":PROPERTIES:\n:ID:       node-b\n:END:\n#+title: Attention\n\n* Detail\n:PROPERTIES:\n:ID:       node-b2\n:END:\nBack to [[id:node-a][A]] and [[id:node-a][again]].\n")
    ("c.org" . ":PROPERTIES:\n:ID:       node-c\n:END:\n#+title: Attention\n\nAlso [[id:node-a]].\n"))
  "Three files: two nodes share a title, two link to node-a.")

(defun my/test-capture--write-graph ()
  "Write `my/test-capture--graph' into the roam directory."
  (pcase-dolist (`(,name . ,text) my/test-capture--graph)
    (my/test-capture--write (expand-file-name name my/inbox-dir) text)))

(ert-deftest my/node-candidates-include-aliases-and-disambiguate ()
  (my/test-capture--with-library
    (my/test-capture--write-graph)
    (let* ((table (my/node-candidates (my/index-records) t))
           (labels (hash-table-keys table)))
      (should (member "Working memory" labels))
      (should (member "WM -> Working memory" labels))
      (should (member "short term store -> Working memory" labels))
      (should (member "Attention  (b)" labels))
      (should (member "Attention  (c)" labels))
      (should (member "Detail" labels))
      (should (equal (plist-get (gethash "WM -> Working memory" table) :id) "node-a"))
      (should-not (member "WM -> Working memory"
                          (hash-table-keys (my/node-candidates (my/index-records))))))))

(ert-deftest my/node-find-visits-or-offers-capture ()
  (my/test-capture--with-library
    (my/test-capture--write-graph)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "WM -> Working memory")))
      (my/node-find)
      (should (equal (file-name-nondirectory (buffer-file-name)) "a.org")))
    (let (asked)
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Brand new idea"))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) (setq asked t) t))
                ((symbol-function 'my/capture--choose-template)
                 (lambda (templates) (car templates))))
        (my/node-find))
      (should asked)
      (should (string-match-p "brand_new_idea" (buffer-file-name))))))

(ert-deftest my/node-insert-link-uses-region-as-description ()
  (my/test-capture--with-library
    (my/test-capture--write-graph)
    (with-temp-buffer
      (org-mode)
      (insert "about the store here")
      (transient-mark-mode 1)
      (goto-char 11)
      (set-mark 16)
      (activate-mark)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "short term store -> Working memory")))
        (my/node-insert-link))
      (should (equal (buffer-string) "about the [[id:node-a][store]] here")))
    (with-temp-buffer
      (org-mode)
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Detail")))
        (my/node-insert-link))
      (should (equal (buffer-string) "[[id:node-b2][Detail]]")))))

(ert-deftest my/node-backlinks-list-each-linking-node-once ()
  (my/test-capture--with-library
    (my/test-capture--write-graph)
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (my/node-backlink-records "node-a"))
                   '("node-c" "node-b2")))
    (should-not (my/node-backlink-records "node-c"))
    (with-current-buffer (my/node-backlinks "node-a")
      (should (derived-mode-p 'my/node-backlinks-mode))
      (should (string-match-p "Links to Working memory" (buffer-string)))
      (goto-char (point-min))
      (search-forward "Detail")
      (my/node-backlinks-visit)
      (should (equal (file-name-nondirectory (buffer-file-name)) "b.org"))
      (should (equal (org-entry-get nil "ID") "node-b2")))
    (kill-buffer my/node-backlinks-buffer-name)))

(ert-deftest my/node-forward-links-list-each-linked-node-once ()
  (my/test-capture--with-library
    (my/test-capture--write-graph)
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (my/node-forward-link-records "node-c"))
                   '("node-a")))
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (my/node-forward-link-records "node-a"))
                   '("node-b")))
    (should-not (my/node-forward-link-records "node-b"))
    (with-current-buffer (my/node-forward-links "node-c")
      (should (derived-mode-p 'my/node-backlinks-mode))
      (should (equal (buffer-name) my/node-forward-links-buffer-name))
      (should (string-match-p "Links from " (buffer-string)))
      (goto-char (point-min))
      (search-forward "Working memory")
      (my/node-backlinks-visit)
      (should (equal (org-entry-get nil "ID") "node-a")))
    (kill-buffer my/node-forward-links-buffer-name)))

(ert-deftest my/id-links-open-through-the-index-then-org ()
  (my/test-capture--with-library
    (my/test-capture--write-graph)
    (with-temp-buffer
      (org-mode)
      (insert "[[id:node-b2][Detail]]")
      (goto-char 3)
      (org-open-at-point)
      (should (equal (file-name-nondirectory (buffer-file-name)) "b.org"))
      (should (equal (org-entry-get nil "ID") "node-b2")))
    ;; An id the index does not know goes to Org's own lookup.
    (let (asked)
      (cl-letf (((symbol-function 'org-id-open)
                 (lambda (id &rest _) (setq asked id))))
        (with-temp-buffer
          (org-mode)
          (insert "[[id:not-indexed]]")
          (goto-char 3)
          (org-open-at-point)))
      (should (equal asked "not-indexed")))))

(ert-deftest my/new-heading-id-is-found-without-org-roam ()
  (my/test-capture--with-library
    (let ((file (expand-file-name "fresh.org" my/inbox-dir)))
      (my/test-capture--write file "#+title: Fresh\n\n* New heading\n")
      (with-current-buffer (find-file-noselect file)
        (org-mode)
        (goto-char (point-max))
        (forward-line -1)
        (let ((id (org-id-get-create)))
          (save-buffer)
          (should (equal (plist-get (my/index-node id) :title) "New heading"))
          (with-temp-buffer
            (org-mode)
            (insert (format "[[id:%s]]" id))
            (goto-char 3)
            (org-open-at-point)
            (should (equal (org-entry-get nil "ID") id))))))))

(ert-deftest my/capture-runs-without-org-roam ()
  "Nothing above loaded org-roam."
  (should-not (featurep 'org-roam)))

(ert-deftest my/note-create-stays-inside-the-library ()
  "A path with .. or an absolute path cannot take a note out of the library."
  (my/test-capture--with-library
    (let ((outside (expand-file-name "../escaped.org" my/note-home)))
      (should-error (my/note-create :title "Escape" :file "../../escaped.org")
                    :type 'user-error)
      (should-error (my/note-create :title "Escape" :file outside) :type 'user-error)
      (should-not (file-exists-p outside))
      ;; A title full of path syntax still lands in the capture directory.
      (let ((note (my/note-create :title "../../../etc/passwd")))
        (should (string-prefix-p (expand-file-name my/note-home)
                                 (plist-get note :file)))))))

(ert-deftest my/daily-offset-steps-calendar-days ()
  (let ((tomorrow (decode-time (my/daily--offset-days 1)))
        (today (decode-time)))
    (should (= 12 (decoded-time-hour tomorrow)))
    (should (equal (format-time-string "%F" (my/daily--offset-days 0))
                   (format-time-string "%F")))
    (should-not (equal (decoded-time-day tomorrow) (decoded-time-day today)))))

;;; test-init-capture.el ends here
