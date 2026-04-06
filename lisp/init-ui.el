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

;; ---- doom-themes ----
(use-package doom-themes
  :demand t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t)
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
