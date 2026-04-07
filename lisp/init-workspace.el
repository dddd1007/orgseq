;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

;; Layout (16:9 display, ~1400x860 initial frame):
;;   ┌──────────┬────────────────────────┬────────────┐
;;   │ treemacs │                        │  outline   │
;;   │  (~15%)  │     main editor        │   (~20%)   │
;;   │          │       (~65%)           ├────────────┤
;;   │          │                        │  terminal  │
;;   │          │                        │   (~20%)   │
;;   └──────────┴────────────────────────┴────────────┘

;; ---- Frame: VSCode/Logseq-like initial size ----
(when (display-graphic-p)
  (let* ((fw (x-display-pixel-width))
         (fh (x-display-pixel-height))
         (w  (min (floor (* fw 0.75)) 1600))
         (h  (min (floor (* fh 0.80)) 960)))
    (push `(width  . (text-pixels . ,w)) default-frame-alist)
    (push `(height . (text-pixels . ,h)) default-frame-alist)
    (push '(left . 0.5) default-frame-alist)
    (push '(top  . 0.5) default-frame-alist)))

;; ---- treemacs: file tree rooted at NoteHQ ----
(use-package treemacs
  :demand t
  :custom
  (treemacs-width 30)
  (treemacs-width-is-initially-locked t)
  (treemacs-position 'left)
  (treemacs-show-hidden-files nil)
  (treemacs-no-png-images nil)
  (treemacs-indentation 2)
  (treemacs-sorting 'alphabetic-asc)
  (treemacs-is-never-other-window nil)
  :config
  (treemacs-follow-mode t)
  (treemacs-filewatch-mode t)
  (treemacs-fringe-indicator-mode 'always))

(use-package treemacs-evil
  :after (treemacs evil)
  :demand t)

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :demand t
  :config (treemacs-load-theme "nerd-icons"))

;; ---- imenu-list: outline sidebar ----
(use-package imenu-list
  :demand t
  :custom
  (imenu-list-position 'right)
  (imenu-list-size 0.23)
  (imenu-list-focus-after-activation nil)
  (imenu-list-auto-resize nil))

;; ---- Terminal ----
;; ⚠️ Windows/MSYS2: vterm needs libvterm + CMake.
;; Fallback chain: vterm → eat → eshell.
(cond
 ((and (eq system-type 'windows-nt)
       (not (locate-library "vterm")))
  (use-package eat
    :commands (eat eat-other-window)
    :custom (eat-term-name "xterm-256color")))
 (t
  (use-package vterm
    :commands (vterm vterm-other-window)
    :custom
    (vterm-max-scrollback 10000)
    (vterm-shell (if (eq system-type 'windows-nt)
                     (or (executable-find "bash") "powershell")
                   (or (getenv "SHELL") "/bin/bash"))))))

;; ---- Workspace orchestration ----

(defvar my/workspace--initialized nil)

(defun my/workspace-open-treemacs ()
  "Open treemacs rooted at NoteHQ."
  (let ((note-dir (file-truename "~/NoteHQ/")))
    (make-directory note-dir t)
    (treemacs-select-window)
    (unless (treemacs-is-treemacs-window-selected?)
      (treemacs))
    (let ((existing (treemacs-current-workspace)))
      (unless (cl-find note-dir
                       (treemacs-workspace->projects existing)
                       :test #'string=
                       :key #'treemacs-project->path)
        (treemacs-do-add-project-to-workspace note-dir "NoteHQ")))))

(defun my/workspace-open-terminal ()
  "Open terminal in bottom-right, rooted at NoteHQ."
  (let* ((note-dir (file-truename "~/NoteHQ/"))
         (default-directory note-dir)
         (term-buf (get-buffer "*NoteHQ-term*")))
    (make-directory note-dir t)
    (if (and term-buf (get-buffer-window term-buf))
        (select-window (get-buffer-window term-buf))
      (when-let ((outline-win (get-buffer-window
                               (get-buffer "*Ilist*"))))
        (select-window outline-win))
      (let ((term-win (split-window-below)))
        (select-window term-win)
        (cond
         ((fboundp 'vterm)  (vterm "*NoteHQ-term*"))
         ((fboundp 'eat)    (eat) (rename-buffer "*NoteHQ-term*" t))
         (t                 (eshell) (rename-buffer "*NoteHQ-term*" t)))))))

(defun my/workspace-setup ()
  "Set up three-column workspace layout."
  (interactive)
  (delete-other-windows)
  ;; Left: treemacs
  (my/workspace-open-treemacs)
  ;; Return to main editor
  (other-window 1)
  ;; Right column
  (split-window-right (- (floor (* (window-total-width) 0.78))))
  ;; Move to right column
  (windmove-right)
  ;; Top-right: outline
  (imenu-list-smart-toggle)
  ;; Bottom-right: terminal
  (my/workspace-open-terminal)
  ;; Focus main editor
  (select-window (get-buffer-window (other-buffer (current-buffer) t)))
  (when (string-match-p "\\*Treemacs\\|\\*Ilist\\|\\*NoteHQ" (buffer-name))
    (windmove-right))
  (setq my/workspace--initialized t))

(defun my/workspace-toggle-sidebar ()
  "Toggle treemacs sidebar."
  (interactive)
  (pcase (treemacs-current-visibility)
    ('visible (delete-window (treemacs-get-local-window)))
    (_        (my/workspace-open-treemacs))))

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

;; Auto-open workspace on startup
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (display-graphic-p)
              (run-at-time 0.5 nil #'my/workspace-setup))))

(provide 'init-workspace)
;;; init-workspace.el ends here
