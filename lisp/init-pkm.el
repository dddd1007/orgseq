;;; init-pkm.el --- PKM extensions -*- lexical-binding: t; -*-

;; ---- org-transclusion: live content embedding ----
(use-package org-transclusion
  :after org
  :bind (("C-c t a" . org-transclusion-add)
         ("C-c t t" . org-transclusion-mode)
         ("C-c t m" . org-transclusion-transient-menu))
  :config
  (add-to-list 'org-transclusion-extensions 'org-transclusion-indent-mode)
  (require 'org-transclusion-indent-mode)
  ;; Register transclusion links as org-roam backlinks
  (with-eval-after-load 'org-roam
    (setq org-roam-db-extra-links-exclude-keys
          (remove "transclude" org-roam-db-extra-links-exclude-keys))))

;; ---- org-ql: SQL-like query language for org ----
(use-package org-ql
  :after org)

;; ---- org-supertag: structured tag system (experimental) ----
;; Uncomment when ready to experiment:
;; (package-vc-install "https://github.com/yibie/org-supertag")
;; (use-package org-supertag
;;   :after org
;;   :config
;;   (org-supertag-setup))

(provide 'init-pkm)
;;; init-pkm.el ends here
