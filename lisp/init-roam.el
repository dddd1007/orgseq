;;; init-roam.el --- org-roam PKM engine + org-node acceleration -*- lexical-binding: t; -*-

;; Requires: init-org (my/note-home, my/roam-dir)
(defvar my/note-home)  ; forward-declare from init-org
(defvar my/roam-dir)   ; forward-declare from init-org
(defvar my/default-capture-templates)
(defvar org-roam-dailies-directory)
(defvar org-roam-dailies-capture-templates)
(defvar org-mem-roamy-do-overwrite-real-db)

(defun my/org-roam-dailies--file-for-date (time)
  "Return the org-seq daily note file path for TIME."
  (expand-file-name
   (format-time-string "%Y-%m-%d.org" time)
   (expand-file-name (if (boundp 'org-roam-dailies-directory)
                         org-roam-dailies-directory
                       "daily/")
                     my/roam-dir)))

(defun my/org-roam-dailies-open-date (time)
  "Open the daily note for TIME without entering org-roam capture."
  (let* ((file (my/org-roam-dailies--file-for-date time))
         (title (format-time-string "%Y-%m-%d" time)))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (format "#+title: %s\n#+filetags: :daily:\n\n" title))))
    (find-file file)))

(defun my/org-roam-dailies-open-today ()
  "Open today's daily note directly, bypassing org-roam capture."
  (interactive)
  (my/org-roam-dailies-open-date (current-time)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: org-roam — core PKM graph database
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; org-roam provides the node/link/backlink data model and capture system.
;; Its expensive SQLite sync is offloaded to org-mem (see Section 2).

(use-package org-roam
  :demand t
  :custom
  (org-roam-directory my/roam-dir)
  (org-roam-db-location (expand-file-name "org-roam.db" my/roam-dir))
  (org-roam-completion-everywhere t)
  (org-roam-node-display-template "${type:12} ${title:*} ${backlinkscount:6} ${tags:10}")
  ;; Suppress GC during DB-intensive operations (official recommendation)
  (org-roam-db-gc-threshold most-positive-fixnum)
  ;; Skip roam:-to-id: link replacement on save (we never use roam: links)
  (org-roam-link-auto-replace nil)
  ;; Disable org-roam's per-save DB writes; org-mem handles this faster.
  (org-roam-db-update-on-save nil)

  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n F" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n j" . my/org-roam-dailies-open-today))

  :config
  ;; Directory creation handled by my/ensure-notehq-structure (init-supertag)
  (make-directory org-roam-directory t)

  ;; ---- Node display: show subdirectory type + backlink count ----
  (cl-defmethod org-roam-node-type ((node org-roam-node))
    "Return the subdirectory of NODE relative to `org-roam-directory'."
    (let* ((file (org-roam-node-file node))
           (relative (and file (file-relative-name file org-roam-directory)))
           (directory (and relative (file-name-directory relative))))
      (if directory
          (file-name-nondirectory (directory-file-name directory))
        "")))

  (cl-defmethod org-roam-node-backlinkscount ((node org-roam-node))
    "Return the backlink count of NODE as a bracketed string."
    (let ((count (caar (org-roam-db-query
                        [:select (funcall count source)
                                 :from links
                                 :where (= dest $s1)
                                 :and (= type "id")]
                        (org-roam-node-id node)))))
      (format "[%d]" (or count 0))))

  (add-to-list 'display-buffer-alist
               '("\\*org-roam\\*"
                 (display-buffer-in-direction)
                 (direction . right)
                 (window-width . 0.33)
                 (window-height . fit-window-to-buffer)))

  (setq org-roam-db-node-include-function
        (lambda ()
          (not (member "ATTACH" (org-get-tags)))))

  ;; Backlink buffer: show backlinks + reflinks only (unlinked-refs is slow)
  (setq org-roam-mode-sections
        (list #'org-roam-backlinks-section
              #'org-roam-reflinks-section))

  (setq org-id-method 'ts
        org-id-ts-format "%Y%m%dT%H%M%S")

  ;; Prefer fast file finders over slow `find' (Doom)
  (setq org-roam-list-files-commands '(fd fdfind rg find))

  ;; Use ID links when inserting from roam files (Doom recommendation)
  (add-hook 'org-roam-find-file-hook
            (lambda () (setq-local org-id-link-to-org-use-id 'create-if-interactive)))

  ;; ---- Capture templates ----
  ;; Built-in default only.  User templates are appended from
  ;; ~/.orgseq/capture-templates.el by init-supertag.el (SPC n m c to edit).
  (setq my/default-capture-templates
        '(("d" "Default" plain "%?"
           :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n")
           :unnarrowed t)))
  (setq org-roam-capture-templates my/default-capture-templates)

  ;; ---- Dailies ----
  (setq org-roam-dailies-directory "daily/")

  (setq org-roam-dailies-capture-templates
        '(("d" "Default" entry "* %<%H:%M> %?"
           :target (file+head "%<%Y-%m-%d>.org"
                              "#+title: %<%Y-%m-%d>\n#+filetags: :daily:\n"))
          ("t" "Task" entry "* TODO %?\nSCHEDULED: %t\n"
           :target (file+head+olp "%<%Y-%m-%d>.org"
                                  "#+title: %<%Y-%m-%d>\n"
                                  ("Tasks")))
          ("j" "Journal" entry "* %<%H:%M> Journal\n%?\n"
           :target (file+head+olp "%<%Y-%m-%d>.org"
                                  "#+title: %<%Y-%m-%d>\n"
                                  ("Journal")))))

  ;; autosync-mode still handles org-id hooks; DB writes are off (see above).
  (org-roam-db-autosync-mode)

  ;; Soft-wrap lines in the backlinks buffer (Doom)
  (add-hook 'org-roam-mode-hook #'visual-line-mode)

  ;; Doom-derived Evil fixes (loaded together when evil is available):
  ;;   1. org-roam-node-insert places links *before* whitespace in normal mode
  ;;   2. magit-section-mode-map overrides Evil keys in org-roam buffer
  (with-eval-after-load 'evil
    (define-advice org-roam-node-insert (:around (fn &rest args) my/evil-fix-insert-position)
      "Insert link after whitespace/EOL in evil normal mode."
      (if (and (bound-and-true-p evil-local-mode)
               (not (evil-insert-state-p))
               (or (looking-at-p "[[:blank:]]")
                   (eolp)))
          (evil-with-state 'insert
            (unless (eolp) (forward-char))
            (when (eolp) (insert " "))
            (apply fn args))
        (apply fn args)))

    (add-hook 'org-roam-mode-hook
              (lambda () (set-keymap-parent org-roam-mode-map nil))))

  ;; Doom fix: org-roam-node-read candidate width is wrong with vertico.
  ;; See org-roam/org-roam#2066.
  (with-eval-after-load 'vertico
    (define-advice org-roam-node-read--to-candidate (:around (fn &rest args) my/fix-vertico-width)
      "Fix completion candidate width for vertico."
      (cl-letf* ((orig-format (symbol-function 'org-roam-node--format-entry))
                 ((symbol-function 'org-roam-node--format-entry)
                  (lambda (template node &optional width)
                    (funcall orig-format template node
                             (if (bound-and-true-p vertico-mode)
                                 (if (minibufferp)
                                     (window-width)
                                   (1- (frame-width)))
                               width)))))
        (apply fn args)))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: org-node + org-mem — high-performance indexing layer
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; org-mem: async file scanner, builds hash tables + SQLite in ~2s for 3000 nodes.
;; org-node: builds on org-mem for node search, backlinks, and org-roam acceleration.
;;
;; Performance comparison (meedstrom's 3000-node benchmark):
;;   org-roam DB sync:  2m 48s  →  org-mem:   2s
;;   save (400 nodes):  5-10s   →  org-node:  instant
;;   20 backlinks:      5-10s   →  org-node:  instant
;;   minibuffer open:   1-3s    →  org-node:  instant

(defun my/byte-compile-library-if-needed (library)
  "Byte-compile LIBRARY when its .elc is missing or stale.

This is used for org-mem's hot-path dependencies so startup does not
fall back to interpreted code and trigger performance warnings.  Any
failure is downgraded to a warning so PKM startup still succeeds."
  (let* ((source (locate-library library))
         (dest (and source (byte-compile-dest-file source))))
    (when (and source
               dest
               (string-match-p "\\.el\\'" source)
               (or (not (file-exists-p dest))
                   (file-newer-than-file-p source dest)))
      (condition-case err
          (progn
            (require 'bytecomp)
            (byte-recompile-file source nil 0)
            t)
        (error
         (message "WARNING org-seq: failed to byte-compile %s: %s" library err)
         nil)))))

(defun my/ensure-org-mem-compiled ()
  "Compile org-mem hot-path libraries before loading org-node.

org-mem warns loudly when it or truename-cache run interpreted because
path normalization becomes much slower.  Compile the dependency chain
up front so first startup does not spam avoidable warnings."
  (dolist (library '("truename-cache" "org-mem" "org-node"))
    (my/byte-compile-library-if-needed library)))

(use-package org-node
  :after org-roam
  :demand t
  :init
  (my/ensure-org-mem-compiled)
  :custom
  ;; Delegate node creation to org-roam's capture system
  (org-node-creation-fn #'org-node-new-via-roam-capture)
  ;; Match org-roam's default slug style
  (org-node-slug-fn #'org-node-slugify-like-roam-default)
  ;; Match existing filename timestamp prefix format
  (org-node-file-timestamp-format "%Y%m%dT%H%M%S-")

  :config
  ;; Scope org-mem to the actionable PKM layers used by org-roam and GTD.
  (setq org-mem-watch-dirs
        (list my/roam-dir
              (expand-file-name "10_Outputs/" my/note-home)
              (expand-file-name "20_Practice/" my/note-home)))

  ;; Write to org-roam's real DB so org-roam-ui and other extensions work
  (setq org-mem-roamy-do-overwrite-real-db t)

  (org-node-cache-mode 1)
  (org-node-roam-accelerator-mode 1)
  (org-mem-roamy-db-mode 1))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Search and visualization
;; ═══════════════════════════════════════════════════════════════════════════

;; Deft: fast incremental note search across the whole NoteHQ vault.
;; Keep project/content search on Consult; Deft is the primary UI for note
;; discovery across Org + Markdown notes under ~/NoteHQ/.
(use-package deft
  :after org-roam
  :commands (deft deft-find-file deft-refresh)
  :bind (("C-c n f" . deft))
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

(defun my/org-roam-rg-search ()
  "Search org-roam directory with consult-ripgrep."
  (interactive)
  (consult-ripgrep org-roam-directory))

;; consult-org-roam: async completion + live preview for org-roam
(use-package consult-org-roam
  :after org-roam
  :custom
  (consult-org-roam-grep-func #'consult-ripgrep)
  (consult-org-roam-buffer-narrow-key ?r)
  (consult-org-roam-buffer-after-buffers t)
  :config
  ;; Defer preview to manual trigger — avoids opening files during fast scrolling
  (consult-customize
   consult-org-roam-forward-links :preview-key "M-."
   consult-org-roam-backlinks     :preview-key "M-.")
  (consult-org-roam-mode 1))

;; org-roam-ui: browser-based graph visualization.
;; DB is maintained by org-mem-roamy-db-mode (Section 2).
(use-package org-roam-ui
  :after org-roam
  :commands org-roam-ui-mode
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t
        org-roam-ui-open-on-start nil))

(provide 'init-roam)
;;; init-roam.el ends here
