;;; init-markdown.el --- Markdown editing experience -*- lexical-binding: t; -*-

;; Requires: init-ui (my/centered-compute-width, my/centered-apply-face-remaps)

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

(defun my/markdown-preview-buffer-p ()
  "Return non-nil when current buffer is a Markdown live preview buffer."
  (and (bound-and-true-p markdown-live-preview-source-buffer)
       (buffer-live-p markdown-live-preview-source-buffer)))

(defun my/markdown-switch-to-live-preview ()
  "Show Markdown live preview in the current window."
  (interactive)
  (unless (derived-mode-p 'markdown-mode)
    (user-error "Current buffer is not a Markdown buffer"))
  (unless buffer-file-name
    (user-error "Markdown live preview requires a file-backed buffer"))
  (let ((source-window (selected-window))
        preview-buffer)
    (unless (and markdown-live-preview-mode
                 (buffer-live-p markdown-live-preview-buffer))
      (markdown-live-preview-mode 1))
    (setq preview-buffer markdown-live-preview-buffer)
    (unless (buffer-live-p preview-buffer)
      (user-error "Failed to create Markdown preview buffer"))
    (dolist (window (get-buffer-window-list preview-buffer nil t))
      (unless (eq window source-window)
        (delete-window window)))
    (set-window-buffer source-window preview-buffer)
    (select-window source-window)))

(defun my/markdown-switch-to-source ()
  "Return from a Markdown live preview buffer to its source."
  (interactive)
  (unless (my/markdown-preview-buffer-p)
    (user-error "Current buffer is not a Markdown preview buffer"))
  (switch-to-buffer markdown-live-preview-source-buffer))

(defun my/markdown-toggle-live-preview ()
  "Toggle between Markdown source and live preview in the current window."
  (interactive)
  (cond
   ((my/markdown-preview-buffer-p)
    (my/markdown-switch-to-source))
   ((derived-mode-p 'markdown-mode)
    (my/markdown-switch-to-live-preview))
   (t
    (user-error "Current buffer is not Markdown source or preview"))))

(defun my/markdown-setup ()
  "Apply opinionated defaults for Markdown editing."
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
        markdown-enable-wiki-links t
        markdown-asymmetric-header t
        markdown-header-scaling t
        markdown-hide-urls t
        markdown-gfm-use-electric-backquote t)
  :config
  ;; Prefer pandoc when available for better export fidelity.
  (when (executable-find "pandoc")
    (setq markdown-command "pandoc")))

(use-package markdown-toc
  :after markdown-mode
  :commands (markdown-toc-generate-toc markdown-toc-refresh-toc)
  :init
  (setq markdown-toc-header-toc-title "## Table of Contents"))

;; ---- Local leader keys for Markdown buffers ----
;; Bound to , (normal/visual) and M-, (insert).
;; Requires general.el (loaded later in init-evil), so defer via eval-after-load.
(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps '(markdown-mode-map gfm-mode-map)
   :prefix ","
   :global-prefix "M-,"
   "" '(nil :wk "markdown")
   "v" '(my/markdown-toggle-live-preview :wk "Toggle live preview")
   "p" '(markdown-preview :wk "Preview")
   "e" '(markdown-export :wk "Export")
   "t" '(markdown-toc-generate-toc :wk "Insert TOC")
   "r" '(markdown-toc-refresh-toc :wk "Refresh TOC")
   "o" '(markdown-toggle-markup-hiding :wk "Toggle markup")
   "l" '(markdown-insert-link :wk "Insert link"))
  (with-eval-after-load 'eww
    (general-define-key
     :states '(normal emacs)
     :keymaps 'eww-mode-map
     :prefix ","
     :global-prefix "M-,"
     "v" '(my/markdown-toggle-live-preview :wk "Back to source"))))

(provide 'init-markdown)
;;; init-markdown.el ends here
