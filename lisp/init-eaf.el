;;; init-eaf.el --- Emacs Application Framework integration -*- lexical-binding: t; -*-

;; Requires: init-python (my/python-command)
;; Requires: init-markdown for Markdown local key integration.
;;
;; EAF is not an ELPA package.  It lives as a git checkout under
;; `my/eaf-install-dir' and is installed/updated with EAF's own
;; `install-eaf.py' script.  This module keeps startup non-fatal when EAF is
;; absent, and provides explicit commands for installation and app launching.

(require 'cl-lib)
(require 'subr-x)

(defvar eaf-browser-continue-where-left-off)
(defvar eaf-browser-enable-adblocker)
(defvar eaf-browser-auto-import-chrome-cookies)
(defvar eaf-browser-enable-autofill)
(defvar eaf-browser-keybinding)
(defvar eaf-enable-debug)
(defvar eaf-find-alternate-file-in-dired)
(defvar eaf-python-command)
(defvar eaf-file-manager-show-hidden-file)
(defvar eaf-goto-right-after-close-buffer)
(defvar eaf-marker-letters)
(defvar eaf-pdf-click-to-copy)
(defvar eaf-pdf-dark-mode)
(defvar eaf-pdf-show-progress-on-page)
(defvar eaf-pyqterminal-cursor-type)
(defvar eaf-pyqterminal-color-schema)
(defvar eaf-pyqterminal-color-schema-from-emacs)
(defvar eaf-pyqterminal-font-family)
(defvar eaf-pyqterminal-font-size)
(defvar eaf-pyqterminal-keybinding)
(defvar eaf-pyqterminal-refresh-ms)
(defvar eaf-rebuild-buffer-after-crash)
(defvar eaf-webengine-default-zoom)
(defvar eaf-webengine-fixed-font-family)
(defvar eaf-webengine-fixed-font-size)
(defvar eaf-webengine-font-family)
(defvar eaf-webengine-font-size)
(defvar eaf-webengine-serif-font-family)
(defvar eaf-evil-leader-key)
(defvar markdown-mode-map)
(defvar gfm-mode-map)
(defvar my/python-command nil)
(declare-function general-define-key "general" (&rest args))
(declare-function eaf-open "eaf" (url &optional app-name args))
(declare-function eaf-open-browser "eaf-browser" (&optional url))
(declare-function eaf-open-pyqterminal "eaf-pyqterminal" ())
(declare-function eaf-pyqterminal-run-command-in-dir "eaf-pyqterminal" (command dir &optional always-new))
(declare-function eaf-stop-process "eaf" ())
(declare-function markdown-preview "markdown-mode" ())

(defcustom my/eaf-install-dir
  (expand-file-name "site-lisp/emacs-application-framework/" user-emacs-directory)
  "Directory where EAF is cloned and loaded from."
  :type 'directory
  :group 'org-seq)

(defcustom my/eaf-enabled-apps
  '(markdown-previewer browser pdf-viewer file-manager pyqterminal image-viewer org-previewer video-player)
  "EAF applications to load when they are installed.

App symbols map to EAF app repositories and features, for example
`markdown-previewer' loads `eaf-markdown-previewer'."
  :type '(repeat symbol)
  :group 'org-seq)

(defcustom my/eaf-install-apps
  '(markdown-previewer browser pdf-viewer file-manager pyqterminal image-viewer org-previewer video-player)
  "EAF applications installed by `my/eaf-install-or-update'."
  :type '(repeat symbol)
  :group 'org-seq)

(defcustom my/eaf-clean-broken-apps-before-install t
  "When non-nil, remove requested EAF app directories that are not git repos.

This fixes interrupted installs where `app/browser' exists but lacks `.git',
which makes EAF's installer try to clone into a non-empty directory."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-install-python-deps-into-selected-python t
  "When non-nil, force EAF installer pip calls through `my/python-command'.

EAF's upstream installer normally calls `pip3' from PATH.  On Windows this can
install dependencies into a different Python than EAF uses at runtime.  org-seq
wraps pip/pip3 during install so dependencies land in the selected conda/uv
Python instead."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-core-python-packages
  '("epc" "sexpdata==1.0.0" "tld" "lxml" "pygetwindow"
    "PyQt6==6.5.0" "PyQt6-Qt6==6.5.0" "PyQt6-sip"
    "PyQt6-WebEngine==6.5.0" "PyQt6-WebEngine-Qt6==6.5.0")
  "Core Python packages installed into `my/python-command' for EAF."
  :type '(repeat string)
  :group 'org-seq)

(defcustom my/eaf-delete-invalid-git-dirs t
  "When non-nil, delete EAF core/app directories with invalid git metadata.

This is intentionally aggressive because interrupted EAF installs often leave
non-empty app directories that are not usable git repositories, causing the
upstream installer to clone into an existing directory and fail."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-use-as-default-browser nil
  "When non-nil, make EAF Browser the default `browse-url' backend."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-browser-continue-where-left-off t
  "When non-nil, EAF Browser restores previous tabs/session state."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-browser-enable-adblocker nil
  "When non-nil, enable EAF Browser ad blocking.

Community configs often keep this nil by default because WebEngine-level
blockers can cause site compatibility or startup issues; enable it if you
prefer built-in blocking over an external browser/proxy setup."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-browser-auto-import-chrome-cookies nil
  "When non-nil, ask EAF Browser to import Chrome cookies where supported."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-pdf-dark-mode nil
  "When non-nil, enable EAF PDF dark mode."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-pdf-click-to-copy t
  "When non-nil, clicking after selecting text in EAF PDF copies it."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-pdf-show-progress-on-page t
  "EAF PDF progress indicator setting.

Use t for the default progress indicator, nil to hide it, or an integer font
size to customize it."
  :type '(choice boolean integer)
  :group 'org-seq)

(defcustom my/eaf-pyqterminal-font-family nil
  "Font family for EAF PyQterminal, or nil to use EAF's default.

If you use icons in terminal programs, set this to a Nerd Font family such as
`CaskaydiaCove Nerd Font' or `JetBrainsMono Nerd Font'."
  :type '(choice (const :tag "EAF default" nil) string)
  :group 'org-seq)

(defcustom my/eaf-webengine-font-family nil
  "Preferred EAF WebEngine proportional font, or nil to auto-detect.

The auto-detection list prefers Sarasa Gothic SC for Chinese reading."
  :type '(choice (const :tag "Auto" nil) string)
  :group 'org-seq)

(defcustom my/eaf-webengine-fixed-font-family nil
  "Preferred EAF WebEngine fixed-width font, or nil to auto-detect.

The auto-detection list prefers Sarasa Mono/Term SC when available."
  :type '(choice (const :tag "Auto" nil) string)
  :group 'org-seq)

(defcustom my/eaf-webengine-serif-font-family nil
  "Preferred EAF WebEngine serif font, or nil to auto-detect.

EAF preview pages may request a CSS serif font.  For Chinese reading,
org-seq intentionally maps that slot to Sarasa Gothic before falling back to
other CJK sans-serif fonts, avoiding Windows Songti/SimSun rendering."
  :type '(choice (const :tag "Auto" nil) string)
  :group 'org-seq)

(defcustom my/eaf-webengine-font-size 18
  "Default EAF WebEngine font size."
  :type 'integer
  :group 'org-seq)

(defcustom my/eaf-pyqterminal-font-size nil
  "Font size for EAF PyQterminal.

When nil, derive the size from the current Emacs frame so EAF terminal text
matches the rest of org-seq."
  :type '(choice (const :tag "Follow Emacs default face" nil) integer)
  :group 'org-seq)

(defcustom my/eaf-pyqterminal-color-schema-from-emacs t
  "When non-nil, make EAF PyQterminal use Emacs terminal colors.

This lets PyQterminal follow the active org-seq theme instead of its built-in
Tango Dark palette."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-pyqterminal-refresh-ms 16
  "Refresh interval in milliseconds for EAF PyQterminal.

Community configs commonly use 16ms, roughly one 60Hz frame, for smoother
terminal rendering."
  :type 'integer
  :group 'org-seq)

(defcustom my/eaf-terminal-prefer-fish t
  "When non-nil, use fish in EAF PyQterminal on Unix when available."
  :type 'boolean
  :group 'org-seq)

(defcustom my/eaf-default-zoom-threshold 2000
  "Frame pixel width above which EAF WebEngine uses enlarged default zoom."
  :type 'integer
  :group 'org-seq)

(defcustom my/eaf-large-display-zoom 1.5
  "EAF WebEngine default zoom used on large displays."
  :type 'float
  :group 'org-seq)

(defcustom my/eaf-normal-display-zoom 1.0
  "EAF WebEngine default zoom used on normal displays."
  :type 'float
  :group 'org-seq)

(defun my/eaf--first-available-font (fonts)
  "Return the first installed font from FONTS, or nil."
  (cl-find-if (lambda (font) (find-font (font-spec :family font))) fonts))

(defun my/eaf--web-font-family ()
  "Return a CJK-friendly WebEngine proportional font."
  (or my/eaf-webengine-font-family
      (my/eaf--first-available-font
       '("Sarasa Gothic SC" "Sarasa UI SC" "Sarasa Gothic CL"
         "Sarasa UI CL" "Microsoft YaHei UI" "Microsoft YaHei"
         "Noto Sans CJK SC" "Source Han Sans SC" "WenQuanYi Micro Hei"
         "PingFang SC" "Arial"))))

(defun my/eaf--web-fixed-font-family ()
  "Return a CJK-friendly WebEngine fixed-width font."
  (or my/eaf-webengine-fixed-font-family
      (my/eaf--first-available-font
       '("Sarasa Mono SC" "Sarasa Term SC" "Sarasa Fixed SC"
         "CaskaydiaCove Nerd Font" "Cascadia Code" "JetBrainsMono Nerd Font"
         "JetBrains Mono" "FiraCode Nerd Font Mono" "Consolas"))))

(defun my/eaf--web-serif-font-family ()
  "Return a CJK-friendly WebEngine serif-slot reading font."
  (or my/eaf-webengine-serif-font-family
      (my/eaf--first-available-font
       '("Sarasa Gothic SC" "Sarasa UI SC" "Sarasa Gothic CL"
         "Sarasa UI CL" "Microsoft YaHei UI" "Microsoft YaHei"
         "Noto Sans CJK SC" "Source Han Sans SC" "PingFang SC"))))

(defun my/eaf--terminal-font-family ()
  "Return a community-tuned terminal font."
  (or my/eaf-pyqterminal-font-family
      (my/eaf--first-available-font
       '("CaskaydiaCove Nerd Font" "JetBrainsMono Nerd Font"
         "FiraCode Nerd Font Mono" "Cascadia Mono" "Consolas"))))

(defun my/eaf--terminal-font-size ()
  "Return a PyQterminal font size matching the current Emacs frame."
  (or my/eaf-pyqterminal-font-size
      (max 1 (frame-char-height))))

(defun my/eaf--default-zoom ()
  "Return EAF WebEngine default zoom for the current frame."
  (if (> (frame-pixel-width) my/eaf-default-zoom-threshold)
      my/eaf-large-display-zoom
    my/eaf-normal-display-zoom))

(defun my/eaf--set-if-non-nil (symbol value)
  "Set SYMBOL to VALUE when VALUE is non-nil."
  (when value
    (set symbol value)))

(defun my/eaf--bind-key (command key keymap-symbol)
  "Bind KEY to COMMAND string in EAF KEYMAP-SYMBOL when available.

This edits EAF's alist-style keybinding variables directly instead of calling
`eaf-bind-key', so it remains byte-compile friendly when EAF is not installed."
  (when (boundp keymap-symbol)
    (let ((bindings (symbol-value keymap-symbol)))
      (set keymap-symbol
           (if command
               (cons (cons key command)
                     (cl-remove key bindings :key #'car :test #'string=))
             (cl-remove key bindings :key #'car :test #'string=))))))

(defun my/eaf-apply-community-tuning ()
  "Apply community-inspired EAF defaults after EAF core/apps load."
  (interactive)
  (setq eaf-browser-continue-where-left-off my/eaf-browser-continue-where-left-off
        eaf-browser-enable-adblocker my/eaf-browser-enable-adblocker
        eaf-browser-enable-autofill t
        eaf-browser-auto-import-chrome-cookies my/eaf-browser-auto-import-chrome-cookies
        eaf-find-alternate-file-in-dired t
        eaf-file-manager-show-hidden-file nil
        eaf-goto-right-after-close-buffer t
        eaf-marker-letters "JKHLNMUIOYPFDSAVCRREW"
        eaf-pdf-dark-mode my/eaf-pdf-dark-mode
        eaf-pdf-click-to-copy my/eaf-pdf-click-to-copy
        eaf-pdf-show-progress-on-page my/eaf-pdf-show-progress-on-page
        eaf-pyqterminal-color-schema-from-emacs my/eaf-pyqterminal-color-schema-from-emacs
        eaf-pyqterminal-font-size (my/eaf--terminal-font-size)
        eaf-pyqterminal-refresh-ms my/eaf-pyqterminal-refresh-ms
        eaf-pyqterminal-cursor-type "box"
        eaf-python-command (or my/python-command "python")
        eaf-rebuild-buffer-after-crash nil
        eaf-webengine-default-zoom (my/eaf--default-zoom)
        eaf-webengine-font-size my/eaf-webengine-font-size
        eaf-webengine-fixed-font-size my/eaf-webengine-font-size
        eaf-evil-leader-key "SPC"
        eaf-enable-debug nil)
  (my/eaf--set-if-non-nil 'eaf-webengine-font-family
                          (my/eaf--web-font-family))
  (my/eaf--set-if-non-nil 'eaf-webengine-fixed-font-family
                          (my/eaf--web-fixed-font-family))
  (my/eaf--set-if-non-nil 'eaf-webengine-serif-font-family
                          (my/eaf--web-serif-font-family))
  (my/eaf--set-if-non-nil 'eaf-pyqterminal-font-family
                          (my/eaf--terminal-font-family))
  (my/eaf--bind-key "undo_action" "C-/" 'eaf-browser-keybinding)
  (my/eaf--bind-key "redo_action" "C-?" 'eaf-browser-keybinding)
  (my/eaf--bind-key "scroll_up" "M-j" 'eaf-browser-keybinding)
  (my/eaf--bind-key "scroll_down" "M-k" 'eaf-browser-keybinding)
  (my/eaf--bind-key "scroll_up_page" "M-n" 'eaf-browser-keybinding)
  (my/eaf--bind-key "scroll_down_page" "M-p" 'eaf-browser-keybinding)
  (my/eaf--bind-key "refresh_page" "M-r" 'eaf-browser-keybinding)
  (my/eaf--bind-key "scroll_up" "M-," 'eaf-pyqterminal-keybinding)
  (my/eaf--bind-key "scroll_down" "M-." 'eaf-pyqterminal-keybinding)
  (my/eaf--bind-key "eaf-send-backspace-key" "M-o" 'eaf-pyqterminal-keybinding))

(defun my/eaf-refresh-theme-integration (&rest _)
  "Refresh EAF variables that mirror the active Emacs theme."
  (when (featurep 'eaf)
    (my/eaf-apply-community-tuning)))

(add-hook 'enable-theme-functions #'my/eaf-refresh-theme-integration)

(defun my/eaf--directory ()
  "Return the normalized EAF installation directory."
  (file-name-as-directory (expand-file-name my/eaf-install-dir)))

(defun my/eaf--app-name (app)
  "Return APP as the EAF application name string."
  (if (symbolp app) (symbol-name app) app))

(defun my/eaf--feature (app)
  "Return APP's Elisp feature symbol."
  (intern (format "eaf-%s" (my/eaf--app-name app))))

(defun my/eaf--app-dir (app)
  "Return APP's EAF app directory."
  (expand-file-name (format "app/%s/" (my/eaf--app-name app))
                    (my/eaf--directory)))

(defun my/eaf--add-load-paths ()
  "Add EAF core and installed app directories to `load-path'."
  (let ((eaf-dir (my/eaf--directory)))
    (when (file-directory-p eaf-dir)
      (add-to-list 'load-path eaf-dir)
      (dolist (app my/eaf-enabled-apps)
        (let ((app-dir (my/eaf--app-dir app)))
          (when (file-directory-p app-dir)
            (add-to-list 'load-path app-dir)))))))

(defun my/eaf-installed-p ()
  "Return non-nil when EAF core appears to be installed."
  (file-exists-p (expand-file-name "eaf.el" (my/eaf--directory))))

(defun my/eaf--python-executable ()
  "Return the selected Python executable for EAF installation/runtime."
  (or my/python-command
      (and (fboundp 'my/python-detect) (my/python-detect))
      (executable-find "python")
      (executable-find "python3")))

(defun my/eaf--python-root (python)
  "Return environment root directory for PYTHON."
  (let* ((python (file-truename python))
         (dir (file-name-directory python))
         (base (file-name-nondirectory (directory-file-name dir))))
    (if (member base '("bin" "Scripts"))
        (file-name-directory (directory-file-name dir))
      dir)))

(defun my/eaf--python-env-paths (python)
  "Return PATH entries needed for PYTHON and its native libraries."
  (let ((root (my/eaf--python-root python)))
    (delq nil
          (if (eq system-type 'windows-nt)
              (list root
                    (expand-file-name "Scripts" root)
                    (expand-file-name "Library/bin" root)
                    (expand-file-name "Library/usr/bin" root))
            (list (expand-file-name "bin" root) root)))))

(defun my/eaf--write-pip-shim (dir python)
  "Write pip/pip3 shims into DIR that invoke PYTHON -m pip.

The shim strips EAF installer's `--user' and `--break-system-packages' flags so
packages are installed into the selected conda/uv Python instead of an unrelated
per-user Python directory."
  (make-directory dir t)
  (let* ((python-path (file-truename python))
         (script (expand-file-name "org-seq-pip-shim.py" dir))
         (cmd-template (if (eq system-type 'windows-nt)
                           (concat "@echo off\r\n\"" python-path "\" \"" script "\" %*\r\n")
                         (concat "#! /bin/sh\nexec \"" python-path "\" \"" script "\" \"$@\"\n"))))
    (with-temp-file script
      (insert "import subprocess, sys\n")
      (insert "args = [a for a in sys.argv[1:] if a not in ('--user', '--break-system-packages')]\n")
      (insert "raise SystemExit(subprocess.call([sys.executable, '-s', '-m', 'pip'] + args))\n"))
    (dolist (name (if (eq system-type 'windows-nt)
                      '("pip.cmd" "pip3.cmd" "pip.bat" "pip3.bat")
                    '("pip" "pip3")))
      (let ((file (expand-file-name name dir)))
        (with-temp-file file
          (insert cmd-template))
        (unless (eq system-type 'windows-nt)
          (set-file-modes file #o755))))))

(defun my/eaf--install-environment (python pip-shim-dir)
  "Return process environment that makes EAF installer use PYTHON."
  (let* ((paths (append (when my/eaf-install-python-deps-into-selected-python
                          (list pip-shim-dir))
                        (my/eaf--python-env-paths python)
                        exec-path))
         (path (mapconcat #'identity (delete-dups (copy-sequence paths)) path-separator)))
    (append (list (concat "PATH=" path)
                  "PYTHONNOUSERSITE=1")
            (cl-remove-if (lambda (entry)
                            (or (string-prefix-p "PATH=" entry)
                                (string-prefix-p "PYTHONHOME=" entry)
                                (string-prefix-p "PYTHONNOUSERSITE=" entry)))
                          process-environment))))

(defun my/eaf-clean-broken-apps (&optional apps)
  "Remove EAF APP directories that exist but are not git repositories.

When APPS is nil, inspect `my/eaf-install-apps'."
  (interactive)
  (let ((removed nil)
        (apps (or apps my/eaf-install-apps)))
    (dolist (app apps)
      (let ((dir (my/eaf--app-dir app)))
        (when (and (file-directory-p dir)
                   (not (file-directory-p (expand-file-name ".git" dir))))
          (delete-directory dir t)
          (push (my/eaf--app-name app) removed))))
    (if removed
        (message "org-seq: removed broken EAF app dirs: %s"
                 (string-join (nreverse removed) ", "))
      (message "org-seq: no broken EAF app dirs found"))
    removed))

(defun my/eaf--git-valid-p (dir)
  "Return non-nil when DIR is a usable git work tree."
  (and (file-directory-p dir)
       (file-directory-p (expand-file-name ".git" dir))
       (zerop (call-process "git" nil nil nil
                            "-C" dir "rev-parse" "--is-inside-work-tree"))))

(defun my/eaf--delete-invalid-git-dir (dir label)
  "Delete DIR when it exists but is not a valid git repository.

LABEL is used for status messages."
  (when (and my/eaf-delete-invalid-git-dirs
             (file-directory-p dir)
             (not (my/eaf--git-valid-p dir)))
    (message "org-seq: deleting invalid EAF git directory for %s: %s" label dir)
    (delete-directory dir t)
    t))

(defun my/eaf-validate-install-tree (&optional apps)
  "Validate EAF core and APP git directories before install/update.

Invalid non-empty directories are deleted when
`my/eaf-delete-invalid-git-dirs' is non-nil."
  (interactive)
  (let ((deleted nil))
    (when (my/eaf--delete-invalid-git-dir (my/eaf--directory) "core")
      (push "core" deleted))
    (when (file-directory-p (my/eaf--directory))
      (dolist (app (or apps my/eaf-install-apps))
        (let ((dir (my/eaf--app-dir app)))
          (when (my/eaf--delete-invalid-git-dir dir (my/eaf--app-name app))
            (push (my/eaf--app-name app) deleted)))))
    (if deleted
        (message "org-seq: deleted invalid EAF git dirs: %s"
                 (string-join (nreverse deleted) ", "))
      (message "org-seq: EAF git dirs look valid"))
    deleted))

(defun my/eaf-install-core-python-deps (python buffer)
  "Install EAF core Python dependencies into PYTHON, writing output to BUFFER."
  (let ((args (append (list "-s" "-m" "pip" "install" "-U")
                      my/eaf-core-python-packages)))
    (with-current-buffer buffer
      (insert (format "org-seq installing EAF core Python deps with: %s -s -m pip
" python)))
    (unless (zerop (apply #'call-process python nil buffer t args))
      (user-error "EAF Python dependency install failed; see %s"
                  (buffer-name buffer)))))

(defun my/eaf-install-instructions ()
  "Show manual EAF install/update commands for this configuration."
  (interactive)
  (let* ((dir (my/eaf--directory))
         (apps (mapconcat #'my/eaf--app-name my/eaf-install-apps " "))
         (buf (get-buffer-create "*org-seq EAF install*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "EAF is installed outside package.el.  Manual commands:\n\n")
        (insert (format "git clone --depth=1 -b master https://github.com/emacs-eaf/emacs-application-framework.git %s\n" dir))
        (insert (format "cd %s\n" dir))
        (insert "python install-eaf.py --install-core-deps\n")
        (insert (format "python install-eaf.py --install %s\n\n" apps))
        (insert "After installation, restart Emacs or run M-x my/eaf-reload.\n")
        (special-mode)))
    (pop-to-buffer buf)))

(defun my/eaf-install-or-update (&optional install-all-apps)
  "Clone/update EAF and install configured apps.

With prefix argument INSTALL-ALL-APPS, ask EAF's installer to install all apps.
Without prefix, install only `my/eaf-install-apps'.  EAF's upstream installer
uses `pip3' from PATH; org-seq temporarily shadows pip/pip3 so dependencies are
installed into `my/python-command'."
  (interactive "P")
  (unless (executable-find "git")
    (user-error "git not found on PATH"))
  (let ((python (my/eaf--python-executable)))
    (unless python
      (user-error "Python not found; inspect with M-x my/python-info"))
    (let* ((dir (my/eaf--directory))
           (script (expand-file-name "install-eaf.py" dir))
           (buffer (get-buffer-create "*org-seq EAF install*"))
           (pip-shim-dir (make-temp-file "org-seq-eaf-pip-" t))
           (process-environment process-environment)
           (exec-path exec-path))
      (unwind-protect
          (progn
            (when my/eaf-install-python-deps-into-selected-python
              (my/eaf--write-pip-shim pip-shim-dir python)
              (setq process-environment
                    (my/eaf--install-environment python pip-shim-dir))
              (setq exec-path (append (list pip-shim-dir)
                                      (my/eaf--python-env-paths python)
                                      exec-path)))
            (with-current-buffer buffer
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert (format "org-seq EAF install Python: %s
" python))
                (insert (format "org-seq EAF install cwd: %s
" dir))
                (insert (format "org-seq EAF install PATH head: %s

"
                                (mapconcat #'identity
                                           (cl-subseq exec-path 0 (min 5 (length exec-path)))
                                           path-separator)))))
            (pop-to-buffer buffer)
            (my/eaf-validate-install-tree (if install-all-apps nil my/eaf-install-apps))
            (unless (file-directory-p dir)
              (make-directory (file-name-directory (directory-file-name dir)) t)
              (unless (zerop (call-process "git" nil buffer t
                                           "clone" "--depth=1" "-b" "master"
                                           "https://github.com/emacs-eaf/emacs-application-framework.git"
                                           (directory-file-name dir)))
                (user-error "Failed to clone EAF; see %s" (buffer-name buffer))))
            (unless (zerop (call-process "git" nil buffer t "-C" dir "pull" "--ff-only"))
              (message "WARNING org-seq: EAF git pull failed; continuing with local checkout"))
            (unless (file-exists-p script)
              (user-error "EAF installer not found: %s" script))
            (when my/eaf-clean-broken-apps-before-install
              (my/eaf-clean-broken-apps (if install-all-apps nil my/eaf-install-apps)))
            (my/eaf-install-core-python-deps python buffer)
            (let ((args (if install-all-apps
                            (list script "--install-all-apps")
                          (append (list script "--install")
                                  (mapcar #'my/eaf--app-name my/eaf-install-apps)))))
              (let ((default-directory dir))
                (unless (zerop (apply #'call-process python nil buffer t args))
                  (user-error "EAF app install failed; see %s" (buffer-name buffer)))))
            (my/eaf-reload)
            (message "EAF install/update finished with Python: %s" python))
        (when (file-directory-p pip-shim-dir)
          (delete-directory pip-shim-dir t))))))

(defun my/eaf-reload ()
  "Reload EAF core and configured apps if they are installed."
  (interactive)
  (my/eaf--add-load-paths)
  (if (not (my/eaf-installed-p))
      (progn
        (message "EAF is not installed.  Run M-x my/eaf-install-or-update")
        nil)
    (condition-case err
        (progn
          (require 'eaf)
          (my/eaf-apply-community-tuning)
          (when my/eaf-use-as-default-browser
            (require 'eaf-browser nil t)
            (when (fboundp 'eaf-open-browser)
              (setq browse-url-browser-function #'eaf-open-browser)))
          (dolist (app my/eaf-enabled-apps)
            (let ((feature (my/eaf--feature app)))
              (unless (require feature nil t)
                (message "org-seq: EAF app not loaded: %s (install it with M-x my/eaf-install-or-update)"
                         feature))))
          ;; Re-apply after app features load so app keybinding alists and
          ;; app-local defcustoms are definitely present.
          (my/eaf-apply-community-tuning)
          t)
      (error
       (message "WARNING org-seq: failed to load EAF: %s" err)
       nil))))

(defun my/eaf--ensure (&optional app)
  "Ensure EAF core and optional APP are loaded, or signal a user error."
  (unless (or (featurep 'eaf) (my/eaf-reload))
    (user-error "EAF is not installed or failed to load; run M-x my/eaf-install-or-update"))
  (when app
    (let ((feature (my/eaf--feature app)))
      (unless (featurep feature)
        (my/eaf--add-load-paths)
        (unless (require feature nil t)
          (user-error "EAF app %s is not installed; run M-x my/eaf-install-or-update"
                      (my/eaf--app-name app)))))))

(defun my/eaf-open-file-as (app)
  "Open the current file with EAF APP."
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (my/eaf--ensure app)
  (save-buffer)
  (eaf-open (file-truename buffer-file-name) (my/eaf--app-name app)))

(defun my/eaf-open-markdown-preview ()
  "Preview the current Markdown file with EAF Markdown Previewer."
  (interactive)
  (unless (derived-mode-p 'markdown-mode 'gfm-mode)
    (user-error "Current buffer is not a Markdown buffer"))
  (my/eaf-open-file-as 'markdown-previewer))

(defun my/eaf-open-org-preview ()
  "Preview the current Org file with EAF Org Previewer."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not an Org buffer"))
  (my/eaf-open-file-as 'org-previewer))

(defun my/eaf-open-current-file ()
  "Open the current file with EAF's default app selection."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (my/eaf--ensure)
  (save-buffer)
  (eaf-open (file-truename buffer-file-name)))

(defun my/eaf-open-pdf ()
  "Open the current PDF file with EAF PDF Viewer."
  (interactive)
  (unless (and buffer-file-name
               (string-equal (downcase (or (file-name-extension buffer-file-name) ""))
                             "pdf"))
    (user-error "Current buffer is not visiting a PDF file"))
  (my/eaf-open-file-as 'pdf-viewer))

(defun my/eaf-open-file-manager (&optional directory)
  "Open DIRECTORY with EAF File Manager.

When DIRECTORY is nil, use the current dired directory, current file's parent,
or `default-directory'."
  (interactive)
  (my/eaf--ensure 'file-manager)
  (let ((dir (or directory
                 (if (derived-mode-p 'dired-mode)
                     default-directory
                   (or (and buffer-file-name (file-name-directory buffer-file-name))
                       default-directory)))))
    (eaf-open (file-truename dir) "file-manager")))

(defun my/eaf-open-terminal (&optional directory)
  "Open EAF PyQterminal in DIRECTORY.

When DIRECTORY is nil, use the current file's parent directory or
`default-directory'."
  (interactive)
  (my/eaf--ensure 'pyqterminal)
  (my/eaf-apply-community-tuning)
  (let ((dir (file-truename
              (or directory
                  (and buffer-file-name (file-name-directory buffer-file-name))
                  default-directory))))
    (cond
     ((fboundp 'eaf-pyqterminal-run-command-in-dir)
      (eaf-pyqterminal-run-command-in-dir
       (cond
        ((and my/eaf-terminal-prefer-fish
              (not (eq system-type 'windows-nt))
              (executable-find "fish"))
         "fish")
        ((eq system-type 'windows-nt) "powershell.exe")
        ((getenv "SHELL"))
        (t "sh"))
       dir t))
     ((fboundp 'eaf-open-pyqterminal)
      (let ((default-directory dir))
        (eaf-open-pyqterminal)))
     (t
      (eaf-open dir "pyqterminal")))))

(defun my/eaf-open-browser (&optional url)
  "Open URL with EAF Browser.  Prompt when URL is omitted."
  (interactive)
  (my/eaf--ensure 'browser)
  (let ((target (or url (read-string "EAF browser URL/search: "))))
    (if (fboundp 'eaf-open-browser)
        (eaf-open-browser target)
      (eaf-open target "browser"))))

(defun my/eaf-open-dired-file-manager ()
  "Open the current directory with EAF File Manager."
  (interactive)
  (my/eaf-open-file-manager))

(my/eaf-reload)

;; ---- Markdown local leader integration ----
(with-eval-after-load 'markdown-mode
  (keymap-set markdown-mode-map "C-c C-e" #'my/eaf-open-markdown-preview)
  (keymap-set gfm-mode-map "C-c C-e" #'my/eaf-open-markdown-preview))

(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'override
   :prefix "SPC"
   :global-prefix "M-SPC"
   "E"   '(:ignore t :wk "EAF")
   "Ei"  '(my/eaf-install-or-update :wk "Install/update EAF")
   "EI"  '(my/eaf-install-instructions :wk "Install notes")
   "Ec"  '(my/eaf-clean-broken-apps :wk "Clean broken apps")
   "EV"  '(my/eaf-validate-install-tree :wk "Validate git dirs")
   "Er"  '(my/eaf-reload :wk "Reload EAF")
   "ET"  '(my/eaf-apply-community-tuning :wk "Apply tuning")
   "Ef"  '(my/eaf-open-current-file :wk "Open current file")
   "Em"  '(my/eaf-open-markdown-preview :wk "Markdown preview")
   "Eo"  '(my/eaf-open-org-preview :wk "Org preview")
   "Eb"  '(my/eaf-open-browser :wk "Browser")
   "Ep"  '(my/eaf-open-pdf :wk "PDF viewer")
   "Ed"  '(my/eaf-open-file-manager :wk "File manager")
   "Et"  '(my/eaf-open-terminal :wk "Terminal")
   "Es"  '(eaf-stop-process :wk "Stop EAF process")))

(provide 'init-eaf)
;;; init-eaf.el ends here
