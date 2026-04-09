;;; init-markdown.el --- Markdown reading experience -*- lexical-binding: t; -*-

;; Requires: init-ui (my/centered-compute-width, my/centered-apply-face-remaps)
;;
;; Read-only oriented: provides comfortable viewing of .md files from other
;; tools (Obsidian, Typora, GitHub, etc.).  Not intended for Markdown authoring
;; — all note creation happens in Org-mode via org-roam.

(defcustom my/markdown-body-width-min 84
  "Minimum visual body width for Markdown buffers."
  :type 'integer :group 'org-seq)

(defcustom my/markdown-body-width-max 120
  "Maximum visual body width for Markdown buffers."
  :type 'integer :group 'org-seq)

(defcustom my/markdown-body-width-scale 0.72
  "Markdown body width as a fraction of the current window width."
  :type 'float :group 'org-seq)

(defun my/markdown-refresh-window (&optional window)
  "Refresh visual fill layout in Markdown WINDOW."
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (when (and (derived-mode-p 'markdown-mode)
                 (bound-and-true-p visual-fill-column-mode))
        (my/centered-apply-face-remaps)
        (setq-local visual-fill-column-width
                    (my/centered-compute-width
                     my/markdown-body-width-min
                     my/markdown-body-width-max
                     my/markdown-body-width-scale window))
        (set-window-fringes window 0 0)
        (visual-fill-column-adjust)))))

(defun my/markdown-refresh-all-windows (&optional frame)
  "Refresh Markdown layout in all live windows on FRAME."
  (dolist (window (window-list frame 'no-minibuffer))
    (my/markdown-refresh-window window)))

(defun my/markdown-setup ()
  "Apply reading-friendly defaults for Markdown buffers."
  (visual-line-mode 1)
  (adaptive-wrap-prefix-mode 1)
  (visual-fill-column-mode 1)
  (setq-local visual-fill-column-center-text t
              visual-fill-column-fringes-outside-margins nil
              fringes-outside-margins nil)
  (display-line-numbers-mode 0)
  (my/markdown-refresh-window))

(use-package adaptive-wrap
  :commands adaptive-wrap-prefix-mode)

(use-package visual-fill-column
  :commands (visual-fill-column-mode visual-fill-column-adjust)
  :config
  (add-hook 'window-size-change-functions #'my/markdown-refresh-all-windows))

(use-package markdown-mode
  :mode (("\\.md\\'" . gfm-mode)
         ("\\.markdown\\'" . markdown-mode))
  :hook ((markdown-mode . my/markdown-setup)
         (gfm-mode . my/markdown-setup))
  :init
  (setq markdown-fontify-code-blocks-natively t
        markdown-enable-math t
        markdown-asymmetric-header t
        markdown-header-scaling t
        markdown-hide-urls t)
  :config
  (when (executable-find "pandoc")
    (setq markdown-command "pandoc")))

;; ---- Local leader keys for Markdown buffers ----
;; Minimal set: preview and markup toggle only (read-oriented).
(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps '(markdown-mode-map gfm-mode-map)
   :prefix ","
   :global-prefix "M-,"
   "" '(nil :wk "markdown")
   "p" '(markdown-preview :wk "Preview in browser")
   "o" '(markdown-toggle-markup-hiding :wk "Toggle markup")))

(provide 'init-markdown)
;;; init-markdown.el ends here
