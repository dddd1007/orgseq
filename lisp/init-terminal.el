;;; init-terminal.el --- Ghostel terminal and popup integration -*- lexical-binding: t; -*-

;; Requires: init-popup (central display-buffer policy)
;; Requires: init-org   (my/note-home)

(require 'subr-x)

(defvar explicit-shell-file-name)
(defvar ghostel-buffer-name-function)
(defvar ghostel-kill-buffer-on-exit)
(defvar ghostel-module-auto-install)
(defvar ghostel-query-before-killing)
(defvar my/note-home)

(declare-function ghostel-exec "ghostel" (buffer program &optional args))
(declare-function ghostel-mode "ghostel" ())
(declare-function my/popup-display-buffer "init-popup" (buffer &optional overrides))

(use-package ghostel
  :defer t
  :commands (ghostel ghostel-exec ghostel-download-module)
  :custom
  (ghostel-module-auto-install 'ask))

(use-package evil-ghostel
  :after (ghostel evil)
  :hook (ghostel-mode . evil-ghostel-mode))

(define-obsolete-variable-alias
  'my/opencode-popup-height 'my/cli-popup-height "2026-05-03")

(defcustom my/cli-popup-height 0.38
  "Height of org-seq's bottom CLI popup windows.
A float means a fraction of the selected frame height; an integer means rows."
  :type '(choice (float :tag "Frame fraction")
                 (integer :tag "Rows"))
  :group 'org-seq)

(defcustom my/powershell-command "pwsh"
  "PowerShell executable used by Windows terminal wrappers."
  :type 'string
  :group 'org-seq)

(defcustom my/powershell-popup-arguments
  '("-NoLogo" "-NoExit" "-Command")
  "PowerShell arguments used when wrapping a TUI command in a popup."
  :type '(repeat string)
  :group 'org-seq)

(defcustom my/terminal-popup-command
  (if (eq system-type 'windows-nt)
      my/powershell-command
    (or explicit-shell-file-name shell-file-name))
  "Command used to start the default terminal popup."
  :type 'string
  :group 'org-seq)

(defcustom my/terminal-popup-arguments
  (when (eq system-type 'windows-nt)
    '("-NoLogo"))
  "Additional command-line arguments for `my/terminal-popup-command'."
  :type '(repeat string)
  :group 'org-seq)

(defcustom my/terminal-popup-buffer-name "*NoteHQ-terminal*"
  "Buffer name for the NoteHQ terminal popup session."
  :type 'string
  :group 'org-seq)

(defun my/cli-popup--buffer-name (buffer-name)
  "Return a normalized terminal BUFFER-NAME with surrounding stars."
  (let ((name (replace-regexp-in-string "\\`\\*+\\|\\*+\\'" ""
                                        buffer-name)))
    (format "*%s*" (if (string-empty-p name) "NoteHQ-cli" name))))

(defun my/cli-popup--resolve-command (command)
  "Return the executable path for COMMAND."
  (or (executable-find command)
      (when (file-executable-p command)
        command)
      (user-error "CLI command not found: %s" command)))

(defun my/cli-popup--window (buffer-name)
  "Return the visible CLI popup window for BUFFER-NAME, or nil."
  (when-let ((buffer (get-buffer (my/cli-popup--buffer-name buffer-name))))
    (get-buffer-window buffer nil)))

(defun my/cli-popup--directory (&optional directory)
  "Return DIRECTORY as a truename directory, defaulting to `my/note-home'."
  (let ((dir (file-name-as-directory
              (expand-file-name (or directory my/note-home)))))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun my/cli-popup--display-buffer (buffer &optional height)
  "Display BUFFER in a bottom side window and select it.
HEIGHT defaults to `my/cli-popup-height'."
  (my/popup-display-buffer
   buffer (list :height (or height my/cli-popup-height) :select t)))

(defun my/cli-popup-display-buffer (buffer &optional height)
  "Display BUFFER in org-seq's bottom CLI popup area."
  (my/cli-popup--display-buffer buffer height))

(defun my/cli-popup--show-buffer (buffer height display-kind)
  "Display BUFFER with HEIGHT according to DISPLAY-KIND.
DISPLAY-KIND is either `window' or `popup'."
  (pcase display-kind
    ('window (pop-to-buffer-same-window buffer))
    (_ (my/cli-popup--display-buffer buffer height))))

(defun my/cli-popup-kill (buffer-name)
  "Kill the Ghostel session BUFFER-NAME without a process confirmation."
  (when-let ((buffer (get-buffer (my/cli-popup--buffer-name buffer-name))))
    (with-current-buffer buffer
      (setq-local ghostel-query-before-killing nil))
    (kill-buffer buffer)))

(defun my/cli-popup--live-buffer (buffer-name)
  "Return the live Ghostel session for BUFFER-NAME, or nil."
  (when-let ((buffer (get-buffer (my/cli-popup--buffer-name buffer-name))))
    (with-current-buffer buffer
      (and (derived-mode-p 'ghostel-mode) buffer))))

(defun my/cli-popup-open
    (buffer-name command &optional arguments directory height restart
                 display-kind setup-function)
  "Open COMMAND with ARGUMENTS in a Ghostel session named BUFFER-NAME.
DIRECTORY defaults to `my/note-home'. HEIGHT controls popup size. When RESTART
is non-nil, recreate the session. DISPLAY-KIND is `popup' or `window'.
SETUP-FUNCTION, when non-nil, receives the initialized buffer before spawn."
  (require 'ghostel)
  (when restart
    (my/cli-popup-kill buffer-name))
  (if-let ((buffer (my/cli-popup--live-buffer buffer-name)))
      (progn
        (my/cli-popup--show-buffer buffer height display-kind)
        buffer)
    (when-let ((stale (get-buffer (my/cli-popup--buffer-name buffer-name))))
      (kill-buffer stale))
    (let* ((target-dir (my/cli-popup--directory directory))
           (resolved-command (my/cli-popup--resolve-command command))
           (buffer (get-buffer-create
                    (my/cli-popup--buffer-name buffer-name))))
      (condition-case err
          (progn
            (with-current-buffer buffer
              (ghostel-mode)
              (setq-local default-directory target-dir)
              (setq-local ghostel-buffer-name-function nil)
              (setq-local ghostel-kill-buffer-on-exit t))
            (my/cli-popup--show-buffer buffer height display-kind)
            (when setup-function
              (funcall setup-function buffer))
            (with-current-buffer buffer
              (ghostel-exec buffer resolved-command arguments))
            buffer)
        (error
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (setq-local ghostel-query-before-killing nil))
           (kill-buffer buffer))
         (signal (car err) (cdr err)))))))

(defun my/cli-popup-toggle
    (buffer-name command &optional arguments directory height restart)
  "Toggle BUFFER-NAME running COMMAND with ARGUMENTS in a bottom popup."
  (if-let ((window (and (not restart)
                        (my/cli-popup--window buffer-name))))
      (delete-window window)
    (my/cli-popup-open buffer-name command arguments directory height restart)))

(defun my/terminal-popup-toggle (&optional restart)
  "Toggle the NoteHQ Ghostel popup.
With prefix argument RESTART, kill and recreate the terminal session."
  (interactive "P")
  (my/cli-popup-toggle
   my/terminal-popup-buffer-name
   my/terminal-popup-command
   my/terminal-popup-arguments
   my/note-home
   my/cli-popup-height
   restart))

(provide 'init-terminal)
;;; init-terminal.el ends here
