;;; init.el --- Main configuration entry point -*- lexical-binding: t; -*-

(require 'cl-lib)

(defvar server-use-tcp)

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

;; ---- Cross-platform runtime tuning ----

(defun my/prepend-to-exec-path (dir)
  "Prepend DIR to `exec-path' and PATH when DIR exists."
  (let ((expanded (directory-file-name (expand-file-name dir))))
    (when (file-directory-p expanded)
      (setq exec-path (cons expanded (delete expanded exec-path)))
      (let* ((path (or (getenv "PATH") ""))
             (parts (split-string path path-separator t)))
        (setenv "PATH"
                (mapconcat #'identity
                           (cons expanded (delete expanded parts))
                           path-separator))))))

(defun my/prepend-platform-exec-paths ()
  "Make common GUI-only tool paths visible to Emacs on every OS."
  (let ((dirs (append
               (when (eq system-type 'windows-nt)
                 (list (expand-file-name "AppData/Local/Microsoft/WinGet/Links" "~")
                       (expand-file-name "scoop/shims" "~")
                       "C:/ProgramData/chocolatey/bin"
                       "C:/Program Files/Git/usr/bin"))
               (when (eq system-type 'darwin)
                 (list "/opt/homebrew/bin"
                       "/opt/homebrew/sbin"
                       "/usr/local/bin"
                       "/usr/local/sbin"
                       "/Library/TeX/texbin"
                       (expand-file-name ".local/bin" "~")
                       (expand-file-name "bin" "~")
                       (expand-file-name ".cargo/bin" "~")
                       (expand-file-name ".ghcup/bin" "~")))
               (when (eq system-type 'gnu/linux)
                 (list (expand-file-name ".local/bin" "~")
                       (expand-file-name "bin" "~")
                       (expand-file-name ".cargo/bin" "~")
                       (expand-file-name ".nix-profile/bin" "~")
                       "/run/current-system/sw/bin"
                       "/snap/bin"
                       "/usr/local/bin"
                       "/usr/local/sbin")))))
    ;; Iterate in reverse because `my/prepend-to-exec-path' prepends; the
    ;; user-facing order above remains the final priority order.
    (dolist (dir (reverse dirs))
      (my/prepend-to-exec-path dir))))

(my/prepend-platform-exec-paths)

(setq frame-resize-pixelwise t
      window-resize-pixelwise t
      select-enable-clipboard t
      delete-by-moving-to-trash t
      browse-url-browser-function
      (cond
       ((eq system-type 'darwin) 'browse-url-default-macosx-browser)
       ((eq system-type 'windows-nt) 'browse-url-default-windows-browser)
       (t 'browse-url-default-browser)))

(when (eq system-type 'gnu/linux)
  ;; PRIMARY selection is Linux/X-specific.  GUI Emacs handles Wayland/X11
  ;; clipboard integration itself when built with the relevant toolkit.
  (setq select-enable-primary t))

(when (eq system-type 'darwin)
  ;; Natural macOS keyboard conventions: Option is Meta, Command remains
  ;; available for GUI/window-manager shortcuts through the Super modifier.
  (when (boundp 'mac-option-modifier)
    (setq mac-option-modifier 'meta))
  (when (boundp 'mac-command-modifier)
    (setq mac-command-modifier 'super))
  (when (boundp 'mac-right-option-modifier)
    (setq mac-right-option-modifier 'none))
  (when (boundp 'ns-use-native-fullscreen)
    (setq ns-use-native-fullscreen nil))
  (when (boundp 'ns-use-proxy-icon)
    (setq ns-use-proxy-icon nil)))

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
;; Allow package.el to upgrade built-in packages (Transient, Org, etc.)
;; Set BEFORE any potential package-install / use-package activation.
(setq package-install-upgrade-built-in t)

;; NOTE(win): The bundled GPG in the official Windows Emacs build constructs
;; a malformed GNUPGHOME path (e.g. /c/Program Files/Emacs/c:/Users/...),
;; which makes ELPA signature verification fail even for legitimately signed
;; packages (the key exists but GPG cannot find its keyring).  Disable
;; signature checking entirely on Windows to avoid blocking package installs.
(when (eq system-type 'windows-nt)
  (setq package-check-signature nil))

(package-initialize)
(defconst my/noninteractive-init noninteractive
  "Non-nil when org-seq is running in a batch/noninteractive session.")

(defun my/package-refresh-contents-maybe ()
  "Refresh package archives only when startup can afford network I/O."
  (if my/noninteractive-init
      (message "org-seq: skipping package archive refresh in noninteractive session")
    (condition-case err
        (package-refresh-contents)
      (error
       (message "WARNING org-seq: package archive refresh failed (%s).
  Restart with network connectivity to install missing packages." err)))))

(unless package-archive-contents
  (my/package-refresh-contents-maybe))

;; ---- use-package (Emacs 29+ built-in) ----
(require 'use-package)
(defun my/use-package-ensure-or-warn (name ensure state)
  "Install NAME for `use-package' or warn when ENSURE is skipped.

During noninteractive validation runs, package installation is suppressed
so byte-compilation and load tests never block on network traffic."
  (if my/noninteractive-init
      (progn
        (dolist (entry ensure)
          (let ((package (or (and (eq entry t) (if (symbolp name) name (intern name)))
                             (and (consp entry) (car entry))
                             entry)))
            (when (and package
                       (not (package-installed-p package)))
              (display-warning
               'org-seq
               (format "Skipping package install for %s in noninteractive session"
                       package)
               :warning))))
        t)
    (use-package-ensure-elpa name ensure state)))

(setq use-package-ensure-function #'my/use-package-ensure-or-warn
      use-package-always-ensure (not my/noninteractive-init)
      use-package-expand-minimally t
      use-package-verbose nil)

;; ---- Pre-module variable setup ----
;; Declare a few early-set variables so byte-compilation catches real issues
;; instead of reporting expected cross-module/built-in customization points.
(defvar evil-want-keybinding)
(defvar ffap-machine-p-known)
(defvar reb-re-syntax)

;; evil-want-keybinding must be nil BEFORE evil or evil-collection loads.
;; init-evil.el loads last, but byte-compilation of earlier modules can
;; trigger the evil-collection runtime warning.  Setting it here (before
;; any module loads) suppresses the warning unconditionally.
(setq evil-want-keybinding nil)

;; ---- Module load path ----
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; ---- Separate custom file ----
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

(defun my/load-custom-file ()
  "Load `custom-file' as explicit user overrides, reporting failures clearly."
  (interactive)
  (if (file-exists-p custom-file)
      (condition-case err
          (progn
            ;; Loaded before modules by design: values saved through Customize
            ;; can affect subsequent `defcustom' defaults and use-package setup.
            (load custom-file nil 'nomessage)
            (message "org-seq: loaded user overrides from %s" custom-file)
            t)
        (error
         (display-warning
          'org-seq
          (format "Failed to load custom-file %s: %s" custom-file err)
          :error)
         nil))
    (message "org-seq: custom-file does not exist yet: %s" custom-file)
    nil))

(defun my/open-custom-file ()
  "Open `custom-file' for inspecting user-level overrides."
  (interactive)
  (find-file custom-file))

(my/load-custom-file)

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

;; ---- Centralized backups: keep NoteHQ clean ----
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory)))
  (make-directory backup-dir t)
  (unless backup-directory-alist
    (setq backup-directory-alist `(("." . ,backup-dir)))))

;; ---- Parenthesis matching ----
(use-package paren
  :ensure nil
  :init
  (show-paren-mode 1))

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
        (message "WARNING org-seq: %s (%s) not found. Install via your package manager%s."
                 (car tool) (cdr tool)
                 (if (eq system-type 'windows-nt) " (winget/scoop)" ""))))))

;; ---- Load modules ----
;; Order: UI -> completion -> pyim -> markdown -> languages -> org -> roam
;; -> gtd -> focus -> pkm -> supertag -> ai -> dashboard -> dired
;; -> workspace -> update -> tty -> evil (last)
;; Each require is guarded so a single broken module does not kill the
;; entire config -- the user gets an actionable warning and can inspect
;; details with `M-x my/init-errors'.
(defvar my/--init-errors nil
  "List of (MODULE . ERROR) pairs for modules that failed to load.")

(defun my/init-errors ()
  "Display modules that failed during org-seq startup."
  (interactive)
  (let ((buf (get-buffer-create "*org-seq init errors*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if my/--init-errors
            (progn
              (insert (format "%d org-seq module(s) failed to load.\n\n"
                              (length my/--init-errors)))
              (dolist (pair (reverse my/--init-errors))
                (insert (format "* %s\n" (car pair)))
                (insert (format "  %s\n\n" (error-message-string (cdr pair))))))
          (insert "No org-seq module load errors recorded.\n"))
        (special-mode)))
    (pop-to-buffer buf)))

(defun my/--require-module (module)
  "Load MODULE, catching errors and recording failures."
  (condition-case err
      (require module)
    (error
     (push (cons module err) my/--init-errors)
     (message "WARNING org-seq: failed to load %s: %s (inspect with M-x my/init-errors)"
              module (error-message-string err)))))

(dolist (mod '(init-ui
               init-completion
               init-pyim
               init-markdown
               init-languages
               init-org
               init-roam
               init-gtd
               init-focus
               init-pkm
               init-supertag
               init-ai
               init-dashboard
               init-dired
               init-workspace
               init-update
               init-tty
               init-evil))
  (my/--require-module mod))

(when my/--init-errors
  (run-with-idle-timer
   1 nil
   (lambda ()
     (message "org-seq: %d module(s) failed to load: %s"
              (length my/--init-errors)
              (mapconcat (lambda (pair) (symbol-name (car pair)))
                         my/--init-errors ", ")))))

;; ---- Emacs server ----
;; Start server so emacsclient can connect instantly.
;; Windows: `server-use-tcp' is set above, so clients must point at the
;; TCP auth file (for the named org-seq daemon this is ~/.emacs.d/server/org-seq).
;; Linux/macOS use the normal local socket and can connect with
;; `emacsclient -s org-seq`.
(require 'server)
(setq server-name "org-seq")
(unless my/noninteractive-init
  (unless (server-running-p server-name)
    (server-start)))

(provide 'init)
;;; init.el ends here
