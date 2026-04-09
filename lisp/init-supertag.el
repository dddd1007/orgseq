;;; init-supertag.el --- Tana-style structured tags + PARA navigation -*- lexical-binding: t; -*-

;; Requires: init-org (my/note-home, my/orgseq-dir)
;; Requires: init-pkm (org-supertag base setup)
;; Requires: init-roam (my/default-capture-templates)
(defvar my/note-home)
(defvar my/orgseq-dir)
(defvar my/default-capture-templates)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: NoteHQ path constants
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Physical structure follows Roam (atomic) + PARA (output) separation.
;; Roam/ is flat except daily/, capture/, dashboards/.
;; Tag-based classification replaces directory-based classification.

(defconst my/roam-dir       (expand-file-name "Roam/"       my/note-home))
(defconst my/outputs-dir    (expand-file-name "Outputs/"    my/note-home))
(defconst my/practice-dir   (expand-file-name "Practice/"   my/note-home))
(defconst my/library-dir    (expand-file-name "Library/"    my/note-home))
(defconst my/archives-dir   (expand-file-name "Archives/"   my/note-home))
(defconst my/dashboards-dir (expand-file-name "dashboards/" my/roam-dir))
(defconst my/schema-file    (expand-file-name "supertag-schema.el" my/roam-dir))
(defconst my/capture-templates-file
  (expand-file-name "capture-templates.el" my/orgseq-dir)
  "User-defined capture templates.  Edit with SPC n m c, reload with SPC n m C.")

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

(with-eval-after-load 'org-supertag
  (when (file-exists-p my/schema-file)
    (load my/schema-file :noerror :nomessage)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Capture template management
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Built-in "default" template lives in init-roam.el.
;; User-defined templates (reading, session, student, ...) live in
;; ~/.orgseq/capture-templates.el — a plain elisp file that sets
;; `my/user-capture-templates'.  Edit with SPC n m c, reload with SPC n m C.

(defvar my/user-capture-templates nil
  "User-defined org-roam capture templates loaded from .orgseq/capture-templates.el.")

(defconst my/capture-templates-template
  ";;; capture-templates.el --- User capture templates -*- lexical-binding: t; -*-
;;
;; Add your templates here.  Each entry follows org-roam-capture-templates format:
;;   (KEY DESCRIPTION TYPE BODY :target TARGET :unnarrowed t)
;;
;; All captures land in Roam/capture/ (flat, timestamp-prefixed).
;; Classification is handled by supertags, not directories.
;;
;; Reload after editing:  SPC n m C  (my/reload-capture-templates)
;;
;; When to add a new template:
;;   You've used the default template 5+ times for the same type of note,
;;   and you notice they share a common heading structure.

(setq my/user-capture-templates
      '((\"r\" \"Reading\" plain
         \"* TL;DR\\n%?\\n* Key points\\n* My commentary\\n\"
         :target (file+head \"capture/%<%Y%m%dT%H%M%S>-${slug}.org\"
                            \"#+title: ${title}\\n#+filetags: :reading:\\n\")
         :unnarrowed t)

        ;; ---- Add more templates below ----
        ;; Uncomment and adapt these examples when you're ready:
        ;;
        ;; (\"s\" \"Session\" plain
        ;;  \"* 基本信息\\n- 来访者: \\n- 日期: %U\\n* 主诉\\n%?\\n* 过程记录\\n* 评估与计划\\n\"
        ;;  :target (file+head \"capture/%<%Y%m%dT%H%M%S>-${slug}.org\"
        ;;                     \"#+title: ${title}\\n#+filetags: :session:\\n\")
        ;;  :unnarrowed t)
        ;;
        ;; (\"c\" \"Client\" plain
        ;;  \"* 基本信息\\n- 年龄: \\n- 主要议题: \\n%?\\n* 咨询记录\\n\"
        ;;  :target (file+head \"capture/%<%Y%m%dT%H%M%S>-${slug}.org\"
        ;;                     \"#+title: ${title}\\n#+filetags: :client:\\n\")
        ;;  :unnarrowed t)
        ;;
        ;; (\"S\" \"Student\" plain
        ;;  \"* 基本信息\\n- 学号: \\n- 年级: \\n%?\\n* 指导记录\\n\"
        ;;  :target (file+head \"capture/%<%Y%m%dT%H%M%S>-${slug}.org\"
        ;;                     \"#+title: ${title}\\n#+filetags: :student:\\n\")
        ;;  :unnarrowed t)
        ))

;;; capture-templates.el ends here
"
  "Template content for a new capture-templates.el file.")

(defun my/ensure-capture-templates-file ()
  "Create .orgseq/capture-templates.el with examples if missing."
  (unless (file-exists-p my/capture-templates-file)
    (make-directory (file-name-directory my/capture-templates-file) t)
    (with-temp-file my/capture-templates-file
      (insert my/capture-templates-template))
    (message "org-seq: created %s" my/capture-templates-file)))

(defun my/reload-capture-templates ()
  "Reload user capture templates and merge with built-in defaults."
  (interactive)
  (setq my/user-capture-templates nil)
  (when (file-exists-p my/capture-templates-file)
    (load my/capture-templates-file :noerror :nomessage))
  (setq org-roam-capture-templates
        (append my/default-capture-templates my/user-capture-templates))
  (message "org-seq: %d capture templates active (%d built-in + %d user)"
           (length org-roam-capture-templates)
           (length my/default-capture-templates)
           (length my/user-capture-templates)))

(defun my/edit-capture-templates ()
  "Open the user capture templates file for editing."
  (interactive)
  (my/ensure-capture-templates-file)
  (find-file my/capture-templates-file))

;; Load user templates after org-roam initializes
(with-eval-after-load 'org-roam
  (my/ensure-capture-templates-file)
  (my/reload-capture-templates))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Tag and field quick actions
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
;; Section 5: Dashboard navigation and creation
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Dashboards are read-only query windows in ~/NoteHQ/Roam/dashboards/.
;; They display supertag query results — never used for data entry.
;; Use SPC n v to browse, SPC n m d to create a new one.

(defun my/dashboard-open (name)
  "Open dashboard NAME (without .org) and refresh all dynamic blocks."
  (let ((file (expand-file-name (concat name ".org") my/dashboards-dir)))
    (if (file-exists-p file)
        (progn
          (find-file file)
          (when (fboundp 'org-update-all-dblocks)
            (ignore-errors (org-update-all-dblocks))))
      (message "org-seq: dashboard not found: %s" file))))

(defun my/dashboard-find ()
  "Pick and open a dashboard from ~/NoteHQ/Roam/dashboards/."
  (interactive)
  (make-directory my/dashboards-dir t)
  (let* ((files (directory-files my/dashboards-dir nil "\\.org\\'"))
         (names (mapcar #'file-name-sans-extension files)))
    (if (null names)
        (when (y-or-n-p "No dashboards yet.  Create one? ")
          (call-interactively #'my/dashboard-create))
      (my/dashboard-open
       (completing-read "Dashboard: " names nil t)))))

(defun my/dashboard-create (name)
  "Create a new dashboard NAME in the dashboards directory."
  (interactive "sDashboard name: ")
  (let ((file (expand-file-name (concat name ".org") my/dashboards-dir)))
    (if (file-exists-p file)
        (progn (find-file file) (message "Dashboard already exists"))
      (make-directory my/dashboards-dir t)
      (find-file file)
      (insert (format "#+title: %s\n#+startup: content\n#+description: \n\n" name)
              "* Query\n"
              "#+BEGIN: supertag-query :tag TAG_HERE :columns (title)\n"
              "#+END\n"
              "\n* Notes\n")
      (save-buffer)
      (message "org-seq: created dashboard %s — edit the query block above" name))))

;; Named shortcuts for frequently used dashboards
(defun my/dash-index   () "Open dashboard index."   (interactive) (my/dashboard-open "index"))
(defun my/dash-review  () "Open weekly review."      (interactive) (my/dashboard-open "weekly-review"))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: PARA layer navigation
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
;; Section 7: Incremental NoteHQ directory bootstrap
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/ensure-notehq-structure ()
  "Create NoteHQ directory skeleton if missing.  Idempotent."
  (dolist (dir (list my/roam-dir
                     (expand-file-name "daily/"   my/roam-dir)
                     (expand-file-name "capture/" my/roam-dir)
                     my/dashboards-dir
                     my/outputs-dir
                     my/practice-dir
                     my/library-dir
                     my/archives-dir))
    (make-directory dir t)))

(my/ensure-notehq-structure)

(provide 'init-supertag)
;;; init-supertag.el ends here
