;;; init-roam.el --- org-roam PKM engine + org-node acceleration -*- lexical-binding: t; -*-

;; Requires: init-org (my/note-home)
(defvar my/note-home)  ; forward-declare from init-org

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: org-roam — core PKM graph database
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; org-roam provides the node/link/backlink data model and capture system.
;; Its expensive SQLite sync is offloaded to org-mem (see Section 2).

(use-package org-roam
  :demand t
  :custom
  (org-roam-directory (file-truename "~/NoteHQ/Roam/"))
  (org-roam-db-location
   (expand-file-name "org-roam.db" (file-truename "~/NoteHQ/Roam/")))
  (org-roam-completion-everywhere t)
  (org-roam-node-display-template "${title:*} ${tags:10}")
  ;; Suppress GC during DB-intensive operations (official recommendation)
  (org-roam-db-gc-threshold most-positive-fixnum)
  ;; Skip roam:-to-id: link replacement on save (we never use roam: links)
  (org-roam-link-auto-replace nil)
  ;; Disable org-roam's per-save DB writes; org-mem handles this faster.
  (org-roam-db-update-on-save nil)

  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n j" . org-roam-dailies-capture-today))

  :config
  ;; Directory creation handled by my/ensure-notehq-structure (init-supertag)
  (make-directory org-roam-directory t)

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

  ;; ---- Capture templates ----
  ;; All captures land in Roam/capture/ (flat, timestamp-prefixed).
  ;; Classification is handled by supertags, not directories.
  ;; Start with minimal templates; add more as your tag schema grows.
  (setq org-roam-capture-templates
        '(("d" "Default" plain "%?"
           :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n")
           :unnarrowed t)

          ("r" "Reading" plain
           "* TL;DR\n%?\n* Key points\n* My commentary\n"
           :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :reading:\n")
           :unnarrowed t)))

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
  (org-roam-db-autosync-mode))

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

(use-package org-node
  :after org-roam
  :demand t
  :custom
  ;; Delegate node creation to org-roam's capture system
  (org-node-creation-fn #'org-node-new-via-roam-capture)
  ;; Match org-roam's default slug style
  (org-node-slug-fn #'org-node-slugify-like-roam-default)
  ;; Match existing filename timestamp prefix format
  (org-node-file-timestamp-format "%Y%m%dT%H%M%S-")

  :config
  ;; Scope org-mem to the notes directory
  (setq org-mem-watch-dirs (list (file-truename "~/NoteHQ/Roam/")))

  ;; Write to org-roam's real DB so org-roam-ui and other extensions work
  (setq org-mem-roamy-do-overwrite-real-db t)

  (org-node-cache-mode 1)
  (org-node-roam-accelerator-mode 1)
  (org-mem-roamy-db-mode 1))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Utilities and visualization
;; ═══════════════════════════════════════════════════════════════════════════

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
