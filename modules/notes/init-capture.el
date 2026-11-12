;;; init-capture.el --- Note capture, Daily commands and note search -*- lexical-binding: t; -*-
;;
;; Interactive note creation without org-roam.  New files are written by
;; the kernel (kernel/orgseq-note.el), the same function the command line
;; and the MCP tools use, and the kernel index picks them up at once.
;;
;;   Templates  Capture templates in org-roam-capture format, from three
;;              sources: `my/default-capture-templates', the functions on
;;              `my/capture-template-functions' (init-nodes adds one per
;;              type in types.org) and the user's
;;              .orgseq/capture-templates.el.  The supported subset is
;;              described in orgseq-note.el; other templates are skipped
;;              with one warning each.
;;   Capture    `my/note-capture' asks for a title (and a template when
;;              several apply), writes the note and visits it with point
;;              where the template's %? mark was.
;;   Daily      One file per day under daily/; open a date, step between
;;              days, append a timestamped entry.
;;   Search     Plain ripgrep over the notes, and Deft.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │ Section 1  Org ids                                               │
;; │ Section 2  Capture templates                                     │
;; │ Section 3  Capture command                                       │
;; │ Section 4  Daily commands                                        │
;; │ Section 5  Search                                                │
;; └─────────────────────────────────────────────────────────────────┘

;; Requires: init-org (library paths and Org configuration)

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'orgseq-note)

(defvar my/note-home)
(defvar my/roam-dir)
(defvar my/capture-templates-file)

(declare-function consult-ripgrep "consult" (&optional dir initial))
(declare-function grep-read-regexp "grep" ())
(declare-function grep "grep" (command-args))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Org ids
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Timestamp ids, the format every org-seq note has used: readable, and
;; sortable by creation time.

(setq org-id-method 'ts
      org-id-ts-format "%Y%m%dT%H%M%S")

(defun my/capture--use-id-links ()
  "Make `org-store-link' create id links in library files."
  (when (and buffer-file-name
             (file-in-directory-p buffer-file-name my/note-home))
    (setq-local org-id-link-to-org-use-id 'create-if-interactive)))

(add-hook 'org-mode-hook #'my/capture--use-id-links)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Capture templates
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/default-capture-templates
  '(("d" "Default" plain "%?"
     :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                        "#+title: ${title}\n")
     :unnarrowed t))
  "Built-in capture templates, offered before typed and user templates.")

(defvar my/user-capture-templates nil
  "User capture templates loaded from .orgseq/capture-templates.el.")

(defvar my/capture-template-functions nil
  "Functions called with no argument, each returning capture templates.
init-nodes adds the generated type templates here.")

(defvar my/capture-templates-changed-hook nil
  "Hook run after the capture templates were reloaded.")

(defvar my/capture-fields-function nil
  "Function of a tag list returning field names for a new note.
The fields are written as empty properties so a typed note shows what
can be filled in.  Set by init-nodes; nil adds no fields.")

(defvar my/capture--user-loaded nil
  "Non-nil once the user template file was read in this session.")

(defvar my/capture--warned (make-hash-table :test 'equal)
  "Template labels already reported as unsupported in this session.")

(defconst my/capture-templates-template
  ";;; capture-templates.el --- User capture templates -*- lexical-binding: t; -*-
;;
;; Free-form capture templates.  For notes that belong to a type (with
;; fields and a view), define the type in types.org instead: org-seq
;; generates its capture template automatically.
;;
;; Each entry follows the org-roam-capture-templates format:
;;   (KEY DESCRIPTION plain BODY :target (file+head PATH HEAD))
;; PATH is relative to 00_Roam/.  PATH, HEAD and BODY may use ${title},
;; ${slug}, %<TIME-FORMAT>, %t %T %u %U, and %? marks where the cursor
;; lands.  Keys starting with \"t\" are reserved for type templates.
;;
;; Reload after editing:  SPC # C  (my/reload-capture-templates)

(setq my/user-capture-templates
      '(
        ;; (\"m\" \"Meeting\" plain
        ;;  \"* Attendees\\n* Notes\\n%?\\n* Decisions\\n\"
        ;;  :target (file+head \"capture/%<%Y%m%dT%H%M%S>-${slug}.org\"
        ;;                     \"#+title: ${title}\\n\")
        ;;  :unnarrowed t)
        ))

;;; capture-templates.el ends here
"
  "Template content for a new capture-templates.el file.")

(defun my/load-user-file-safely (file description)
  "Load FILE and report a clear error tagged with DESCRIPTION on failure."
  (condition-case err
      (progn
        (load file nil 'nomessage)
        t)
    (error
     (message "org-seq: failed to load %s from %s: %s" description file err)
     nil)))

(defun my/ensure-capture-templates-file ()
  "Create .orgseq/capture-templates.el with examples if missing."
  (unless (file-exists-p my/capture-templates-file)
    (make-directory (file-name-directory my/capture-templates-file) t)
    (with-temp-file my/capture-templates-file
      (insert my/capture-templates-template))
    (message "org-seq: created %s" my/capture-templates-file)))

(defun my/capture--load-user-templates ()
  "Read the user template file into `my/user-capture-templates'."
  (setq my/user-capture-templates nil
        my/capture--user-loaded t)
  (when (file-exists-p my/capture-templates-file)
    (my/load-user-file-safely my/capture-templates-file "capture templates")))

(defun my/capture-templates ()
  "Return every capture template: defaults, generated, then user ones."
  (unless my/capture--user-loaded
    (my/capture--load-user-templates))
  (append my/default-capture-templates
          (cl-mapcan (lambda (fn) (copy-sequence (funcall fn)))
                     my/capture-template-functions)
          my/user-capture-templates))

(defun my/capture--warn (template reason)
  "Report TEMPLATE as skipped for REASON, once per session."
  (let ((label (my/note-template-label template)))
    (unless (gethash label my/capture--warned)
      (puthash label t my/capture--warned)
      (display-warning
       'org-seq
       (format "Capture template \"%s\" skipped: it %s (see %s)"
               label reason my/capture-templates-file)
       :warning))))

(defun my/capture-usable-templates (&optional templates)
  "Return the supported templates among TEMPLATES (default: all).
Unsupported ones are reported with `my/capture--warn'; menu groups are
dropped silently."
  (let (usable)
    (dolist (template (or templates (my/capture-templates)))
      (condition-case err
          (when (my/note-template-parse template)
            (push template usable))
        (my/note-template-unsupported
         (my/capture--warn template (cadr err)))))
    (nreverse usable)))

(defun my/reload-capture-templates ()
  "Reload user capture templates and report what is available."
  (interactive)
  (clrhash my/capture--warned)
  (my/capture--load-user-templates)
  (run-hooks 'my/capture-templates-changed-hook)
  (let ((all (my/capture-templates)))
    (message "org-seq: %d capture templates usable (%d user)"
             (length (my/capture-usable-templates all))
             (length my/user-capture-templates))))

(defun my/edit-capture-templates ()
  "Open the user capture templates file for editing."
  (interactive)
  (my/ensure-capture-templates-file)
  (find-file my/capture-templates-file))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Capture command
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/capture--template-tags (template)
  "Return the tags on the #+filetags line of TEMPLATE's head, if any."
  (let ((head (plist-get (ignore-errors (my/note-template-parse template)) :head)))
    (when (and head (string-match "^#\\+filetags:[ \t]*\\(.*\\)$" head))
      (split-string (match-string 1 head) "[: \t]+" t))))

(defun my/capture--props (template fields)
  "Return the property alist for a note from TEMPLATE with FIELDS.
Empty slots for the fields of the template's types come first; FIELDS,
an alist of (NAME . VALUE), fill or extend them."
  (let ((props (mapcar (lambda (name) (cons (upcase name) ""))
                       (and my/capture-fields-function
                            (funcall my/capture-fields-function
                                     (my/capture--template-tags template))))))
    (pcase-dolist (`(,name . ,value) fields)
      (let* ((name (upcase (format "%s" name)))
             (cell (assoc name props)))
        (if cell
            (setcdr cell value)
          (setq props (append props (list (cons name value)))))))
    props))

(cl-defun my/note-capture-create (title template &key fields initial)
  "Create a note titled TITLE from TEMPLATE without visiting it.
FIELDS is an alist of (NAME . VALUE) set on the note; INITIAL is the
text the template's %i stands for.  Return the plist of
`my/note-create-from-template'."
  (my/note-create-from-template template title
                                :props (my/capture--props template fields)
                                :initial initial))

(defun my/capture--choose-template (templates)
  "Return one of TEMPLATES, asking when there are several."
  (cond
   ((null templates) (user-error "No usable capture template; see SPC # c"))
   ((null (cdr templates)) (car templates))
   (t
    (let* ((table (mapcar (lambda (template)
                            (cons (format "%-4s %s" (nth 0 template) (nth 1 template))
                                  template))
                          templates)))
      (cdr (assoc (completing-read "Template: " table nil t) table))))))

(defun my/note-capture (&optional title template fields no-visit)
  "Create a new note titled TITLE and visit it.
TEMPLATE is a capture template in org-roam format; nil asks when several
templates apply.  FIELDS is an alist of (NAME . VALUE) to set.  With
NO-VISIT the note is written but not shown.  Return the note plist
\(:id :file :title :cursor)."
  (interactive)
  (let* ((title (or title (read-string "New note title: ")))
         (template (or template
                       (my/capture--choose-template (my/capture-usable-templates))))
         (note (my/note-capture-create title template :fields fields)))
    (unless no-visit
      (find-file (plist-get note :file))
      (goto-char (min (point-max) (plist-get note :cursor))))
    (message "org-seq: created %s"
             (file-relative-name (plist-get note :file) my/note-home))
    note))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Daily commands
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/daily-open-date (time)
  "Visit the Daily note of TIME, creating the file when it is missing."
  (find-file (my/daily-ensure-file time)))

(defun my/daily-open-today ()
  "Visit today's Daily note."
  (interactive)
  (my/daily-open-date (current-time)))

(defun my/daily--offset-days (days)
  "Return a time on the calendar day DAYS days from today.
Steps the calendar date, not 24-hour blocks, so a daylight-saving change
cannot skip or repeat a day; the result is noon of that day."
  (let ((now (decode-time)))
    (encode-time (list 0 0 12 (+ (decoded-time-day now) days)
                       (decoded-time-month now) (decoded-time-year now)
                       nil -1 nil))))

(defun my/daily-goto-yesterday ()
  "Visit yesterday's Daily note."
  (interactive)
  (my/daily-open-date (my/daily--offset-days -1)))

(defun my/daily-goto-tomorrow ()
  "Visit tomorrow's Daily note."
  (interactive)
  (my/daily-open-date (my/daily--offset-days 1)))

(defun my/daily-find-date ()
  "Pick a date with the Org calendar and visit its Daily note."
  (interactive)
  (my/daily-open-date (org-read-date nil t nil "Daily note for: ")))

(defun my/daily--current-date ()
  "Return the date (YYYY-MM-DD) of the Daily buffer, else of today."
  (let ((name (and buffer-file-name (file-name-base buffer-file-name))))
    (if (and name
             (string-match-p "\\`[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]\\'" name)
             (file-in-directory-p buffer-file-name (my/daily-dir)))
        name
      (format-time-string "%Y-%m-%d"))))

(defun my/daily-neighbor-file (direction &optional date)
  "Return the existing Daily file before or after DATE.
DIRECTION is `previous' or `next'; DATE (YYYY-MM-DD) defaults to the
current Daily buffer's date, else today.  Return nil when there is none."
  (let ((date (or date (my/daily--current-date)))
        (files (my/daily-files)))
    (if (eq direction 'previous)
        (car (last (cl-remove-if-not
                    (lambda (file) (string< (file-name-base file) date)) files)))
      (cl-find-if (lambda (file) (string< date (file-name-base file))) files))))

(defun my/daily-goto-previous-note ()
  "Visit the Daily note before the current one that exists."
  (interactive)
  (find-file (or (my/daily-neighbor-file 'previous)
                 (user-error "No earlier Daily note"))))

(defun my/daily-goto-next-note ()
  "Visit the Daily note after the current one that exists."
  (interactive)
  (find-file (or (my/daily-neighbor-file 'next)
                 (user-error "No later Daily note"))))

(defun my/daily-capture-date (time text)
  "Append TEXT as a timestamped heading to the Daily note of TIME; visit it."
  (interactive
   (let ((time (org-read-date nil t nil "Daily note for: ")))
     (list time (read-string "Entry: "))))
  (let ((entry (my/daily-append text time)))
    (find-file (plist-get entry :file))
    (goto-char (plist-get entry :pos))
    entry))

(defun my/daily-capture-today (text)
  "Append TEXT as a timestamped heading to today's Daily note; visit it."
  (interactive (list (read-string "Today: ")))
  (my/daily-capture-date (current-time) text))

(define-obsolete-function-alias 'my/org-roam-dailies--file-for-date
  #'my/daily-file-for-date "2026-11-12")
(define-obsolete-function-alias 'my/org-roam-dailies-open-date
  #'my/daily-open-date "2026-11-12")
(define-obsolete-function-alias 'my/org-roam-dailies-open-today
  #'my/daily-open-today "2026-11-12")

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Search
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/note-search-text ()
  "Search the text of the notes in 00_Roam/ with ripgrep.
Uses consult-ripgrep when Consult is installed, else a plain *grep*
buffer running rg."
  (interactive)
  (if (fboundp 'consult-ripgrep)
      (consult-ripgrep my/roam-dir)
    (unless (executable-find "rg")
      (user-error "ripgrep (rg) is not installed"))
    (require 'grep)
    (let ((query (grep-read-regexp))
          (default-directory my/roam-dir))
      (grep (concat "rg --no-heading --line-number --smart-case --glob '*.org' -e "
                    (shell-quote-argument query) " .")))))

;; Deft: incremental search over file names and text of every note.
(use-package deft
  :commands (deft deft-find-file deft-refresh)
  :custom
  (deft-directory my/note-home)
  (deft-extensions '("org" "md" "markdown" "txt"))
  (deft-recursive t)
  (deft-recursive-ignore-dir-regexp
   (concat "\\(?:"
           "\\`\\.[^/]*\\'"
           "\\|\\`dashboards\\'"
           "\\)"))
  (deft-default-extension "org")
  (deft-org-mode-title-prefix t)
  (deft-use-filename-as-title nil)
  (deft-auto-save-interval 0)
  (deft-strip-summary-regexp
   (concat "\\("
           "[\n\t]"
           "\\|^#\\+[[:upper:]_]+:.*$"
           "\\|^:PROPERTIES:$"
           "\\|^:END:$"
           "\\|^:[[:upper:]_]+:.*$"
           "\\)")))

;; Non-leader bindings for the note commands (the leader keys live in
;; init-evil).  The node commands are defined by init-nodes.
(keymap-global-set "C-c n c" #'my/note-capture)
(keymap-global-set "C-c n j" #'my/daily-open-today)
(keymap-global-set "C-c n f" #'deft)
(keymap-global-set "C-c n F" 'my/node-find)
(keymap-global-set "C-c n i" 'my/node-insert-link)
(keymap-global-set "C-c n l" 'my/node-backlinks)

(provide 'init-capture)
;;; init-capture.el ends here
