;;; orgseq-note.el --- Writing new notes and Daily entries -*- lexical-binding: t; -*-
;;
;; Kernel file: no UI, no dependency on any module or on org-roam.
;;
;; The one write path for new note files.  The interactive capture
;; (modules/notes/init-capture.el), the command line and the MCP tools
;; (core/orgseq-cli.el) all create notes here, so a note looks the same
;; whichever way it was made:
;;
;;   :PROPERTIES:
;;   :ID:       20261112T101500
;;   :FIELD:    value
;;   :END:
;;   #+title: Title
;;   #+filetags: :tag:
;;
;;   Body
;;
;; Capture templates are user data written in org-roam-capture format.
;; This file expands the common subset of that format without org-roam:
;; plain templates with a `file' or `file+head' target, ${title},
;; ${slug}, %<TIME-FORMAT>, %t %T %u %U, %i, %% and the %? cursor mark.
;; A template outside that subset is reported as unsupported, never
;; half-expanded.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │ Section 1  Ids, slugs and file names                             │
;; │ Section 2  Creating a note file                                  │
;; │ Section 3  Capture templates (org-roam-capture format subset)    │
;; │ Section 4  Daily files                                           │
;; └─────────────────────────────────────────────────────────────────┘

(require 'cl-lib)
(require 'subr-x)
(require 'orgseq-paths)
(require 'orgseq-index)

(defvar my/roam-dir)

(declare-function org-id-new "org-id" (&optional prefix))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Ids, slugs and file names
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/note-slug (title)
  "Return a file-name slug for TITLE: lower case, runs of other characters as _.
Letters of any script are kept."
  (let ((slug (string-trim
               (replace-regexp-in-string "[^[:alnum:]]+" "_" (downcase title))
               "_+" "_+")))
    (if (string-empty-p slug) "note" (truncate-string-to-width slug 60))))

(defun my/note-new-id ()
  "Return a new Org id that no indexed node uses yet.
Timestamp ids have one-second resolution, and scripts can create several
notes within a second, so a taken id gets a random suffix."
  (require 'org-id)
  (let ((new (org-id-new)))
    (while (my/index-node new)
      (setq new (format "%s-%04x" (org-id-new) (random 65536))))
    new))

(defun my/note--free-file (file)
  "Return FILE, or FILE with a -N suffix when FILE already exists."
  (let ((candidate file)
        (n 1))
    (while (file-exists-p candidate)
      (setq candidate (format "%s-%d.%s" (file-name-sans-extension file)
                              (cl-incf n) (or (file-name-extension file) "org"))))
    candidate))

(defun my/note-capture-dir ()
  "Return the directory new notes go to when no template names one."
  (expand-file-name "capture/" my/roam-dir))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Creating a note file
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/note-default-head (title &optional tags)
  "Return the #+title (and #+filetags for TAGS) lines of a new note."
  (concat (format "#+title: %s\n" title)
          (if tags (format "#+filetags: :%s:\n" (string-join tags ":")) "")))

(cl-defun my/note-create (&key title file id props tags head body)
  "Write a new note file and add it to the index.
TITLE is the note title.  FILE is the file to create; a relative name is
taken relative to `my/roam-dir', and nil means capture/STAMP-SLUG.org.
An existing file is never overwritten: a numeric suffix is added instead.
ID defaults to `my/note-new-id'.  PROPS is an alist of (NAME . VALUE)
written to the file's property drawer after the id.  HEAD is the text
after the drawer (default: #+title, plus #+filetags from TAGS).  BODY
follows HEAD after one blank line.

Return a plist (:id ID :file FILE :title TITLE :body-start POS), where
POS is the buffer position at which BODY begins in the new file."
  (when (or (null title) (string-empty-p (string-trim title)))
    (user-error "A note needs a title"))
  (let* ((id (or id (my/note-new-id)))
         (file (my/note--free-file
                (expand-file-name
                 (or file
                     (format "%s-%s.org" (format-time-string "%Y%m%dT%H%M%S")
                             (my/note-slug title)))
                 (if file my/roam-dir (my/note-capture-dir)))))
         (head (or head (my/note-default-head title tags)))
         (body (or body ""))
         (coding-system-for-write 'utf-8-unix)
         body-start)
    ;; FILE may come from a user template or a title placed in a path; a
    ;; ".." or an absolute path must not take the note out of the library.
    (unless (string-prefix-p
             (file-name-as-directory (expand-file-name my/note-home))
             (expand-file-name file))
      (user-error "Note path %s is outside the library %s"
                  file (abbreviate-file-name my/note-home)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert ":PROPERTIES:\n" (format ":ID:       %s\n" id))
      (pcase-dolist (`(,name . ,value) props)
        (insert (format ":%s: %s\n" (upcase (format "%s" name)) (or value ""))))
      (insert ":END:\n" head)
      (unless (bolp) (insert "\n"))
      (insert "\n")
      (setq body-start (point))
      (insert body)
      (unless (bolp) (insert "\n")))
    (my/index-update-file file)
    (list :id id :file file :title title :body-start body-start)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Capture templates
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; A template is (KEY DESCRIPTION plain BODY [:target TARGET] [OPTIONS...]).
;; TARGET is (file+head PATH HEAD) or (file PATH); without :target the
;; org-roam default applies.  Options such as :unnarrowed only change how
;; org-roam shows its capture buffer and are ignored here.  A two-element
;; entry (KEY DESCRIPTION) is a menu group and is not a template.

(define-error 'my/note-template-unsupported "Unsupported capture template")

(defconst my/note-default-target
  '(file+head "%<%Y%m%d%H%M%S>-${slug}.org" "#+title: ${title}\n")
  "Target of a template that names none (org-roam's default).")

(defun my/note-template-expand (text title &optional time initial)
  "Expand capture template TEXT for a note titled TITLE.
Return (EXPANDED . CURSOR): CURSOR is the offset of the %? mark in
EXPANDED, or nil.  TIME (default now) feeds %<FORMAT>, %t, %T, %u and
%U; INITIAL is the text %i stands for.  Anything else in ${...} or an
Org capture escape not listed signals `my/note-template-unsupported'."
  (let ((time (or time (current-time)))
        (start 0)
        (parts nil)
        (length 0)
        cursor)
    (cl-flet ((emit (string)
                (push string parts)
                (setq length (+ length (length string)))))
      (while (string-match "\\${\\([^}]*\\)}\\|%\\(<\\([^>]*\\)>\\|.\\)" text start)
        (emit (substring text start (match-beginning 0)))
        (setq start (match-end 0))
        (let ((var (match-string 1 text))
              (format (match-string 3 text))
              (escape (match-string 2 text)))
          (cond
           (var
            (pcase var
              ("title" (emit title))
              ("slug" (emit (my/note-slug title)))
              (_ (signal 'my/note-template-unsupported
                         (list (format "uses ${%s}" var))))))
           (format (emit (format-time-string format time)))
           ((equal escape "?") (unless cursor (setq cursor length)))
           ((equal escape "%") (emit "%"))
           ((equal escape "t") (emit (format-time-string "<%Y-%m-%d %a>" time)))
           ((equal escape "T") (emit (format-time-string "<%Y-%m-%d %a %H:%M>" time)))
           ((equal escape "u") (emit (format-time-string "[%Y-%m-%d %a]" time)))
           ((equal escape "U") (emit (format-time-string "[%Y-%m-%d %a %H:%M]" time)))
           ((equal escape "i") (emit (or initial "")))
           ((string-match-p "[[:alpha:]^(\\[\\\\:{]" escape)
            (signal 'my/note-template-unsupported
                    (list (format "uses the %%%s escape" escape))))
           ;; A percent sign before anything else is plain text.
           (t (emit (concat "%" escape))))))
      (emit (substring text start)))
    (cons (apply #'concat (nreverse parts)) cursor)))

(defun my/note-template-parse (template)
  "Check capture TEMPLATE and return its parts as a plist.
The plist has :key :description :body :path :head (HEAD is nil for a
`file' target).  Return nil for a menu group entry.  Signal
`my/note-template-unsupported' for any other shape."
  (cond
   ((and (consp template) (= (length template) 2)
         (stringp (car template)) (stringp (cadr template)))
    nil)
   ((not (and (proper-list-p template) (>= (length template) 4)
              (stringp (nth 0 template)) (stringp (nth 1 template))))
    (signal 'my/note-template-unsupported
            (list "is not a (KEY DESCRIPTION TYPE BODY ...) list")))
   (t
    (pcase-let* ((`(,key ,description ,type ,body . ,options) template)
                 (target (or (plist-get options :target) my/note-default-target)))
      (unless (eq type 'plain)
        (signal 'my/note-template-unsupported
                (list (format "has type %s; only plain templates are supported" type))))
      (unless (stringp body)
        (signal 'my/note-template-unsupported
                (list "has a body that is not a string")))
      (let ((parts
             (pcase target
               (`(file+head ,(and path (pred stringp)) ,(and head (pred stringp)))
                (list :key key :description description :body body
                      :path path :head head))
               (`(file ,(and path (pred stringp)))
                (list :key key :description description :body body
                      :path path :head nil))
               (_ (signal 'my/note-template-unsupported
                          (list (format "has target %S; only file and file+head are supported"
                                        (car-safe target))))))))
        ;; A trial expansion finds placeholders this subset cannot fill,
        ;; so such a template is rejected before any file is written.
        (dolist (text (list (plist-get parts :path) (plist-get parts :head) body))
          (when text (my/note-template-expand text "title")))
        parts)))))

(defun my/note-template-label (template)
  "Return \"KEY DESCRIPTION\" naming TEMPLATE in messages."
  (if (consp template)
      (format "%s %s" (car template) (or (car-safe (cdr template)) ""))
    (format "%S" template)))

(cl-defun my/note-create-from-template (template title &key props initial time)
  "Create a note titled TITLE from capture TEMPLATE (org-roam format).
PROPS is an alist of (NAME . VALUE) for the property drawer; INITIAL is
the text %i stands for; TIME the capture time.  Return the plist of
`my/note-create' plus :cursor, the position of the %? mark (or the start
of the body)."
  (let* ((parts (or (my/note-template-parse template)
                    (signal 'my/note-template-unsupported
                            (list "is a menu group, not a template"))))
         (time (or time (current-time)))
         (path (car (my/note-template-expand (plist-get parts :path) title time)))
         (head (and (plist-get parts :head)
                    (car (my/note-template-expand (plist-get parts :head)
                                                  title time initial))))
         (body (my/note-template-expand (plist-get parts :body) title time initial))
         (head (or head (my/note-default-head title)))
         (note (my/note-create
                :title title
                :file (if (string-suffix-p ".org" path) path (concat path ".org"))
                :props props :head head :body (car body))))
    (append note
            (list :cursor (+ (plist-get note :body-start) (or (cdr body) 0))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Daily files
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; One file per day, daily/YYYY-MM-DD.org under `my/roam-dir'.  A Daily
;; file starts with a title and the daily tag; entries are top-level
;; headings named by the time they were written.

(defun my/daily-file-for-date (time)
  "Return the Daily file for TIME, without creating it."
  (expand-file-name (format-time-string "%Y-%m-%d.org" time) (my/daily-dir)))

(defun my/daily-header (time)
  "Return the first lines of a new Daily file for TIME."
  (format-time-string "#+title: %Y-%m-%d\n#+filetags: :daily:\n" time))

(defun my/daily-ensure-file (time)
  "Create the Daily file for TIME when it is missing; return its name."
  (let ((file (my/daily-file-for-date time))
        (coding-system-for-write 'utf-8-unix))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (write-region (my/daily-header time) nil file nil 'silent))
    file))

(defun my/daily-files ()
  "Return the existing Daily files, oldest first."
  (let ((dir (my/daily-dir)))
    (and (file-directory-p dir)
         (sort (directory-files
                dir t "\\`[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]\\.org\\'")
               #'string<))))

(defun my/daily-append (text &optional time)
  "Append TEXT as a heading named by the time to the Daily file of TIME.
TIME defaults to now.  A buffer visiting the file is edited and saved,
so an open Daily note never goes stale.  Return a plist (:file FILE
:pos POS), POS being the end of the new heading line."
  (let* ((time (or time (current-time)))
         (file (my/daily-file-for-date time))
         (text (string-trim (or text "")))
         (heading (concat "* " (format-time-string "%H:%M" time)
                          (if (string-empty-p text) "" (concat " " text))))
         (buffer (find-buffer-visiting file))
         pos)
    (cl-flet ((append-heading ()
                (goto-char (point-max))
                (unless (bolp) (insert "\n"))
                (insert heading)
                (setq pos (point))
                (insert "\n")))
      (if buffer
          (with-current-buffer buffer
            (save-excursion
              (save-restriction
                (widen)
                (when (= (point-min) (point-max))
                  (insert (my/daily-header time)))
                (append-heading)))
            (save-buffer))
        (my/daily-ensure-file time)
        (with-temp-buffer
          (insert-file-contents file)
          (append-heading)
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region (point-min) (point-max) file nil 'silent)))))
    (my/index-update-file file)
    (list :file file :pos pos)))

(provide 'orgseq-note)
;;; orgseq-note.el ends here
