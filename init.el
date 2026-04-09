;;; init.el --- Main configuration entry point -*- lexical-binding: t; -*-

;; ---- Restore reasonable GC after startup ----
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)  ; 16MB
                  gc-cons-percentage 0.1)
            (message "Emacs loaded in %s with %d garbage collections."
                     (emacs-init-time) gcs-done)))

;; ---- Runtime performance (Doom-style) ----
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)
(setq-default cursor-in-non-selected-windows nil)
(setq highlight-nonselected-windows nil)
(setq redisplay-skip-fontification-on-input t)

;; Large process output buffer — benefits LSP, ripgrep, etc. (Doom/Purcell/Centaur)
(setq read-process-output-max (* 4 1024 1024))  ; 4MB

;; ---- Windows performance tuning ----
(when (eq system-type 'windows-nt)
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

;; Allow package.el to upgrade built-in packages (Transient, Org, etc.)
(setq package-install-upgrade-built-in t)

;; ---- Module load path ----
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; ---- Separate custom file ----
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

;; ---- Clipboard sanity (Purcell/Prot/Centaur) ----
(setq save-interprogram-paste-before-kill t   ; preserve external clipboard before kill
      kill-do-not-save-duplicates t)          ; no consecutive dupes in kill ring

;; ---- History persistence ----
(use-package savehist
  :ensure nil
  :custom
  (savehist-additional-variables '(search-ring regexp-search-ring kill-ring))
  :config
  ;; Strip text properties before saving to prevent savehist file bloat (Doom)
  (add-hook 'savehist-save-hook
            (lambda ()
              (setq kill-ring
                    (mapcar #'substring-no-properties
                            (cl-remove-if-not #'stringp kill-ring)))))
  :init (savehist-mode))

;; ---- Save place: reopen files at last position ----
(use-package saveplace
  :ensure nil
  :init (save-place-mode)
  :config
  ;; Recenter after restoring saved position (Doom) — avoids cursor at window edge
  (advice-add 'save-place-find-file-hook :after
              (lambda (&rest _)
                (when buffer-file-name (ignore-errors (recenter))))))

;; ---- Editing polish ----
(setq set-mark-command-repeat-pop t)           ; C-SPC C-SPC ... pops mark ring (Purcell/Prot)
(setq help-window-select t)                    ; auto-focus *Help* buffer (Prot)
(setq window-combination-resize t)             ; proportional window resize on split (Purcell/Prot)
(setq ffap-machine-p-known 'reject)            ; no network pings in find-file-at-point (Centaur)
(setq reb-re-syntax 'string)                   ; sane regex builder syntax — no double-escaping

;; Winner mode: undo/redo window layouts
(winner-mode +1)

;; Auto-chmod scripts on save (cross-platform; no-op on Windows)
(add-hook 'after-save-hook
          #'executable-make-buffer-file-executable-if-script-p)

;; ---- External dependency checks (deferred to avoid process spawns during init) ----
(run-with-idle-timer 2 nil
  (lambda ()
    (dolist (tool '(("rg" . "ripgrep") ("fd" . "fd-find")))
      (unless (executable-find (car tool))
        (message "⚠️ org-seq: %s (%s) not found. Install via your package manager%s."
                 (car tool) (cdr tool)
                 (if (eq system-type 'windows-nt) " (winget/scoop)" ""))))))

;; ---- Load modules ----
;; Order: UI -> completion -> markdown -> org -> roam -> gtd -> pkm -> supertag -> ai -> dashboard -> workspace -> evil (last)
(require 'init-ui)
(require 'init-completion)
(require 'init-markdown)
(require 'init-org)
(require 'init-roam)
(require 'init-gtd)
(require 'init-pkm)
(require 'init-supertag)
(require 'init-ai)
(require 'init-dashboard)
(require 'init-workspace)
(require 'init-evil)

;; ---- Emacs server ----
;; Start server so emacsclient can connect instantly.
;; Windows: server-use-tcp is set above; clients use emacsclient -c -a ""
(require 'server)
(unless (or (daemonp) (server-running-p))
  (server-start))

(provide 'init)
;;; init.el ends here
