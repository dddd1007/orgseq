;;; init-platform.el --- Platform tuning and ELPA signature bootstrap -*- lexical-binding: t; -*-

;; Bootstrap-phase module.  Unlike every module in `my/init-modules-default',
;; this one is required directly by init.el before package management starts,
;; because `exec-path' repair and the ELPA signature probe both have to happen
;; before the first package is installed.  It therefore has no org-seq module
;; dependencies and must not require any other init-* module.

(require 'cl-lib)

(defvar package-check-signature)
(defvar package-gnupghome-dir)

(declare-function epg-find-configuration "epg-config"
                  (protocol &optional no-cache program-alist))

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
                 (list (expand-file-name ".bun/bin" "~")
                        (expand-file-name ".local/bin" "~")
                        (expand-file-name "AppData/Roaming/npm" "~")
                        (expand-file-name "AppData/Local/Microsoft/WinGet/Links" "~")
                        (expand-file-name "scoop/shims" "~")
                        "C:/ProgramData/chocolatey/bin"
                        "C:/Program Files/Git/usr/bin"))
                (when (eq system-type 'darwin)
                  (list (expand-file-name ".bun/bin" "~")
                        "/opt/homebrew/bin"
                        "/opt/homebrew/sbin"
                        "/usr/local/bin"
                        "/usr/local/sbin"
                       "/Library/TeX/texbin"
                       (expand-file-name ".local/bin" "~")
                       (expand-file-name "bin" "~")
                       (expand-file-name ".cargo/bin" "~")
                       (expand-file-name ".ghcup/bin" "~")))
                (when (eq system-type 'gnu/linux)
                  (list (expand-file-name ".bun/bin" "~")
                        (expand-file-name ".local/bin" "~")
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

;; NOTE(win): The bundled GPG in the official Windows Emacs build constructs
;; a malformed GNUPGHOME path (e.g. /c/Program Files/Emacs/c:/Users/...),
;; which makes ELPA signature verification fail even for legitimately signed
;; packages (the key exists but GPG cannot find its keyring).  Instead of
;; disabling signature checking outright, probe whether the resolved gpg can
;; actually operate on `package-gnupghome-dir' (a working gpg such as the one
;; shipped with Git for Windows is often on PATH).  Keep the default ELPA
;; verification whenever the probe succeeds; disable only when it fails.
(defvar my/package-signature-status
  (if (eq system-type 'windows-nt) 'unknown 'default)
  "How org-seq resolved ELPA signature checking on this system.
One of `default' (non-Windows, Emacs default), `verified' (Windows,
working gpg found, verification kept), or `disabled' (Windows, no
usable gpg, `package-check-signature' set to nil).")

(defvar epg-gpg-program)

(defconst my/init--gpg-native-candidates
  '("C:/Program Files (x86)/GnuPG/bin/gpg.exe"
    "C:/Program Files/GnuPG/bin/gpg.exe")
  "Known native Windows GnuPG install locations (Gpg4win, official GnuPG).
Native builds handle Windows-style --homedir paths; MSYS builds (Git for
Windows, the Emacs bundle) treat them as relative paths and fail.")

(defun my/init--gpg-homedir-usable-p (program homedir)
  "Return non-nil when gpg PROGRAM can operate on HOMEDIR.
Runs the same homedir access pattern package.el uses for signature
verification, so the probe fails exactly when real verification would.
HOMEDIR is created first because package.el creates it too when it
imports the bundled ELPA keyring; gpg refuses missing homedirs in
--batch mode, which would otherwise make this probe a false negative."
  (condition-case nil
      (progn
        (make-directory homedir t)
        (eq 0 (call-process program nil nil nil
                            "--homedir" homedir
                            "--batch" "--quiet" "--list-keys")))
    (error nil)))

(defun my/init--find-usable-gpg ()
  "Return a gpg program usable for ELPA verification, or nil.
Tries the gpg that epg resolves by default first, then the known native
GnuPG install locations in `my/init--gpg-native-candidates'."
  (when (require 'epg-config nil t)
    (let* ((homedir (expand-file-name package-gnupghome-dir))
           (config (ignore-errors (epg-find-configuration 'OpenPGP)))
           (default-program (and config (alist-get 'program config))))
      (or (and default-program
               (my/init--gpg-homedir-usable-p default-program homedir)
               default-program)
          (cl-find-if (lambda (candidate)
                        (and (file-executable-p candidate)
                             (my/init--gpg-homedir-usable-p candidate homedir)))
                      my/init--gpg-native-candidates)))))

(defun my/platform-resolve-package-signature ()
  "Resolve ELPA signature checking for this platform.
Sets `my/package-signature-status' and, on Windows, `package-check-signature'.
Call after `package' is loaded and before any package installation."
  (when (eq system-type 'windows-nt)
    ;; Probe only in interactive sessions: batch validation suppresses package
    ;; installation anyway, and skipping the subprocess keeps batch runs fast.
    (let ((gpg (and (not noninteractive) (my/init--find-usable-gpg))))
      (if gpg
          (progn
            (setq my/package-signature-status 'verified
                  package-check-signature 'allow-unsigned)
            ;; When the usable gpg is not the one epg resolves by default
            ;; (e.g. a native Gpg4win install shadowed by the MSYS gpg from
            ;; Git for Windows on exec-path), point epg at it explicitly and
            ;; refresh epg's cached configuration.
            (unless (equal gpg
                           (ignore-errors
                             (alist-get 'program
                                        (epg-find-configuration 'OpenPGP))))
              (setq epg-gpg-program gpg)
              (ignore-errors (epg-find-configuration 'OpenPGP t))))
        (setq my/package-signature-status 'disabled
              package-check-signature nil)
        (unless noninteractive
          (message "org-seq: no usable gpg found; ELPA signature checking disabled (install Gpg4win or official GnuPG to enable it)"))))))

(provide 'init-platform)
;;; init-platform.el ends here
