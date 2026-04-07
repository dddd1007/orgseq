;;; init.el --- Main configuration entry point -*- lexical-binding: t; -*-

;; ---- Restore reasonable GC after startup ----
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)  ; 16MB
                  gc-cons-percentage 0.1)
            (message "Emacs loaded in %s with %d garbage collections."
                     (emacs-init-time) gcs-done)))

;; ---- Windows performance tuning ----
(when (eq system-type 'windows-nt)
  (setq read-process-output-max (* 1024 1024))  ; 1MB
  (setq w32-pipe-read-delay 0)
  (setq w32-pipe-buffer-size (* 64 1024))        ; 64KB

  ;; Encoding: unified UTF-8
  (prefer-coding-system 'utf-8-unix)
  (setq-default buffer-file-coding-system 'utf-8-unix)

  ;; Server: Windows has no Unix domain sockets
  (setq server-use-tcp t))

;; ---- Package management ----
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; ---- use-package (Emacs 29+ built-in) ----
(require 'use-package)
(setq use-package-always-ensure t
      use-package-expand-minimally t
      use-package-verbose nil)

;; ---- Module load path ----
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; ---- Separate custom file ----
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

;; ---- History persistence ----
(use-package savehist
  :ensure nil
  :init (savehist-mode))

;; ---- External dependency checks ----
(dolist (tool '(("rg" . "ripgrep: winget install BurntSushi.ripgrep.MSVC")
               ("fd" . "fd: winget install sharkdp.fd")))
  (unless (executable-find (car tool))
    (message "⚠️ org-seq: %s not found. Install: %s" (car tool) (cdr tool))))

;; ---- Load modules ----
;; Order: UI -> completion -> markdown -> org -> roam -> pkm -> ai -> dashboard -> workspace -> evil (last)
(require 'init-ui)
(require 'init-completion)
(require 'init-markdown)
(require 'init-org)
(require 'init-roam)
(require 'init-pkm)
(require 'init-ai)
(require 'init-dashboard)
(require 'init-workspace)
(require 'init-evil)

;;; init.el ends here
