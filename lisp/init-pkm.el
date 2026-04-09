;;; init-pkm.el --- PKM extensions: org-supertag + org-transclusion + org-ql -*- lexical-binding: t; -*-

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: org-supertag — structured data engine (Tana-style)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Core PKM engine: turns #tags into database tables with typed fields.
;; Provides structured queries, table views, kanban boards, and automation.
;;
;; Three-layer PKM architecture:
;;   org-roam      = graph layer      (nodes, links, backlinks, capture)
;;   org-node      = performance layer (fast indexing, async DB sync)
;;   org-supertag  = data layer       (structured tags, fields, queries, views)
;;
;; Higher-level supertag functions (schema, dashboards, PARA navigation)
;; live in init-supertag.el which loads after this module.

;; ht: hash-table library required by org-supertag
(use-package ht :ensure t)

;; Bootstrap org-supertag from GitHub (not on MELPA).
(when (< emacs-major-version 30)
  (unless (package-installed-p 'org-supertag)
    (if (fboundp 'package-vc-install)
        (condition-case err
            (package-vc-install "https://github.com/yibie/org-supertag")
          (error
           (message "WARNING org-seq: failed to install org-supertag: %s" err)))
      (message "WARNING org-seq: package-vc-install unavailable, skip org-supertag."))))

(if (>= emacs-major-version 30)
    (use-package org-supertag
      :after org
      :vc (:url "https://github.com/yibie/org-supertag" :rev :newest)
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
      (setq org-supertag-sync-directories
            (list (file-truename "~/NoteHQ/Roam/")))
      (setq org-supertag-bridge-enable-ai t))
  (use-package org-supertag
    :after org
    :if (locate-library "org-supertag")
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
    (setq org-supertag-sync-directories
          (list (file-truename "~/NoteHQ/Roam/")))
    (setq org-supertag-bridge-enable-ai t)))

(unless (locate-library "org-supertag")
  (run-with-idle-timer 2 nil
    (lambda ()
      (message "WARNING org-seq: org-supertag not found. Run M-x package-vc-install to install it."))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Capture bridge — org-roam → org-supertag
;; ═══════════════════════════════════════════════════════════════════════════

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
