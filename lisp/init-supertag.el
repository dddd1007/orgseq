;;; init-supertag.el --- Tana-style structured tags + PARA navigation + dashboard helpers -*- lexical-binding: t; -*-
;;
;; This module is the USER-FACING side of org-supertag integration. The
;; package itself is installed and minimally configured by init-pkm.el;
;; this file layers on:
;;
;;   - Schema edit/reload                 (my/edit-supertag-schema, SPC n m t/T)
;;   - Capture template management        (my/user-capture-templates merged
;;                                         with my/default-capture-templates
;;                                         from init-roam.el)
;;   - Context-aware quick-action menu    (my/supertag-quick-action, SPC n p p)
;;   - Tana-style node action menu        (my/node-action, SPC n n / , ,)
;;   - Dashboard open/create/find         (my/dashboard-find, my/dashboard-create)
;;   - PARA layer navigation              (my/find-in-outputs, my/ripgrep-notehq)
;;   - NoteHQ directory bootstrap         (my/ensure-notehq-structure, runs on load)
;;
;; Load order:
;;
;;   init-org  ->  init-roam  ->  init-gtd  ->  init-pkm  ->  init-supertag
;;   (paths)       (templates)                   (install)     (this file)
;;
;; The split between init-pkm (bootstrap) and init-supertag (higher-level)
;; exists because init-supertag depends on `my/default-capture-templates'
;; from init-roam.el, which must load before the supertag package can be
;; set up. Keeping the install in init-pkm means "packages that need to
;; be installed early" and "features that need the install plus downstream
;; state" stay separate.

;; Requires: init-org  (NoteHQ path constants)
;; Requires: init-pkm  (org-supertag package installed)
;; Requires: init-roam (my/default-capture-templates)
(defvar my/note-home)
(defvar my/orgseq-dir)
(defvar my/roam-dir)
(defvar my/outputs-dir)
(defvar my/practice-dir)
(defvar my/library-dir)
(defvar my/archives-dir)
(defvar my/dashboards-dir)
(defvar my/schema-file)
(defvar my/capture-templates-file)
(defvar my/default-capture-templates)
(defvar org-roam-capture-templates)

(require 'org)
(require 'org-id)

(declare-function consult-ripgrep "consult")
(declare-function org-roam-capture- "org-roam-capture")
(declare-function org-roam-node-create "org-roam")
(declare-function org-supertag-node-get-tags "org-supertag")
(declare-function org-supertag-tag-add-tag "org-supertag")
(declare-function org-supertag-tag-remove "org-supertag")
(declare-function org-supertag-node-edit-field "org-supertag")
(declare-function org-supertag-node-follow-ref "org-supertag")

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: User file loading helpers
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Physical NoteHQ/PARA path constants live in init-org.el so all modules
;; share one source of truth regardless of load order.

(defun my/load-user-file-safely (file description)
  "Load FILE and report a clear error tagged with DESCRIPTION on failure."
  (condition-case err
      (progn
        (load file nil 'nomessage)
        t)
    (error
     (message "org-seq: failed to load %s from %s: %s" description file err)
     nil)))

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
      (if (my/load-user-file-safely my/schema-file "supertag schema")
        (message "org-seq: supertag schema reloaded from %s" my/schema-file))
    (message "org-seq: schema file not found: %s" my/schema-file)))

(with-eval-after-load 'org-supertag
  (when (file-exists-p my/schema-file)
    (my/load-user-file-safely my/schema-file "supertag schema")))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Capture template management
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Built-in "default" template lives in init-roam.el.
;; User-defined templates (reading, session, student, ...) live in
;; ~/.orgseq/capture-templates.el — a plain elisp file that sets
;; `my/user-capture-templates'.  Edit with SPC n m c, reload with SPC n m C.

(defvar my/user-capture-templates nil
  "User-defined org-roam capture templates loaded from
.orgseq/capture-templates.el.")

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
    (my/load-user-file-safely my/capture-templates-file "capture templates"))
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
         (tags (condition-case err
                   (org-supertag-node-get-tags node-id)
                 (error
                  (message "org-seq: failed to read supertag metadata: %s" err)
                  nil))))
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
;; Section 4.5: Tana-style node action menu
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Tana users expect one fast command menu from any node.  In org-seq the
;; underlying actions live in org-roam, org-supertag, and dashboard helpers;
;; this menu gives them one keyboard-first front door without hiding the
;; native commands.

(defun my/node--ensure-org ()
  "Signal a user error unless the current buffer is an Org buffer."
  (unless (derived-mode-p 'org-mode)
    (user-error "Node actions are available in org-mode buffers only")))

(defun my/node--title ()
  "Return a display title for the current org node or file."
  (or (ignore-errors (org-get-heading t t t t))
      (file-name-base (or buffer-file-name (buffer-name)))))

(defun my/node-copy-id-link ()
  "Copy an id link to the current org node."
  (interactive)
  (my/node--ensure-org)
  (require 'org-id)
  (let* ((id (org-id-get-create))
         (title (my/node--title))
         (link (format "[[id:%s][%s]]" id title)))
    (kill-new link)
    (message "Copied node link: %s" link)))

(defun my/node--supertags ()
  "Return supertags attached to the current node, or nil."
  (when (require 'org-supertag nil t)
    (condition-case err
        (org-supertag-node-get-tags (org-id-get-create))
      (error
       (message "org-seq: failed to read supertags: %s" err)
       nil))))

(defun my/node--capture-template-text (text)
  "Escape TEXT for safe use as org-capture template body."
  (replace-regexp-in-string "%" "%%" text t t))

(defun my/node-capture-region-as-note (title)
  "Capture the active region as a new org-roam note titled TITLE.
The new note includes a source link back to the current node."
  (interactive
   (progn
     (unless (use-region-p)
       (user-error "Select a region first"))
     (list (read-string "New node title: "))))
  (my/node--ensure-org)
  (require 'org-id)
  (require 'org-roam)
  (let* ((text (buffer-substring-no-properties (region-beginning) (region-end)))
         (source-id (org-id-get-create))
         (source-title (my/node--title))
         (source-link (format "[[id:%s][%s]]" source-id source-title))
         (body (concat (my/node--capture-template-text text)
                       "\n\n* Source\n"
                       (my/node--capture-template-text source-link)
                       "\n"))
         (templates
          `(("x" "Extracted region" plain ,body
             :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                                "#+title: ${title}\n")
             :unnarrowed t))))
    (deactivate-mark)
    (org-roam-capture-
     :node (org-roam-node-create :title title)
     :templates templates
     :props '(:finalize find-file))))

(defun my/dashboard-create-for-tag (tag)
  "Create a simple dashboard for supertag TAG, then open it."
  (let ((file (expand-file-name (concat tag ".org") my/dashboards-dir)))
    (make-directory my/dashboards-dir t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (format "#+title: %s\n#+startup: content\n#+description: Nodes tagged %s\n\n"
                        tag tag)
                "* Query\n"
                (format "#+BEGIN: supertag-query :tag %s :columns (title)\n" tag)
                "#+END\n")))
    (my/dashboard-open tag)))

(defun my/node-open-tag-dashboard ()
  "Open or create a dashboard related to one of the current node's tags."
  (interactive)
  (my/node--ensure-org)
  (let* ((tags (my/node--supertags))
         (dashboards (when (file-directory-p my/dashboards-dir)
                       (mapcar #'file-name-sans-extension
                               (directory-files my/dashboards-dir nil "\\.org\\'"))))
         (choices (delete-dups (append tags dashboards))))
    (if (null choices)
        (call-interactively #'my/dashboard-find)
      (let* ((name (completing-read "Dashboard/tag: " choices nil nil))
             (file (expand-file-name (concat name ".org") my/dashboards-dir)))
        (cond
         ((file-exists-p file) (my/dashboard-open name))
         ((y-or-n-p (format "Create dashboard for tag `%s'? " name))
          (my/dashboard-create-for-tag name)))))))

(defun my/node-action ()
  "Open a Tana-style action menu for the current Org node."
  (interactive)
  (my/node--ensure-org)
  (let ((actions
         '(("Supertag quick action" . my/supertag-quick-action)
           ("Add supertag" . org-supertag-tag-add-tag)
           ("Edit supertag fields" . org-supertag-node-edit-field)
           ("Remove supertag" . org-supertag-tag-remove)
           ("Jump linked field" . org-supertag-node-follow-ref)
           ("Insert link to another node" . org-roam-node-insert)
           ("Toggle backlinks panel" . org-roam-buffer-toggle)
           ("Copy node id link" . my/node-copy-id-link)
           ("Open dashboard for tag" . my/node-open-tag-dashboard)
           ("Create new roam note" . org-roam-capture))))
    (when (use-region-p)
      (setq actions
            (append actions
                    '(("Extract region to new note" . my/node-capture-region-as-note)))))
    (let* ((choice (completing-read "Node action: " (mapcar #'car actions) nil t))
           (command (cdr (assoc choice actions))))
      (call-interactively command))))

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
            (condition-case err
                (org-update-all-dblocks)
              (error
               (message "org-seq: dashboard refresh failed: %s" err)))))
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

(add-hook 'after-init-hook
          (lambda ()
            (run-with-idle-timer 0.5 nil #'my/ensure-notehq-structure)))

(provide 'init-supertag)
;;; init-supertag.el ends here
