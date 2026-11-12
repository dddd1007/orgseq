;;; init-roam.el --- Optional org-roam integration -*- lexical-binding: t; -*-
;;
;; Optional module: listed in `my/init-optional-modules' and loaded only
;; when `my/init-enabled-optional-modules' (user/modules.el) names it.
;;
;; org-seq does not need org-roam: notes, capture, Daily, node find,
;; links, backlinks and views run on the kernel index.  Enabling this
;; module adds org-roam on top of the same Org files:
;;
;;   org-roam          its node buffer, dailies capture and alias/ref commands,
;;                     with org-seq's capture templates
;;   org-node/org-mem  fast caching for org-roam, writing org-roam's own
;;                     database (org-roam.db, separate from the kernel index)
;;   consult-org-roam  consult-based link and backlink pickers
;;   org-roam-ui       the browser graph view
;;
;; The kernel index stays the source for every org-seq command; nothing
;; here writes to it or replaces an org-seq command.

;; Requires: init-org (my/note-home, my/roam-dir, PARA paths)
;; Requires: init-capture (capture templates, Daily location)
(defvar my/note-home)    ; forward-declare from init-org
(defvar my/roam-dir)     ; forward-declare from init-org
(defvar my/outputs-dir)  ; forward-declare from init-org
(defvar my/practice-dir) ; forward-declare from init-org
(defvar my/capture-templates-changed-hook)
(defvar org-roam-capture-templates)
(defvar org-roam-dailies-directory)
(defvar org-roam-dailies-capture-templates)
(defvar org-mem-roamy-do-overwrite-real-db)

(declare-function my/capture-usable-templates "init-capture" (&optional templates))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: org-roam — core PKM graph database
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; org-roam keeps its own database of the same Org files.  Its SQLite sync
;; is offloaded to org-mem (see Section 2).

(defun my/roam-sync-capture-templates ()
  "Give org-roam the capture templates org-seq itself offers."
  (setq org-roam-capture-templates (my/capture-usable-templates)))

;; ---- Doom-derived advice helpers ----
;;
;; Plain top-level defuns rather than `define-advice' forms nested inside
;; `with-eval-after-load'.  A nested definition is invisible to the byte
;; compiler, which then cannot check the `advice-add' call sites below, and
;; the generated advice name is awkward to remove by hand.
;; Native compilation runs in a fresh Emacs; this macro must be available
;; while compiling the advice, not merely when Evil loads at runtime.
(eval-when-compile (require 'evil nil t))
(declare-function org-get-tags "org" (&optional pos local))
(declare-function org-mem-roamy-db-mode "org-mem-roamy" (&optional arg))
(declare-function evil-insert-state-p "evil-states" (&optional state))
(declare-function org-roam-backlinks-section "org-roam-mode" (node))
(declare-function org-roam-db-query "org-roam-db" (sql &rest args))
(declare-function org-roam-node--format-entry "org-roam-node"
                  (template node &optional width))
(declare-function org-roam-reflinks-section "org-roam-mode" (node))

(defun my/roam--evil-insert-position (fn &rest args)
  "Around advice for `org-roam-node-insert', calling FN with ARGS.
Insert the link after surrounding whitespace or at end of line while evil
is in normal state, which is where a user expects the link to land."
  (if (and (bound-and-true-p evil-local-mode)
           (not (evil-insert-state-p))
           (or (looking-at-p "[[:blank:]]")
               (eolp)))
      (evil-with-state 'insert
        (unless (eolp) (forward-char))
        (when (eolp) (insert " "))
        (apply fn args))
    (apply fn args)))

(defun my/roam--vertico-candidate-width (fn &rest args)
  "Around advice for `org-roam-node-read--to-candidate' (FN with ARGS).
Correct the completion candidate width under vertico.
See URL `https://github.com/org-roam/org-roam/issues/2066'."
  (cl-letf* ((orig-format (symbol-function 'org-roam-node--format-entry))
             ((symbol-function 'org-roam-node--format-entry)
              (lambda (template node &optional width)
                (funcall orig-format template node
                         (if (bound-and-true-p vertico-mode)
                             (if (minibufferp)
                                 (window-width)
                               (1- (frame-width)))
                           width)))))
    (apply fn args)))

;; NOTE(startup): Warm org-roam after the first frame so graph commands and
;; background accelerators reach a predictable ready state.
(use-package org-roam
  :defer 1
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

  :bind (("C-c n L" . org-roam-buffer-toggle))

  :config
  ;; Directory creation handled by my/ensure-notehq-structure (init-nodes)
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

  (setq org-roam-db-node-include-function
        (lambda ()
          (not (member "ATTACH" (org-get-tags)))))

  ;; Backlink buffer: show backlinks + reflinks only (unlinked-refs is slow)
  (setq org-roam-mode-sections
        (list #'org-roam-backlinks-section
              #'org-roam-reflinks-section))

  ;; Prefer fast file finders over slow `find' (Doom)
  (setq org-roam-list-files-commands '(fd fdfind rg find))

  ;; Use ID links when inserting from roam files (Doom recommendation)
  (add-hook 'org-roam-find-file-hook
            (lambda () (setq-local org-id-link-to-org-use-id 'create-if-interactive)))

  ;; ---- Capture templates ----
  ;; The same templates as `my/note-capture' (init-capture): defaults,
  ;; type templates from types.org and .orgseq/capture-templates.el.
  (my/roam-sync-capture-templates)
  (add-hook 'my/capture-templates-changed-hook #'my/roam-sync-capture-templates)

  ;; ---- Dailies ----
  ;; The Daily location of org-seq (`my/daily-dir'): daily/ under the roam
  ;; directory.
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
    (advice-add 'org-roam-node-insert :around
                #'my/roam--evil-insert-position)

    (add-hook 'org-roam-mode-hook
              (lambda () (set-keymap-parent org-roam-mode-map nil))))

  ;; Doom fix: org-roam-node-read candidate width is wrong with vertico.
  ;; See org-roam/org-roam#2066.
  (with-eval-after-load 'vertico
    (advice-add 'org-roam-node-read--to-candidate :around
                #'my/roam--vertico-candidate-width)))

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

(defcustom my/org-node-startup-delay 2.0
  "Idle delay before loading the org-node/org-mem acceleration layer."
  :type 'number
  :group 'org-seq)

(defun my/load-org-node-later ()
  "Compile and load org-node shortly after startup settles."
  (run-with-idle-timer
   my/org-node-startup-delay nil
   (lambda ()
     (my/ensure-org-mem-compiled)
     (require 'org-node nil t))))

(use-package org-node
  :after org-roam
  :defer t
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
        (list my/roam-dir my/outputs-dir my/practice-dir))

  ;; Write to org-roam's real DB so org-roam-ui and other extensions work
  (setq org-mem-roamy-do-overwrite-real-db t)

  ;; Candidate caching and the Roam DB writer do not start the scanner.
  (org-mem-updater-mode 1)
  (org-node-cache-mode 1)
  (org-node-roam-accelerator-mode 1)
  (org-mem-roamy-db-mode 1))

(add-hook 'emacs-startup-hook #'my/load-org-node-later)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Search and visualization (org-roam specific)
;; ═══════════════════════════════════════════════════════════════════════════

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
