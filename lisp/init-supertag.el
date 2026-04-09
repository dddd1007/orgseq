;;; init-supertag.el --- Tana-style structured tags + PARA navigation -*- lexical-binding: t; -*-

;; Requires: init-org (my/note-home, my/orgseq-dir)
;; Requires: init-pkm (org-supertag base setup)
(defvar my/note-home)
(defvar my/orgseq-dir)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: NoteHQ path constants
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Physical structure follows Roam (atomic) + PARA (output) separation.
;; Roam/ is flat except daily/, capture/, dashboards/.
;; Tag-based classification replaces directory-based classification.

(defconst my/roam-dir      (expand-file-name "Roam/"       my/note-home))
(defconst my/outputs-dir   (expand-file-name "Outputs/"    my/note-home))
(defconst my/practice-dir  (expand-file-name "Practice/"   my/note-home))
(defconst my/library-dir   (expand-file-name "Library/"    my/note-home))
(defconst my/archives-dir  (expand-file-name "Archives/"   my/note-home))
(defconst my/dashboards-dir (expand-file-name "dashboards/" my/roam-dir))
(defconst my/schema-file   (expand-file-name "supertag-schema.el" my/roam-dir))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Schema editing and reloading
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/edit-supertag-schema ()
  "Open the supertag schema definition file."
  (interactive)
  (find-file my/schema-file))

(defun my/reload-supertag-schema ()
  "Reload tag definitions without restarting Emacs."
  (interactive)
  (if (file-exists-p my/schema-file)
      (progn
        (load my/schema-file :noerror :nomessage)
        (message "org-seq: supertag schema reloaded from %s" my/schema-file))
    (message "org-seq: schema file not found: %s" my/schema-file)))

;; Load schema on supertag init (incremental — only if file exists)
(with-eval-after-load 'org-supertag
  (when (file-exists-p my/schema-file)
    (load my/schema-file :noerror :nomessage)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Tag and field quick actions
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/supertag-quick-action ()
  "Context-aware popup for tag and field operations on the current node."
  (interactive)
  (require 'org-supertag)
  (let* ((node-id (org-id-get-create))
         (tags (ignore-errors (org-supertag-node-get-tags node-id))))
    (if (null tags)
        (call-interactively #'org-supertag-tag-add-tag)
      (let ((choice (completing-read
                     "Action: "
                     `("[+] Add another tag"
                       "[-] Remove a tag"
                       ,@(mapcar (lambda (tag) (format "[edit] %s fields" tag)) tags)
                       ,@(mapcar (lambda (tag) (format "[goto] linked from %s" tag)) tags)))))
        (cond
         ((string-prefix-p "[+]"    choice) (call-interactively #'org-supertag-tag-add-tag))
         ((string-prefix-p "[-]"    choice) (call-interactively #'org-supertag-tag-remove))
         ((string-prefix-p "[edit]" choice) (call-interactively #'org-supertag-node-edit-field))
         ((string-prefix-p "[goto]" choice) (call-interactively #'org-supertag-node-follow-ref)))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Dashboard navigation
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Dashboards are read-only query windows in ~/NoteHQ/Roam/dashboards/.
;; They display supertag query results — never used for data entry.

(defun my/dashboard-open (name)
  "Open dashboard NAME (without .org) and refresh all dynamic blocks."
  (let ((file (expand-file-name (concat name ".org") my/dashboards-dir)))
    (if (file-exists-p file)
        (progn
          (find-file file)
          (when (fboundp 'org-update-all-dblocks)
            (ignore-errors (org-update-all-dblocks))))
      (message "org-seq: dashboard not found: %s" file))))

(defun my/dash-index   () "Open dashboard index."   (interactive) (my/dashboard-open "index"))
(defun my/dash-review  () "Open weekly review."      (interactive) (my/dashboard-open "weekly-review"))
(defun my/dash-reading () "Open reading dashboard."  (interactive) (my/dashboard-open "reading"))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: PARA layer navigation
;; ═══════════════════════════════════════════════════════════════════════════

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

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: Incremental NoteHQ directory bootstrap
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Ensure critical directories exist on startup.  Does not create seed
;; files — those come from the bootstrap script.

(defun my/ensure-notehq-structure ()
  "Create NoteHQ directory skeleton if missing.  Idempotent."
  (dolist (dir (list my/roam-dir
                     (expand-file-name "daily/"    my/roam-dir)
                     (expand-file-name "capture/"  my/roam-dir)
                     my/dashboards-dir
                     my/outputs-dir
                     my/practice-dir
                     my/library-dir
                     my/archives-dir))
    (make-directory dir t)))

(my/ensure-notehq-structure)

(provide 'init-supertag)
;;; init-supertag.el ends here
