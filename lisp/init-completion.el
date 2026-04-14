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
  (when (eq system-type 'windows-nt)
    ;; Windows: path separator must be / for preview/jump consistency.
    (setq consult-ripgrep-args
          "rg --null --line-buffered --color=never --max-columns=1000 --path-separator / --smart-case --no-heading --with-filename --line-number --search-zip"))
  ;; Debian/Ubuntu package fd as `fdfind', while Homebrew/Arch/Fedora use `fd'.
  ;; Consult should follow whichever executable is actually present.
  (when-let ((fd (or (executable-find "fd")
                     (executable-find "fdfind"))))
    (setq consult-find-args
          (format "%s --color=never --full-path" (shell-quote-argument fd)))))

;; ---- Marginalia: rich annotations for completion candidates ----
(use-package marginalia
  :init (marginalia-mode))

;; ---- Embark: contextual actions (right-click menu concept) ----
(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)))

(use-package embark-consult
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; ---- Corfu: in-buffer completion popup (sibling of vertico) ----
;; Picks up completion-at-point-functions from eglot, ESS, cape, etc.
(use-package corfu
  :demand t
  :custom
  (corfu-cycle t)
  (corfu-auto t)                          ; popup without manual M-TAB
  (corfu-auto-delay 0.2)
  (corfu-auto-prefix 2)                   ; start completing after 2 chars
  (corfu-quit-no-match 'separator)
  (corfu-preview-current nil)
  (corfu-popupinfo-delay '(0.4 . 0.2))    ; doc popup timing (show . update)
  :init
  (global-corfu-mode)
  :config
  (when (fboundp 'corfu-popupinfo-mode)
    (corfu-popupinfo-mode 1))             ; inline doc for current candidate
  :bind (:map corfu-map
         ("C-j"   . corfu-next)
         ("C-k"   . corfu-previous)
         ("M-d"   . corfu-popupinfo-toggle)
         ("TAB"   . corfu-insert)
         ([tab]   . corfu-insert)))

;; ---- Cape: extra completion-at-point backends (files, dabbrev, ...) ----
(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev))

(provide 'init-completion)
;;; init-completion.el ends here
