;;; init-ui.el --- Fonts, themes, modeline -*- lexical-binding: t; -*-

;; ---- CJK mixed typesetting ----
(defun my/setup-fonts ()
  "Configure mixed CJK/Latin fonts."
  (when (display-graphic-p)
    ;; Latin font
    (set-face-attribute 'default nil
                        :family "Cascadia Code"
                        :height 130)  ; 13pt

    ;; CJK font: han, kana, symbol, cjk-misc, bopomofo
    (dolist (charset '(kana han symbol cjk-misc bopomofo))
      (set-fontset-font t charset
                        (font-spec :family "LXGW WenKai Mono")))

    ;; Rescale CJK font to align with Latin
    (setq face-font-rescale-alist
          '(("LXGW WenKai Mono" . 1.1)))))

;; Handle daemon mode
(if (daemonp)
    (add-hook 'after-make-frame-functions
              (lambda (frame)
                (with-selected-frame frame (my/setup-fonts))))
  (my/setup-fonts))

;; ---- modus-themes: accessible, built-in since Emacs 28 ----
(use-package modus-themes
  :ensure nil
  :demand t
  :config
  (setq modus-themes-mixed-fonts t
        modus-themes-italic-constructs t
        modus-themes-bold-constructs t
        modus-themes-prompts '(bold)
        modus-themes-completions '((t . (bold)))
        modus-themes-org-blocks 'tinted-background
        modus-themes-headings '((1 . (variable-pitch 1.4))
                                (2 . (1.2))
                                (3 . (1.1))
                                (t . (1.0))))
  (load-theme 'modus-operandi-tinted t))

;; ---- ef-themes: colorful & elegant light/dark themes ----
(use-package ef-themes
  :demand t)

;; ---- doom-themes: modern IDE-style themes ----
(use-package doom-themes
  :demand t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

;; ---- nerd-icons ----
;; Windows: after install, run M-x nerd-icons-install-fonts
;; then manually install the downloaded .ttf files (right-click -> Install)
(use-package nerd-icons
  :demand t)

;; ---- doom-modeline ----
(use-package doom-modeline
  :demand t
  :init (doom-modeline-mode 1)
  :custom
  (doom-modeline-height 25)
  (doom-modeline-bar-width 4)
  (doom-modeline-icon t)
  (doom-modeline-buffer-file-name-style 'auto)
  (doom-modeline-project-detection 'project))

;; ---- valign: pixel-perfect table alignment with variable-width fonts ----
(use-package valign
  :hook (org-mode . valign-mode))

;; ---- General UI settings ----
(setq-default cursor-type 'bar)
(blink-cursor-mode -1)
(global-display-line-numbers-mode 1)
(column-number-mode 1)

;; Disable line numbers in certain modes
(dolist (mode '(org-mode-hook
               term-mode-hook
               shell-mode-hook
               eshell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

(provide 'init-ui)
;;; init-ui.el ends here
