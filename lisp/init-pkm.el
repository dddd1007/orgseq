;;; init-pkm.el --- PKM support packages: org-supertag bootstrap + org-transclusion + org-ql -*- lexical-binding: t; -*-
;;
;; This module is the "support packages" layer of the PKM stack. It
;; handles three independent things that share one property: each is a
;; pure package installation with minimal configuration.
;;
;;   1. `org-supertag' — BOOTSTRAP INSTALL ONLY.
;;      Installs the package from GitHub and sets two baseline options
;;      (sync directory, AI bridge). All higher-level supertag logic
;;      (schema editing, dashboards, PARA navigation, capture-template
;;      management) lives in `lisp/init-supertag.el' which loads right
;;      after this module. The split exists because init-supertag.el
;;      needs `my/default-capture-templates' from init-roam.el, which
;;      forces this load order:
;;
;;          init-org -> init-roam -> init-gtd -> init-pkm -> init-supertag
;;
;;   2. `org-transclusion' — enables live `#+transclude:' blocks.
;;      Stand-alone, no org-seq-specific config.
;;
;;   3. `org-ql' — SQL-like query language for org; used by init-gtd's
;;      dashboard for live counts.
;;
;; Naming note: "pkm" here means "pkm support packages", not "PKM hub".
;; The actual PKM feature surface is split across four modules:
;;   init-roam       graph layer (org-roam + org-node + org-mem)
;;   init-pkm        structured-data + transclusion + query package install
;;   init-supertag   supertag higher-level UI and helpers
;;   init-gtd        task management on top of the agenda
;;
;; If you are looking for "where does the supertag schema editing
;; function live?" the answer is init-supertag.el, not here.

(require 'subr-x)

(defvar org-supertag-bridge-enable-ai)

;; Requires: init-org (my/roam-dir)
;; Requires: init-packages (Git package bootstrap and source metadata)
(defvar my/roam-dir)  ; forward-declare from init-org

(declare-function my/vc-package-ensure "init-packages" (package))
(declare-function supertag-save-store "supertag-core-store" ())
(declare-function my/vc-package-install-command "init-packages" (package))
(declare-function my/vc-package-install-error "init-packages" (package))

(defvar my/supertag-sync-timer nil
  "Idle timer used to debounce post-capture supertag syncs.")

(defun my/supertag-schedule-sync ()
  "Debounce `supertag-sync-check-now' after org-roam capture finalization."
  (when my/supertag-sync-timer
    (cancel-timer my/supertag-sync-timer))
  (setq my/supertag-sync-timer
        (run-with-idle-timer
         0.5 nil
         (lambda ()
           (setq my/supertag-sync-timer nil)
           (when (fboundp 'supertag-sync-check-now)
             (supertag-sync-check-now))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: org-supertag — bootstrap install + baseline config
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; org-supertag (v5.8+, Tana-style tags with typed fields) is not on
;; MELPA; init-packages bootstraps it from the registered Git source. This
;; section does ONLY the install and minimal config.  Everything
;; user-facing (schema editing, SPC n p * keys, dashboards, etc.) is
;; in init-supertag.el.
;;
;; Three-layer PKM architecture (as a reminder):
;;   org-roam      = graph layer       (nodes, links, backlinks, capture)
;;   org-node/mem  = performance layer (fast indexing, async DB sync)
;;   org-supertag  = data layer        (structured tags, fields, queries)

;; ht: hash-table library required by org-supertag
(use-package ht :ensure t)

(defcustom my/supertag-compat-backup-directory
  (expand-file-name ".cache/org-seq/compat-backups/" user-emacs-directory)
  "Directory for backups made before org-supertag compatibility patches."
  :type 'directory
  :group 'org-seq)

(defconst my/supertag--compat-version "5.8.1")
(defconst my/supertag--compat-commit
  "7e98ed9ad01f985881afced0fdc4a1ef3fedfa2a")

(defconst my/supertag--compat-specs
  '((:file "supertag-services-capture.el"
     :original-hash "a25cf03a81389b72eecfe804cc709e6a74961263"
     :patched-hash "6cc1a20017f1d025035f447b54325b07114eb176"
     :replacements
     (("(mapconcat (lambda (t) (concat \"#\" t))"
       . "(mapconcat (lambda (tag) (concat \"#\" tag))")))
    (:file "supertag-view-framework.el"
     :original-hash "69867c7583b0e5759ac3874675721b5e4bc6f077"
     :patched-hash "ef27071bf7e3dc1a7946ea4b9996df8cfbab3a77"
     :replacements
     (("(list :type :list :items (\"Task A\" \"Task B\" \"Task C\"))"
       . "(list :type :list :items (list \"Task A\" \"Task B\" \"Task C\"))")))
    (:file "supertag-view-effort-distribution.el"
     :original-hash "e03ff3ae1a4afbd6bb306983809786d0567aa3f1"
     :patched-hash "831bad737a3ee5be53f37229cea4203cf94cc0a7"
     :replacements
     (("        (dolist (t node-tags)\n          (when (and (stringp t) (not (equal t tag-name)))\n            (let ((entry (assoc t tag-groups)))\n              (if entry\n                  (setcdr entry (+ (cdr entry) effort))\n                (push (cons t effort) tag-groups)))))))"
       . "        (dolist (tag node-tags)\n          (when (and (stringp tag) (not (equal tag tag-name)))\n            (let ((entry (assoc tag tag-groups)))\n              (if entry\n                  (setcdr entry (+ (cdr entry) effort))\n                (push (cons tag effort) tag-groups)))))))"))))
  "Exact source states and replacements for the supported upstream revision.")

(defun my/supertag--git-blob-sha1 (file)
  "Return FILE's Git blob SHA-1 after normalizing CRLF to LF."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (goto-char (point-min))
    (while (search-forward "\r\n" nil t)
      (replace-match "\n" t t))
    (let* ((content (buffer-string))
           (header (encode-coding-string
                    (format "blob %d%c" (string-bytes content) 0)
                    'binary)))
      (secure-hash 'sha1 (concat header content)))))

(defun my/supertag--read-match (file regexp)
  "Return the first REGEXP capture from FILE, or nil."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward regexp nil t)
        (string-trim (match-string-no-properties 1))))))

(defun my/supertag--metadata (directory)
  "Return org-supertag version and commit metadata for DIRECTORY."
  (list
   :version
   (my/supertag--read-match
    (expand-file-name "org-supertag.el" directory)
    "^;; Version:[ \\t]*\\(.+\\)$")
   :commit
   (my/supertag--read-match
    (expand-file-name "org-supertag-pkg.el" directory)
    ":commit[ \\t]+\"\\([[:xdigit:]]+\\)\"")))

(defun my/supertag--compat-directory ()
  "Return the installed org-supertag directory, or nil."
  (when-let ((main (locate-library "org-supertag")))
    (file-name-directory main)))

(defun my/supertag--supported-metadata-p (metadata)
  "Return non-nil when METADATA is the explicitly supported upstream source."
  (and (equal (plist-get metadata :version) my/supertag--compat-version)
       (equal (plist-get metadata :commit) my/supertag--compat-commit)))

(defun my/supertag--compat-backup-root ()
  "Return the revision-specific compatibility backup directory."
  (expand-file-name
   (format "org-supertag-%s-%s/"
           my/supertag--compat-version
           (substring my/supertag--compat-commit
                      0 (min 12 (length my/supertag--compat-commit))))
   my/supertag-compat-backup-directory))

(defun my/supertag--rewrite-atomically (source target replacements)
  "Write SOURCE to TARGET atomically after literal REPLACEMENTS."
  (make-directory (file-name-directory target) t)
  (let ((temp (make-temp-file
               (expand-file-name ".org-seq-supertag-"
                                 (file-name-directory target))))
        (modes (file-modes source)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert-file-contents source)
            (let ((coding buffer-file-coding-system))
              (dolist (replacement replacements)
                (goto-char (point-min))
                (unless (search-forward (car replacement) nil t)
                  (error "Expected compatibility source not found in %s"
                         source))
                (replace-match (cdr replacement) t t))
              (let ((coding-system-for-write coding))
                (write-region (point-min) (point-max) temp nil 'silent))))
          (when modes
            (set-file-modes temp modes))
          (rename-file temp target t)
          (setq temp nil))
      (when (and temp (file-exists-p temp))
        (delete-file temp)))))

(defun my/supertag--copy-atomically (source target)
  "Copy SOURCE to TARGET through a same-directory temporary file."
  (make-directory (file-name-directory target) t)
  (let ((temp (make-temp-file
               (expand-file-name ".org-seq-supertag-"
                                 (file-name-directory target)))))
    (unwind-protect
        (progn
          (copy-file source temp t t nil t)
          (rename-file temp target t)
          (setq temp nil))
      (when (and temp (file-exists-p temp))
        (delete-file temp)))))

(defun my/supertag--classify-sources (directory)
  "Return compatibility source states for DIRECTORY."
  (mapcar
   (lambda (spec)
     (let* ((file (expand-file-name (plist-get spec :file) directory))
            (hash (and (file-readable-p file)
                       (my/supertag--git-blob-sha1 file)))
            (state (cond
                    ((equal hash (plist-get spec :original-hash)) 'original)
                    ((equal hash (plist-get spec :patched-hash)) 'patched)
                    (t 'unknown))))
       (cons spec state)))
   my/supertag--compat-specs))

(defun my/supertag--known-sources-p (states)
  "Return non-nil when every entry in STATES is recognized."
  (let ((known t))
    (dolist (entry states known)
      (when (eq (cdr entry) 'unknown)
        (setq known nil)))))

(defun my/supertag--ensure-backups (directory states)
  "Create and verify compatibility backups for DIRECTORY and STATES."
  (let ((backup-root (my/supertag--compat-backup-root)))
    (dolist (entry states)
      (let* ((spec (car entry))
             (state (cdr entry))
             (source (expand-file-name (plist-get spec :file) directory))
             (backup (expand-file-name (plist-get spec :file) backup-root)))
        (unless (file-exists-p backup)
          (pcase state
            ('original
             (my/supertag--copy-atomically source backup))
            ('patched
             (my/supertag--rewrite-atomically
              source backup
              (mapcar (lambda (replacement)
                        (cons (cdr replacement) (car replacement)))
                      (plist-get spec :replacements))))))
        (unless (and (file-readable-p backup)
                     (equal (my/supertag--git-blob-sha1 backup)
                            (plist-get spec :original-hash)))
          (error "Invalid org-supertag compatibility backup: %s" backup))))))

(defun my/supertag-apply-compat-patches ()
  "Apply the governed org-supertag 5.8.1 Emacs 30 compatibility patch.
Return `patched', `current', `missing', `unsupported', or `error'."
  (interactive)
  (if-let ((directory (my/supertag--compat-directory)))
      (let* ((metadata (my/supertag--metadata directory))
             (states (my/supertag--classify-sources directory)))
        (cond
         ((not (my/supertag--supported-metadata-p metadata))
          (message "WARNING org-seq: refusing org-supertag compatibility patch for version %s commit %s"
                   (or (plist-get metadata :version) "unknown")
                   (or (plist-get metadata :commit) "unknown"))
          'unsupported)
         ((not (my/supertag--known-sources-p states))
          (message "WARNING org-seq: refusing org-supertag compatibility patch because source hashes drifted")
          'unsupported)
         (t
          (condition-case err
              (let ((changed nil))
                (my/supertag--ensure-backups directory states)
                (dolist (entry states)
                  (when (eq (cdr entry) 'original)
                    (let* ((spec (car entry))
                           (file (expand-file-name
                                  (plist-get spec :file) directory)))
                      (my/supertag--rewrite-atomically
                       file file (plist-get spec :replacements))
                      (let ((elc (concat file "c")))
                        (when (file-exists-p elc)
                          (delete-file elc)))
                      (setq changed t))))
                (when changed
                  (message "org-seq: applied governed org-supertag Emacs 30 compatibility patch"))
                (if changed 'patched 'current))
            (error
             (message "WARNING org-seq: org-supertag compatibility patch failed: %s"
                      (error-message-string err))
             'error)))))
    'missing))

(defun my/supertag-rollback-compat-patches ()
  "Restore org-supertag sources from the governed compatibility backup."
  (interactive)
  (if-let ((directory (my/supertag--compat-directory)))
      (let* ((metadata (my/supertag--metadata directory))
             (states (my/supertag--classify-sources directory))
             (backup-root (my/supertag--compat-backup-root)))
        (cond
         ((not (my/supertag--supported-metadata-p metadata)) 'unsupported)
         ((not (my/supertag--known-sources-p states)) 'unsupported)
         (t
          (condition-case err
              (progn
                (dolist (spec my/supertag--compat-specs)
                  (let ((backup (expand-file-name
                                 (plist-get spec :file) backup-root)))
                    (unless (and (file-readable-p backup)
                                 (equal (my/supertag--git-blob-sha1 backup)
                                        (plist-get spec :original-hash)))
                      (error "Missing or invalid compatibility backup: %s"
                             backup))))
                (dolist (spec my/supertag--compat-specs)
                  (let* ((file (expand-file-name
                                (plist-get spec :file) directory))
                         (backup (expand-file-name
                                  (plist-get spec :file) backup-root)))
                    (my/supertag--copy-atomically backup file)
                    (let ((elc (concat file "c")))
                      (when (file-exists-p elc)
                        (delete-file elc)))))
                (message "org-seq: restored org-supertag sources from compatibility backup")
                'restored)
            (error
             (message "WARNING org-seq: org-supertag compatibility rollback failed: %s"
                      (error-message-string err))
             'error)))))
    'missing))

;; Bootstrap source metadata and error handling live in init-packages.
(my/vc-package-ensure 'org-supertag)

(unless noninteractive
  (my/supertag-apply-compat-patches))

;; WORKAROUND for org-supertag recursive load: preload the low-level
;; modules that the top-level org-supertag.el requires, so they are
;; already in memory when the main file loads.
(dolist (lib '("supertag-core-notify"
               "supertag-core-store"
               "supertag-ops-node"
               "supertag-ui-search"))
  (when (locate-library lib)
    (condition-case err
        (require (intern lib) nil t)
      (error (message "org-seq: preloading %s failed: %s" lib err)))))

(use-package org-supertag
  :if (locate-library "org-supertag")
  :after org
  :commands (org-supertag-tag-add-tag org-supertag-tag-remove
             org-supertag-node-edit-field org-supertag-node-follow-ref
             org-supertag-node-list-fields org-supertag-node-get-tags
             supertag-add-tag supertag-view-node supertag-search
             supertag-view-kanban supertag-capture supertag-create-node
             supertag-set-tag-parent supertag-sync-full-initialize
             supertag-sync-check-now supertag-sync-status
             supertag-convert-properties-to-field
             supertag-capture-enrich-node-at-point)
  :config
  (setq org-supertag-sync-directories (list my/roam-dir))
  (setq org-supertag-bridge-enable-ai t))

(with-eval-after-load 'org-supertag
  (when noninteractive
    (remove-hook 'kill-emacs-hook #'supertag-save-store)))

(unless (locate-library "org-supertag")
  (run-with-idle-timer 2 nil
    (lambda ()
      (message "WARNING org-seq: org-supertag not found. %sRun %s"
               (if (my/vc-package-install-error 'org-supertag)
                   (format "Last install error: %s. "
                           (my/vc-package-install-error 'org-supertag))
                 "")
               (my/vc-package-install-command 'org-supertag)))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Capture bridge — org-roam → org-supertag
;; ═══════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'org-roam
  (add-hook 'org-roam-capture-after-finalize-hook #'my/supertag-schedule-sync))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: org-transclusion — live content embedding
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org-transclusion
  :after org
  :bind (("C-c t a" . org-transclusion-add)
         ("C-c t t" . org-transclusion-mode)
         ("C-c t m" . org-transclusion-transient-menu))
  :config
  (add-to-list 'org-transclusion-extensions 'org-transclusion-indent-mode)
  (require 'org-transclusion-indent-mode)
  (when (boundp 'org-roam-db-extra-links-exclude-keys)
    (setq org-roam-db-extra-links-exclude-keys
          (remove "transclude" org-roam-db-extra-links-exclude-keys))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: org-ql — SQL-like query language for org
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org-ql
  :after org
  :commands (org-ql-search org-ql-view org-ql-select))

(provide 'init-pkm)
;;; init-pkm.el ends here
