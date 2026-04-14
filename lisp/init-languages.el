;;; init-languages.el --- R (ESS) + Python (eglot) + Julia -*- lexical-binding: t; -*-

;; Requires: init-completion (corfu provides the in-buffer popup UI used by
;; every language backend registered here).

;; ═══════════════════════════════════════════════════════════════════════════
;; ESS: R as primary, with Julia/SAS/Stata secondary via the same package
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; ESS (Emacs Speaks Statistics) is the canonical R environment on Emacs:
;; syntax/indentation, inferior R process (`M-x R'), send region/buffer/
;; function (`C-c C-n', `C-c C-b', `C-c C-c'), object browser, help lookup.
;; Completion flows through `completion-at-point-functions' and pops up via
;; corfu automatically.
;;
;; For LSP-grade navigation in R, install the `languageserver' R package
;; once (`install.packages("languageserver")') and run `M-x eglot-ensure' in
;; an R buffer.  ESS itself works fully without it.

(use-package ess
  :defer t
  :mode (("\\.[rR]\\'"         . R-mode)
         ("\\.[rR]profile\\'"  . R-mode))
  :commands (R R-mode ess-julia-mode ess-switch-to-ESS)
  :custom
  (ess-ask-for-ess-directory nil)         ; don't prompt for working dir
  (ess-eval-visibly 'nowait)              ; async eval, never block on output
  (ess-use-flymake nil)                   ; flymake in R buffers is noisy
  (ess-style 'RStudio)                    ; familiar indentation
  (ess-indent-with-fancy-comments nil)    ; # / ## / ### share one column
  (inferior-R-args "--no-restore --no-save")
  :config
  ;; Windows: locate the latest R install if Rterm.exe isn't already on PATH.
  (when (and (eq system-type 'windows-nt)
             (not (executable-find "Rterm")))
    (dolist (root '("C:/Program Files/R" "C:/Program Files (x86)/R"))
      (when (file-directory-p root)
        (let* ((versions (directory-files root t "^R-[0-9]"))
               (latest   (car (last (sort versions #'string<)))))
          (when latest
            (let ((bin (expand-file-name "bin/x64" latest)))
              (when (and (file-directory-p bin) (fboundp 'my/prepend-to-exec-path))
                (my/prepend-to-exec-path bin)))))))))

;; ---- poly-R: polymode for Rmarkdown (.Rmd) and Quarto (.qmd) ----
(use-package poly-R
  :defer t
  :after ess
  :mode (("\\.[rR]md\\'" . poly-markdown+r-mode)
         ("\\.qmd\\'"    . poly-markdown+r-mode)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Python: built-in python.el + eglot + pyright (via pip/npm)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Emacs 29+ ships `python.el' and `eglot' in-tree.  We only need to point
;; eglot at a language server; pyright is the recommended choice (fast,
;; type-aware).  Install once: `pip install pyright' or `npm i -g pyright'.
;; Falls back to pylsp if pyright isn't on PATH.

(use-package python
  :ensure nil                              ; built-in
  :mode (("\\.py\\'" . python-mode))
  :custom
  (python-indent-offset 4)
  (python-shell-interpreter
   (cond ((executable-find "python")  "python")
         ((executable-find "python3") "python3")
         (t "python"))))

;; Auto-launch eglot only if an LSP server is actually installed, so users
;; without pyright aren't hit with a noisy error on every .py file open.
(when (or (executable-find "pyright-langserver")
          (executable-find "pylsp")
          (executable-find "python-lsp-server"))
  (add-hook 'python-mode-hook    #'eglot-ensure)
  (add-hook 'python-ts-mode-hook #'eglot-ensure))

;; ---- pyvenv: activate virtualenvs so eglot/python-shell pick them up ----
(use-package pyvenv
  :defer t
  :commands (pyvenv-activate pyvenv-workon pyvenv-deactivate))

;; ═══════════════════════════════════════════════════════════════════════════
;; Julia: julia-mode + julia-repl (terminal REPL, preferred over ESS-julia)
;; ═══════════════════════════════════════════════════════════════════════════

(use-package julia-mode
  :defer t
  :mode "\\.jl\\'")

(use-package julia-repl
  :defer t
  :hook (julia-mode . julia-repl-mode)
  :commands (julia-repl))

(provide 'init-languages)
;;; init-languages.el ends here
