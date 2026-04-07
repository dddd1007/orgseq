;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

;; Layout target (16:9 display):
;;   ┌──────────┬────────────────────────┬────────────┐
;;   │ treemacs │                        │  outline   │
;;   │  (~15%)  │     main editor        │   (~20%)   │
;;   │          │       (~65%)           ├────────────┤
;;   │          │                        │  terminal  │
;;   │          │                        │   (~20%)   │
;;   └──────────┴────────────────────────┴────────────┘

;; ---- Frame: maximized horizontal layout ----
(when (display-graphic-p)
  (push '(fullscreen . maximized) default-frame-alist))

;; ---- treemacs: file tree rooted at NoteHQ ----
(use-package treemacs
  :commands (treemacs treemacs-select-window)
  :custom
  (treemacs-width 30)
  (treemacs-width-is-initially-locked t)
  (treemacs-position 'left)
  (treemacs-show-hidden-files nil)
  (treemacs-no-png-images nil)
  (treemacs-indentation 2)
  (treemacs-sorting 'alphabetic-asc)
  :config
  (treemacs-follow-mode t)
  (treemacs-filewatch-mode t)
  (treemacs-fringe-indicator-mode 'always))

(use-package treemacs-evil
  :after (treemacs evil))

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config (treemacs-load-theme "nerd-icons"))

;; ---- imenu-list: outline sidebar ----
(use-package imenu-list
  :commands imenu-list-smart-toggle
  :custom
  (imenu-list-position 'right)
  (imenu-list-size 0.2)
  (imenu-list-focus-after-activation nil)
  (imenu-list-auto-resize nil))

;; ---- vterm: terminal emulator ----
;; ⚠️ Windows/MSYS2: vterm requires libvterm and CMake to compile.
;; If vterm fails to build, eat (Emulate A Terminal) is a pure-elisp fallback.
(if (and (eq system-type 'windows-nt)
         (not (locate-library "vterm")))
    (use-package eat
      :commands (eat eat-other-window)
      :custom
      (eat-term-name "xterm-256color"))
  (use-package vterm
    :commands (vterm vterm-other-window)
    :custom
    (vterm-max-scrollback 10000)
    (vterm-shell (if (eq system-type 'windows-nt)
                     (or (executable-find "bash")
                         "powershell")
                   (or (getenv "SHELL") "/bin/bash")))))

;; ---- Workspace orchestration ----

(defun my/workspace-open-treemacs ()
  "Open treemacs rooted at NoteHQ."
  (require 'treemacs)
  (let ((note-dir (file-truename "~/NoteHQ/")))
    (make-directory note-dir t)
    (unless (treemacs-current-visibility)
      (treemacs))
    (treemacs-do-add-project-to-workspace note-dir "NoteHQ")))

(defun my/workspace-open-outline ()
  "Open imenu-list outline in right side."
  (require 'imenu-list)
  (unless (get-buffer-window imenu-list-buffer-name)
    (imenu-list-smart-toggle)))

(defun my/workspace-open-terminal ()
  "Open terminal in bottom-right, rooted at NoteHQ."
  (let* ((note-dir (file-truename "~/NoteHQ/"))
         (default-directory note-dir)
         (term-buf (get-buffer "*NoteHQ-term*")))
    (make-directory note-dir t)
    (if (and term-buf (get-buffer-window term-buf))
        (select-window (get-buffer-window term-buf))
      ;; Find or create the terminal in a bottom-right split
      (when-let ((outline-win (get-buffer-window imenu-list-buffer-name)))
        (select-window outline-win))
      (let ((term-win (split-window-below)))
        (select-window term-win)
        (if (fboundp 'vterm)
            (progn (vterm "*NoteHQ-term*"))
          (if (fboundp 'eat)
              (progn (eat) (rename-buffer "*NoteHQ-term*" t))
            (progn (eshell) (rename-buffer "*NoteHQ-term*" t))))))))

(defun my/workspace-setup ()
  "Set up three-column workspace layout."
  (interactive)
  (delete-other-windows)
  ;; 1. Open treemacs on the left
  (my/workspace-open-treemacs)
  ;; 2. Select main editor window
  (other-window 1)
  ;; 3. Create right column: split for outline + terminal
  (let ((right-win (split-window-right (- (floor (* (frame-width) 0.20))))))
    ;; 4. Outline in right-top
    (select-window right-win)
    (my/workspace-open-outline)
    ;; 5. Terminal in right-bottom
    (my/workspace-open-terminal))
  ;; 6. Return focus to main editor
  (windmove-left)
  (when (string-match "Treemacs" (buffer-name))
    (windmove-right)))

(defun my/workspace-toggle-sidebar ()
  "Toggle treemacs sidebar."
  (interactive)
  (require 'treemacs)
  (pcase (treemacs-current-visibility)
    ('visible (delete-window (treemacs-get-local-window)))
    (_ (my/workspace-open-treemacs))))

(defun my/workspace-toggle-outline ()
  "Toggle imenu-list outline."
  (interactive)
  (imenu-list-smart-toggle))

(defun my/workspace-toggle-terminal ()
  "Toggle NoteHQ terminal."
  (interactive)
  (let ((term-buf (get-buffer "*NoteHQ-term*")))
    (if (and term-buf (get-buffer-window term-buf))
        (delete-window (get-buffer-window term-buf))
      (my/workspace-open-terminal))))

(provide 'init-workspace)
;;; init-workspace.el ends here
