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

(defun my/supertag--patch-file (file replacements)
  "Apply literal REPLACEMENTS to FILE when the old text is present.
Return non-nil if FILE was changed."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((changed nil))
        (dolist (replacement replacements)
          (goto-char (point-min))
          (when (search-forward (car replacement) nil t)
            (replace-match (cdr replacement) t t)
            (setq changed t)))
        (when changed
          (write-region (point-min) (point-max) file nil 'silent)
          (let ((elc (concat file "c")))
            (when (file-exists-p elc)
              (delete-file elc))))
        changed))))

(defun my/supertag-apply-compat-patches ()
  "Patch known org-supertag upstream byte-compile errors.
The fixes are intentionally tiny and only apply when exact old source
patterns are still present.  They can be removed once upstream ships the
same fixes."
  (when-let* ((main (locate-library "org-supertag"))
              (dir (file-name-directory main)))
    (let ((patched nil))
      (setq patched
            (or (my/supertag--patch-file
                 (expand-file-name "supertag-services-capture.el" dir)
                 '(("(mapconcat (lambda (t) (concat \"#\" t))"
                    . "(mapconcat (lambda (tag) (concat \"#\" tag))")))
                patched))
      (setq patched
            (or (my/supertag--patch-file
                 (expand-file-name "supertag-view-framework.el" dir)
                 '(("(list :type :list :items (\"Task A\" \"Task B\" \"Task C\"))"
                    . "(list :type :list :items (list \"Task A\" \"Task B\" \"Task C\"))")))
                patched))
      (setq patched
            (or (my/supertag--patch-file
                 (expand-file-name "supertag-view-effort-distribution.el" dir)
                 (list
                  (cons (concat "        (dolist (t node-tags)\n"
                                "          (when (and (stringp t) (not (equal t tag-name)))\n"
                                "            (let ((entry (assoc t tag-groups)))\n"
                                "              (if entry\n"
                                "                  (setcdr entry (+ (cdr entry) effort))\n"
                                "                (push (cons t effort) tag-groups)))))))")
                        (concat "        (dolist (tag node-tags)\n"
                                "          (when (and (stringp tag) (not (equal tag tag-name)))\n"
                                "            (let ((entry (assoc tag tag-groups)))\n"
                                "              (if entry\n"
                                "                  (setcdr entry (+ (cdr entry) effort))\n"
                                "                (push (cons tag effort) tag-groups)))))))"))))
                patched))
      (when patched
        (message "org-seq: applied org-supertag Emacs 30 compatibility patches")))))

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
