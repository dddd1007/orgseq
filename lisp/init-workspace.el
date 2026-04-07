;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

;; Layout (16:9 display):
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

;; ---- MSYS2 shell detection ----
(defvar my/workspace-shell
  (cond
   ((executable-find "bash") (executable-find "bash"))
   ((executable-find "powershell") (executable-find "powershell"))
   ((getenv "SHELL"))
   (t "cmd.exe"))
  "Shell to use for the workspace terminal.")

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

;; ---- Terminal: eshell (built-in, works on all platforms) ----
(setq eshell-directory-name (expand-file-name "eshell/" user-emacs-directory))
(when (eq system-type 'windows-nt)
  (setq explicit-shell-file-name my/workspace-shell))

;; ---- Workspace orchestration ----

(defun my/workspace-open-treemacs ()
  "Open treemacs rooted at NoteHQ."
  (let ((note-dir (file-truename "~/NoteHQ/")))
    (make-directory note-dir t)
    (treemacs-select-window)
    (let ((ws (treemacs-current-workspace)))
      (unless (cl-find note-dir
                       (treemacs-workspace->projects ws)
                       :test #'string=
                       :key #'treemacs-project->path)
        (treemacs-do-add-project-to-workspace note-dir "NoteHQ")))))

(defun my/workspace-open-terminal ()
  "Open eshell terminal in the selected window, rooted at NoteHQ."
  (let ((default-directory (file-truename "~/NoteHQ/")))
    (make-directory default-directory t)
    (let ((buf (eshell 'new)))
      (with-current-buffer buf
        (rename-buffer "*NoteHQ-term*" t)))))

(defun my/workspace-setup ()
  "Set up three-column workspace layout."
  (interactive)
  (delete-other-windows)

  ;; Step 1: treemacs on the left
  (my/workspace-open-treemacs)

  ;; Step 2: select the one non-treemacs window (main editor)
  (let ((editor-win (car (cl-remove-if
                          (lambda (w) (string-match-p "Treemacs"
                                                      (buffer-name (window-buffer w))))
                          (window-list)))))
    (select-window editor-win)

    ;; Step 3: split editor → editor (left ~78%) | right panel (~22%)
    (let* ((right-cols (max 30 (floor (* (window-total-width editor-win) 0.22))))
           (right-win (split-window editor-win (- (window-total-width editor-win) right-cols)
                                    'right)))

      ;; Step 4: right panel → outline (top 60%) | terminal (bottom 40%)
      (select-window right-win)
      (switch-to-buffer (get-buffer-create "*Ilist*"))
      (imenu-list-minor-mode 1)

      (let* ((term-rows (max 8 (floor (* (window-total-height right-win) 0.40))))
             (term-win (split-window right-win (- (window-total-height right-win) term-rows)
                                     'below)))
        (select-window term-win)
        (my/workspace-open-terminal))))

  ;; Step 5: focus back to main editor
  (let ((editor-win (car (cl-remove-if
                          (lambda (w)
                            (string-match-p "\\*Treemacs\\|\\*Ilist\\|\\*NoteHQ"
                                            (buffer-name (window-buffer w))))
                          (window-list)))))
    (when editor-win (select-window editor-win))))

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

;; Auto-open workspace on GUI startup
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (display-graphic-p)
              (run-at-time 0.5 nil #'my/workspace-setup))))

(provide 'init-workspace)
;;; init-workspace.el ends here
