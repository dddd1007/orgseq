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

(defvar org-supertag-bridge-enable-ai)

;; Requires: init-org (my/roam-dir)
(defvar my/roam-dir)  ; forward-declare from init-org

(defvar my/supertag-install-error nil
  "Last error encountered while installing org-supertag, if any.")

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
;; MELPA; we install it from GitHub via `package-vc-install'. This
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

;; Bootstrap org-supertag from GitHub (not on MELPA).  Works on Emacs 29+
;; via package-vc-install.  The condition-case prevents an offline first
;; boot from killing init.el; the deferred warning below tells the user
;; to retry once they have network.
(unless (package-installed-p 'org-supertag)
  (condition-case err
      (package-vc-install "https://github.com/yibie/org-supertag")
    (error
     (setq my/supertag-install-error err)
     (message "WARNING org-seq: failed to install org-supertag: %s" err))))

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

(unless (locate-library "org-supertag")
  (run-with-idle-timer 2 nil
    (lambda ()
      (message "WARNING org-seq: org-supertag not found. %sRun M-x package-vc-install RET https://github.com/yibie/org-supertag RET"
               (if my/supertag-install-error
                   (format "Last install error: %s. " my/supertag-install-error)
                 "")))))

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
