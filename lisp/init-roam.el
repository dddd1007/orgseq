;;; init-roam.el --- org-roam PKM engine -*- lexical-binding: t; -*-

;; md-roam is not on MELPA; install from GitHub once.
(unless (package-installed-p 'md-roam)
  (if (fboundp 'package-vc-install)
      (condition-case err
          (package-vc-install "https://github.com/nobiot/md-roam")
        (error
         (message "⚠️ org-seq: failed to install md-roam: %s" err)))
    (message "⚠️ org-seq: package-vc-install unavailable, skip md-roam bootstrap.")))

(use-package org-roam
  :demand t
  :custom
  (org-roam-directory (file-truename "~/org-roam/"))
  (org-roam-db-location
   (expand-file-name "org-roam.db" (file-truename "~/org-roam/")))
  (org-roam-completion-everywhere t)
  (org-roam-node-display-template
   (concat "${title:*} " (propertize "${tags:10}" 'face 'org-tag)))

  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n j" . org-roam-dailies-capture-today))

  :config
  ;; Ensure directory structure exists before database init
  (dolist (dir (list org-roam-directory
                     (expand-file-name "daily" org-roam-directory)
                     (expand-file-name "lit" org-roam-directory)
                     (expand-file-name "concepts" org-roam-directory)))
    (make-directory dir t))

  ;; Backlinks buffer on the right side
  (add-to-list 'display-buffer-alist
               '("\\*org-roam\\*"
                 (display-buffer-in-direction)
                 (direction . right)
                 (window-width . 0.33)
                 (window-height . fit-window-to-buffer)))

  ;; Node inclusion: exclude ATTACH-tagged headings
  (setq org-roam-db-node-include-function
        (lambda ()
          (not (member "ATTACH" (org-get-tags)))))

  ;; ID generation
  (setq org-id-method 'ts
        org-id-ts-format "%Y%m%dT%H%M%S")

  ;; ---- Capture templates ----
  (setq org-roam-capture-templates
        '(("d" "Default" plain "%?"
           :target (file+head "%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: \n")
           :unnarrowed t)

          ("l" "Literature note" plain "%?"
           :target (file+head "lit/%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :literature:\n\n* Core Ideas\n\n* Methodology\n\n* Relevance\n\n* Notes\n")
           :unnarrowed t)

          ("c" "Concept" plain "%?"
           :target (file+head "concepts/%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :concept:\n\n* Definition\n\n* Related Concepts\n\n* Notes\n")
           :unnarrowed t)

          ("f" "Fleeting" plain "%?"
           :target (file+head "%<%Y%m%dT%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :fleeting:\n")
           :immediate-finish t :unnarrowed t)))

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
                                  ("Journal"))))))

;; ---- md-roam: mixed Org + Markdown graph for Obsidian compatibility ----
;; Enable md-roam before org-roam autosync.
(use-package md-roam
  :after org-roam
  :if (locate-library "md-roam")
  :custom
  (md-roam-file-extension "md")
  :config
  (setq org-roam-file-extensions '("org" "md"))
  (md-roam-mode 1)
  (org-roam-db-autosync-mode 1))

;; ---- Full-text search in org-roam directory ----
(defun my/org-roam-rg-search ()
  "Search org-roam directory with consult-ripgrep."
  (interactive)
  (consult-ripgrep org-roam-directory))

;; ---- org-roam-ui: browser-based graph visualization ----
(use-package org-roam-ui
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t
        org-roam-ui-open-on-start nil))

(provide 'init-roam)
;;; init-roam.el ends here
