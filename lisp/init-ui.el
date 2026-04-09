;;; init-ui.el --- Fonts, themes, modeline -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

;; ---- CJK mixed typesetting ----
(defvar my/cjk-font-candidates
  '("Sarasa Fixed SC" "LXGW WenKai Mono" "Microsoft YaHei UI" "SimHei")
  "CJK font candidates in preference order.")

(defun my/first-available-font (candidates)
  "Return the first installed font from CANDIDATES."
  (cl-find-if (lambda (f) (member f (font-family-list))) candidates))

(defun my/setup-fonts ()
  "Configure mixed CJK/Latin fonts."
  (when (display-graphic-p)
    (set-face-attribute 'default nil
                        :family "Cascadia Code"
                        :height 130)

    (when-let ((cjk (my/first-available-font my/cjk-font-candidates)))
      (dolist (charset '(kana han symbol cjk-misc bopomofo))
        (set-fontset-font t charset (font-spec :family cjk)))
      (setq face-font-rescale-alist
            (cond
             ((string= cjk "Sarasa Fixed SC")     `((,cjk . 1.0)))
             ((string= cjk "LXGW WenKai Mono")    `((,cjk . 1.1)))
             (t                                    `((,cjk . 1.05)))))
      (message "org-seq: CJK font → %s" cjk))))

;; Handle daemon mode
(if (daemonp)
    (add-hook 'after-make-frame-functions
              (lambda (frame)
                (with-selected-frame frame (my/setup-fonts))))
  (my/setup-fonts))

;; ---- modus-themes: accessible, WCAG AAA ----
(use-package modus-themes
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

;; ---- ef-themes: colorful & elegant light/dark themes (lazy, for switching) ----
(use-package ef-themes
  :defer t)

;; ---- doom-themes: modern IDE-style themes (lazy, for switching) ----
(use-package doom-themes
  :defer t
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
  (doom-modeline-height 22)
  (doom-modeline-bar-width 4)
  (doom-modeline-icon t)
  (doom-modeline-major-mode-icon nil)
  (doom-modeline-minor-modes nil)
  (doom-modeline-buffer-encoding nil)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-project-detection 'project))

;; ---- valign: pixel-perfect table alignment with variable-width fonts ----
(use-package valign
  :hook (org-mode . valign-mode))

;; ---- Adaptive centered writing ----
;; Shared infrastructure for Olivetti (org) and visual-fill-column (markdown).
;; Both use the same pattern: compute width from window, apply face remaps,
;; refresh on window resize.

(defcustom my/olivetti-body-width-min 88
  "Minimum body width for `olivetti-mode'."
  :type 'integer :group 'org-seq)

(defcustom my/olivetti-body-width-max 140
  "Maximum body width for `olivetti-mode'."
  :type 'integer :group 'org-seq)

(defcustom my/olivetti-body-width-scale 0.62
  "Body width as a fraction of the current window width."
  :type 'float :group 'org-seq)

(defvar-local my/centered-face-remaps nil
  "Face remap cookies for flattening side areas.  Shared by olivetti and markdown.")

(defun my/centered-compute-width (min-w max-w scale &optional window)
  "Compute adaptive body width for WINDOW given MIN-W, MAX-W, and SCALE."
  (let* ((window (or window (selected-window)))
         (ww (window-total-width window)))
    (max min-w (min max-w (floor (* ww scale))))))

(defun my/centered-apply-face-remaps ()
  "Flatten side-area faces to match the main text background."
  (unless my/centered-face-remaps
    (setq-local my/centered-face-remaps
                (list (face-remap-add-relative 'left-margin 'default)
                      (face-remap-add-relative 'right-margin 'default)
                      (face-remap-add-relative 'fringe 'default)))))

(defun my/centered-remove-face-remaps ()
  "Remove face remaps added by `my/centered-apply-face-remaps'."
  (when my/centered-face-remaps
    (dolist (cookie my/centered-face-remaps)
      (face-remap-remove-relative cookie))
    (setq-local my/centered-face-remaps nil)))

(defun my/olivetti-refresh-window (&optional window)
  "Refresh Olivetti layout in WINDOW."
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (when (bound-and-true-p olivetti-mode)
        (my/centered-apply-face-remaps)
        (setq-local olivetti-body-width
                    (my/centered-compute-width
                     my/olivetti-body-width-min
                     my/olivetti-body-width-max
                     my/olivetti-body-width-scale window))
        (setq-local fringes-outside-margins nil)
        (set-window-fringes window 0 0)
        (olivetti-set-width olivetti-body-width)))))

(defun my/olivetti-refresh-all-windows (&optional frame)
  "Refresh Olivetti layout in all live windows on FRAME."
  (dolist (window (window-list frame 'no-minibuffer))
    (my/olivetti-refresh-window window)))

(defun my/olivetti-setup ()
  "Enable adaptive Olivetti layout for the current buffer."
  (olivetti-mode 1)
  (my/olivetti-refresh-window))

(defun my/olivetti-mode-hook-fn ()
  "Handle Olivetti mode toggle: apply remaps on enable, clean up on disable."
  (if olivetti-mode
      (my/olivetti-refresh-window)
    (my/centered-remove-face-remaps)))

(use-package olivetti
  :hook ((org-mode . my/olivetti-setup)
         (olivetti-mode . my/olivetti-mode-hook-fn))
  :custom
  (olivetti-style nil)
  :config
  (add-hook 'window-size-change-functions #'my/olivetti-refresh-all-windows))

;; ---- General UI settings ----
(setq-default cursor-type 'bar)
(blink-cursor-mode -1)
(global-display-line-numbers-mode 1)
(column-number-mode 1)

;; Disable line numbers in prose/terminal modes
(defun my/disable-line-numbers ()
  "Disable `display-line-numbers-mode'."
  (display-line-numbers-mode 0))

(dolist (mode '(org-mode-hook
               dashboard-mode-hook
               treemacs-mode-hook
               term-mode-hook
               shell-mode-hook
               eshell-mode-hook))
  (add-hook mode #'my/disable-line-numbers))

(provide 'init-ui)
;;; init-ui.el ends here
