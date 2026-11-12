;;; init-ai-cli.el --- AI CLI popup sessions -*- lexical-binding: t; -*-
;;
;; Ghostel-backed bottom popups for external AI CLIs (Codex, OpenCode,
;; kimi-cli) plus the claude-code package, split out of init-ai.el: that
;; module owns gptel and the in-buffer AI commands; this module owns the
;; terminal-style CLI sessions rooted at `my/note-home'.
;; `init-terminal' owns Ghostel placement and popup lifecycle.

;; Requires: init-org (my/note-home)
;; Requires: init-packages (Git package bootstrap and source metadata)
;; Requires: init-terminal (Ghostel popup lifecycle)
(defvar claude-code-terminal-backend)
(defvar my/note-home)  ; forward-declare from init-org
(defvar my/cli-popup-height)
(defvar my/powershell-command)
(defvar my/powershell-popup-arguments)

(declare-function my/cli-popup--resolve-command "init-terminal" (command))
(declare-function my/cli-popup-kill "init-terminal" (buffer-name))
(declare-function my/cli-popup-open "init-terminal" (&rest arguments))
(declare-function my/cli-popup-toggle "init-terminal" (&rest arguments))
(declare-function my/vc-package-ensure "init-packages" (package))

;; ---- CLI commands and popup buffer names ----

(defcustom my/codex-command "codex"
  "Command used to start the Codex CLI."
  :type 'string
  :group 'org-seq)

(defcustom my/codex-arguments nil
  "Additional command-line arguments passed to `my/codex-command'."
  :type '(repeat string)
  :group 'org-seq)

(defcustom my/codex-use-powershell-wrapper (eq system-type 'windows-nt)
  "When non-nil, launch Codex through PowerShell in org-seq's popup.

This makes the Codex CLI see the same interactive PowerShell PATH and shim
behavior as a normal local terminal, which is especially helpful for npm
PowerShell shims such as codex.ps1 on Windows."
  :type 'boolean
  :group 'org-seq)

(defcustom my/codex-buffer-name "*NoteHQ-codex*"
  "Buffer name for the NoteHQ Codex CLI session."
  :type 'string
  :group 'org-seq)

(defcustom my/opencode-command "opencode"
  "Command used to start the OpenCode CLI."
  :type 'string
  :group 'org-seq)

(defcustom my/opencode-arguments nil
  "Additional command-line arguments passed to `my/opencode-command'."
  :type '(repeat string)
  :group 'org-seq)

(defcustom my/opencode-buffer-name "*NoteHQ-opencode*"
  "Buffer name for the NoteHQ OpenCode CLI session."
  :type 'string
  :group 'org-seq)

(defcustom my/kimi-cli-command "kimi-cli"
  "Command used to start kimi-cli."
  :type 'string
  :group 'org-seq)

(defcustom my/kimi-cli-arguments nil
  "Additional command-line arguments passed to `my/kimi-cli-command'."
  :type '(repeat string)
  :group 'org-seq)

(defcustom my/kimi-cli-buffer-name "*NoteHQ-kimi*"
  "Buffer name for the NoteHQ kimi-cli session."
  :type 'string
  :group 'org-seq)

;; ---- PowerShell wrapper helpers ----

(defun my/powershell--quote-argument (argument)
  "Return ARGUMENT as a single-quoted PowerShell token."
  (format "'%s'" (replace-regexp-in-string "'" "''" argument t t)))

(defun my/powershell--command-script (command &optional arguments)
  "Return a PowerShell script that invokes COMMAND with ARGUMENTS."
  (string-join
   (cons "&"
         (mapcar #'my/powershell--quote-argument
                 (cons (my/cli-popup--resolve-command command) arguments)))
   " "))

;; ---- Popup toggles ----

(defun my/codex--popup-command ()
  "Return the executable used to launch Codex in the popup."
  (if my/codex-use-powershell-wrapper
      my/powershell-command
    my/codex-command))

(defun my/codex--popup-arguments ()
  "Return the argument list used to launch Codex in the popup."
  (if my/codex-use-powershell-wrapper
      (append my/powershell-popup-arguments
              (list (my/powershell--command-script
                     my/codex-command my/codex-arguments)))
    my/codex-arguments))

(defun my/codex-popup-toggle (&optional restart)
  "Toggle the NoteHQ Codex CLI popup.
With prefix argument RESTART, kill and recreate the Codex session."
  (interactive "P")
  (my/cli-popup-toggle
   my/codex-buffer-name
   (my/codex--popup-command)
   (my/codex--popup-arguments)
   my/note-home
   my/cli-popup-height
   restart))

(defun my/opencode-open (&optional restart)
  "Open OpenCode in a bottom popup rooted at `my/note-home'.
With prefix argument RESTART, restart the existing OpenCode process first."
  (interactive "P")
  (my/cli-popup-open
   my/opencode-buffer-name
   my/opencode-command
   my/opencode-arguments
   my/note-home
   my/cli-popup-height
   restart))

(defun my/opencode-toggle (&optional restart)
  "Toggle the NoteHQ OpenCode popup.
With prefix argument RESTART, kill and recreate the OpenCode session."
  (interactive "P")
  (my/cli-popup-toggle
   my/opencode-buffer-name
   my/opencode-command
   my/opencode-arguments
   my/note-home
   my/cli-popup-height
   restart))

(defun my/opencode-kill ()
  "Kill the NoteHQ OpenCode session buffer and its running process."
  (interactive)
  (my/cli-popup-kill my/opencode-buffer-name))

(defun my/kimi-cli-popup-toggle (&optional restart)
  "Toggle the NoteHQ kimi-cli popup.
With prefix argument RESTART, kill and recreate the kimi-cli session."
  (interactive "P")
  (my/cli-popup-toggle
   my/kimi-cli-buffer-name
   my/kimi-cli-command
   my/kimi-cli-arguments
   my/note-home
   my/cli-popup-height
   restart))

;; ---- claude-code: Claude Code CLI inside Emacs ----
;; Runs Claude Code through its native Ghostel backend.

;; inheritenv: required by claude-code, must be installed before it
(use-package inheritenv :defer t)

;; Git source metadata and noninteractive policy live in init-packages.
(my/vc-package-ensure 'claude-code)

(setq claude-code-terminal-backend 'ghostel)

(use-package claude-code
  :if (locate-library "claude-code")
  :defer t
  :commands (claude-code claude-code-toggle claude-code-transient
             claude-code-send-region claude-code-send-command
             claude-code-send-command-with-context
             claude-code-fix-error-at-point)
  :custom
  (claude-code-enable-notifications t))

(provide 'init-ai-cli)
;;; init-ai-cli.el ends here
