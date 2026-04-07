;;; init-evil.el --- Evil mode + SPC leader keys -*- lexical-binding: t; -*-

;; ---- Evil core ----
(use-package evil
  :demand t
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil        ; required by evil-collection
        evil-want-C-u-scroll t
        evil-want-C-i-jump nil          ; free C-i for org-mode TAB
        evil-want-Y-yank-to-eol t
        evil-undo-system 'undo-redo     ; Emacs 28+ native undo/redo
        evil-split-window-below t
        evil-vsplit-window-right t)
  :config
  (evil-mode 1)
  (evil-global-set-key 'motion "j" 'evil-next-visual-line)
  (evil-global-set-key 'motion "k" 'evil-previous-visual-line))

(use-package evil-collection
  :after evil
  :config (evil-collection-init))

;; ---- general.el: leader key framework ----
(use-package general
  :demand t
  :config
  (general-evil-setup t)

  ;; Primary leader: SPC (normal/visual/emacs), M-SPC (insert)
  (general-create-definer my/leader-keys
    :states '(normal visual emacs)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "M-SPC")

  ;; ---- Doom-style SPC key groups ----
  (my/leader-keys
    ;; Top-level shortcuts
    "SPC" '(execute-extended-command :wk "M-x")
    "."   '(find-file :wk "Find file")
    ","   '(consult-buffer :wk "Switch buffer")
    "/"   '(consult-ripgrep :wk "Project search")
    "TAB" '(evil-switch-to-windows-last-buffer :wk "Last buffer")

    ;; SPC b - Buffer
    "b"   '(:ignore t :wk "buffer")
    "bb"  '(consult-buffer :wk "Switch")
    "bd"  '(kill-current-buffer :wk "Kill")
    "bs"  '(save-buffer :wk "Save")

    ;; SPC f - File
    "f"   '(:ignore t :wk "file")
    "ff"  '(find-file :wk "Open file")
    "fr"  '(consult-recent-file :wk "Recent files")
    "fs"  '(save-buffer :wk "Save")
    "fp"  '((lambda () (interactive) (find-file user-init-file)) :wk "Config")

    ;; SPC w - Window
    "w"   '(:ignore t :wk "window")
    "wv"  '(evil-window-vsplit :wk "Vsplit")
    "ws"  '(evil-window-split :wk "Hsplit")
    "wd"  '(delete-window :wk "Close")
    "wm"  '(delete-other-windows :wk "Maximize")
    "wh"  '(evil-window-left :wk "Left")
    "wj"  '(evil-window-down :wk "Down")
    "wk"  '(evil-window-up :wk "Up")
    "wl"  '(evil-window-right :wk "Right")

    ;; SPC s - Search
    "s"   '(:ignore t :wk "search")
    "ss"  '(consult-line :wk "Buffer")
    "sp"  '(consult-ripgrep :wk "Project")
    "si"  '(consult-imenu :wk "Imenu")
    "so"  '(consult-outline :wk "Outline")

    ;; SPC n - Notes (PKM core)
    "n"   '(:ignore t :wk "notes")
    "nf"  '(org-roam-node-find :wk "Find note")
    "ni"  '(org-roam-node-insert :wk "Insert link")
    "nc"  '(org-roam-capture :wk "New note")
    "na"  '(my/org-open-task-dashboard :wk "Task dashboard")
    "np"  '(my/org-open-project-dashboard :wk "Project dashboard")
    "nr"  '(my/org-open-weekly-review :wk "Weekly review")
    "nt"  '(org-todo-list :wk "All tasks")
    "nb"  '(org-roam-buffer-toggle :wk "Backlinks")
    "nd"  '(org-roam-dailies-capture-today :wk "Daily note")
    "ng"  '(org-roam-ui-mode :wk "Graph view")
    "ns"  '(my/org-roam-rg-search :wk "Search notes")

    ;; SPC p - Project
    "p"   '(:ignore t :wk "project")
    "pp"  '(project-switch-project :wk "Switch project")
    "pf"  '(project-find-file :wk "Project file")

    ;; SPC g - Git
    "g"   '(:ignore t :wk "git")
    "gg"  '(magit-status :wk "Magit")

    ;; SPC h - Help
    "h"   '(:ignore t :wk "help")
    "hf"  '(describe-function :wk "Function")
    "hv"  '(describe-variable :wk "Variable")
    "hk"  '(describe-key :wk "Key")

    ;; SPC l - Layout / workspace
    "l"   '(:ignore t :wk "layout")
    "ll"  '(my/workspace-setup :wk "Open workspace")
    "lt"  '(my/workspace-toggle-sidebar :wk "Toggle treemacs")
    "lo"  '(my/workspace-toggle-outline :wk "Toggle outline")
    "le"  '(my/workspace-toggle-terminal :wk "Toggle terminal")

    ;; SPC t - Toggle
    "t"   '(:ignore t :wk "toggle")
    "tt"  '(consult-theme :wk "Theme")
    "tl"  '(display-line-numbers-mode :wk "Line numbers")

    ;; SPC q - Quit
    "q"   '(:ignore t :wk "quit")
    "qq"  '(save-buffers-kill-emacs :wk "Quit Emacs")))

;; ---- magit: Git interface ----
;; ⚠️ Windows: may be slow on large repos, set magit-git-executable to full path if needed
(use-package magit
  :commands magit-status)

;; ---- which-key: key hint popup ----
;; Built-in since Emacs 30; install from MELPA only on 29.
(if (>= emacs-major-version 30)
    (use-package which-key
      :ensure nil
      :demand t
      :init (which-key-mode)
      :config (setq which-key-idle-delay 0.3))
  (use-package which-key
    :demand t
    :init (which-key-mode)
    :config (setq which-key-idle-delay 0.3)))

;; ---- Auto-dismiss which-key popup after 10s of inactivity ----
(defvar my/which-key-auto-dismiss-seconds 10
  "Seconds of idle time before auto-dismissing the which-key popup.")

(run-with-idle-timer
 my/which-key-auto-dismiss-seconds t
 (lambda ()
   (when (and (fboundp 'which-key--popup-showing-p)
              (which-key--popup-showing-p))
     (if (fboundp 'which-key--hide-popup)
         (which-key--hide-popup)
       (when (fboundp 'which-key-abort)
         (which-key-abort))))))

(provide 'init-evil)
;;; init-evil.el ends here
