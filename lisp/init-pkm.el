;;; init-pkm.el --- PKM extensions: org-supertag + org-transclusion + org-ql -*- lexical-binding: t; -*-

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: org-supertag — structured data engine (Tana-style)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Core PKM engine: turns #tags into database tables with typed fields.
;; Provides structured queries, table views, kanban boards, and automation.
;; Uses org-id for node identity (compatible with org-roam graph).
;;
;; Three-layer PKM architecture:
;;   org-roam      = graph layer      (nodes, links, backlinks, capture)
;;   org-node      = performance layer (fast indexing, async DB sync)
;;   org-supertag  = data layer       (structured tags, fields, queries, views)

;; ht: hash-table library required by org-supertag
(use-package ht :ensure t)

;; Bootstrap org-supertag from GitHub (not on MELPA).
(when (< emacs-major-version 30)
  (unless (package-installed-p 'org-supertag)
    (if (fboundp 'package-vc-install)
        (condition-case err
            (package-vc-install "https://github.com/yibie/org-supertag")
          (error
           (message "⚠️ org-seq: failed to install org-supertag: %s" err)))
      (message "⚠️ org-seq: package-vc-install unavailable, skip org-supertag."))))

;; Lazy-load org-supertag: commands are available immediately via autoload,
;; sync service starts after 2s idle (safe auto-start with retry).
(if (>= emacs-major-version 30)
    (use-package org-supertag
      :after org
      :vc (:url "https://github.com/yibie/org-supertag" :rev :newest)
      :commands (supertag-add-tag supertag-view-node supertag-search
                 supertag-view-kanban supertag-capture supertag-create-node
                 supertag-set-tag-parent supertag-sync-full-initialize
                 supertag-sync-check-now supertag-sync-status
                 supertag-convert-properties-to-field
                 supertag-capture-enrich-node-at-point)
      :config
      (setq org-supertag-sync-directories
            (list (file-truename "~/NoteHQ/Roam/")))
      (setq org-supertag-bridge-enable-ai t))
  (use-package org-supertag
    :after org
    :if (locate-library "org-supertag")
    :commands (supertag-add-tag supertag-view-node supertag-search
               supertag-view-kanban supertag-capture supertag-create-node
               supertag-set-tag-parent supertag-sync-full-initialize
               supertag-sync-check-now supertag-sync-status
               supertag-convert-properties-to-field
               supertag-capture-enrich-node-at-point)
    :config
    (setq org-supertag-sync-directories
          (list (file-truename "~/NoteHQ/Roam/")))
    (setq org-supertag-bridge-enable-ai t)))

;; Deferred init: ensure org-supertag loads and sync starts after startup.
(run-with-idle-timer 2 nil
  (lambda ()
    (when (and (locate-library "org-supertag")
               (not (featurep 'org-supertag)))
      (require 'org-supertag nil t))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Capture bridge — org-roam → org-supertag
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; After org-roam capture finalize, trigger org-supertag sync so the new
;; node is immediately available in supertag queries.

(with-eval-after-load 'org-roam
  (add-hook 'org-roam-capture-after-finalize-hook
            (lambda ()
              (when (fboundp 'supertag-sync-check-now)
                (run-with-idle-timer 0.5 nil #'supertag-sync-check-now)))))

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
  (setq org-roam-db-extra-links-exclude-keys
        (remove "transclude" org-roam-db-extra-links-exclude-keys)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: org-ql — SQL-like query language for org
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org-ql
  :after org
  :commands (org-ql-search org-ql-view org-ql-select))

(provide 'init-pkm)
;;; init-pkm.el ends here
