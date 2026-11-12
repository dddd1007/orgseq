;;; init-pkm.el --- Transclusion and Org queries -*- lexical-binding: t; -*-

;; Note-level structure (types, fields, views) lives in init-nodes on top
;; of the kernel index.  This module only adds two general Org tools that the
;; node layer and GTD build on: live transclusion of other nodes and
;; org-ql queries.

(use-package org-transclusion
  :after org
  :bind (("C-c t a" . org-transclusion-add)
         ("C-c t t" . org-transclusion-mode)
         ("C-c t m" . org-transclusion-transient-menu))
  :config
  (add-to-list 'org-transclusion-extensions 'org-transclusion-indent-mode)
  (require 'org-transclusion-indent-mode))

(use-package org-ql
  :after org
  :commands (org-ql-search org-ql-view org-ql-select))

(provide 'init-pkm)
;;; init-pkm.el ends here
