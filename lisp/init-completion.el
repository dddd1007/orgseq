;;; init-completion.el --- Vertico completion stack -*- lexical-binding: t; -*-

;; ---- Vertico: vertical completion UI ----
(use-package vertico
  :demand t
  :init (vertico-mode)
  :config
  (setq vertico-count 15
        vertico-cycle t
        vertico-resize nil)
  :bind (:map vertico-map
         ("C-j" . vertico-next)
         ("C-k" . vertico-previous)))

;; Vertico directory navigation enhancement (built-in extension)
(use-package vertico-directory
  :after vertico :ensure nil
  :bind (:map vertico-map
         ("RET" . vertico-directory-enter)
         ("DEL" . vertico-directory-delete-char)
         ("M-DEL" . vertico-directory-delete-word))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; ---- Orderless: space-separated fuzzy matching ----
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion)))))

;; ---- Consult: enhanced search/navigation commands ----
(use-package consult
  :bind (("C-x b" . consult-buffer)
         ("M-y"   . consult-yank-pop)
         ("M-s l" . consult-line)
         ("M-s r" . consult-ripgrep)
         ("M-s o" . consult-outline))
  :config
  ;; Windows: path separator must be / and find.exe conflicts with Unix find
  (when (eq system-type 'windows-nt)
    (setq consult-ripgrep-args
          "rg --null --line-buffered --color=never --max-columns=1000 --path-separator / --smart-case --no-heading --with-filename --line-number --search-zip")
    (setq consult-find-args "fd --color=never --full-path")))

;; ---- Marginalia: rich annotations for completion candidates ----
(use-package marginalia
  :init (marginalia-mode))

;; ---- Embark: contextual actions (right-click menu concept) ----
(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)))

(use-package embark-consult
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(provide 'init-completion)
;;; init-completion.el ends here
