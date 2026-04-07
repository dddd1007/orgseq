;;; init-markdown.el --- Markdown editing experience -*- lexical-binding: t; -*-

(defun my/markdown-setup ()
  "Apply opinionated defaults for Markdown editing."
  (visual-line-mode 1)
  (setq-local fill-column 100)
  (display-line-numbers-mode 0))

(use-package markdown-mode
  :mode (("\\.md\\'" . gfm-mode)
         ("\\.markdown\\'" . markdown-mode))
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
    (setq markdown-command "pandoc"))
  (add-hook 'markdown-mode-hook #'my/markdown-setup))

(use-package markdown-toc
  :after markdown-mode
  :commands (markdown-toc-generate-toc markdown-toc-refresh-toc)
  :init
  (setq markdown-toc-header-toc-title "## Table of Contents"))

(provide 'init-markdown)
;;; init-markdown.el ends here
