;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

;; Layout (16:9 display):
;;   ┌──────────┬────────────────────────┬────────────┐
;;   │ treemacs │                        │  outline   │
;;   │  (~15%)  │     main editor        │   (~20%)   │
;;   │          │       (~65%)           ├────────────┤
;;   │          │                        │  terminal  │
;;   │          │                        │   (~20%)   │
;;   └──────────┴────────────────────────┴────────────┘

;; ---- Frame: large initial size for writing ----
(when (display-graphic-p)
  (let* ((fw (x-display-pixel-width))
         (fh (x-display-pixel-height))
         (w  (min (floor (* fw 0.88)) 1920))
         (h  (min (floor (* fh 0.90)) 1080)))
    (push `(width  . (text-pixels . ,w)) default-frame-alist)
    (push `(height . (text-pixels . ,h)) default-frame-alist)
    (push '(left . 0.5) default-frame-alist)
    (push '(top  . 0.5) default-frame-alist)))

;; ---- treemacs: file tree rooted at NoteHQ ----
;; Deferred: loaded when workspace-startup or workspace-setup runs (~0.3s after init)
(use-package treemacs
  :defer t
  :commands (treemacs treemacs-select-window treemacs-current-visibility
             treemacs-get-local-window treemacs-current-workspace
             treemacs-workspace->projects treemacs-project->path
             treemacs-do-add-project-to-workspace)
  :custom
  (treemacs-width 24)
  (treemacs-width-is-initially-locked t)
  (treemacs-position 'left)
  (treemacs-show-hidden-files nil)
  (treemacs-no-png-images nil)
  (treemacs-indentation 2)
  (treemacs-sorting 'alphabetic-asc)
  (treemacs-is-never-other-window nil)
  :config
  (treemacs-follow-mode t)
  (treemacs-fringe-indicator-mode 'always))

(use-package treemacs-evil
  :after (treemacs evil))

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config (treemacs-load-theme "nerd-icons"))

;; ---- imenu-list: outline sidebar ----
(use-package imenu-list
  :commands (imenu-list-smart-toggle imenu-list-minor-mode)
  :custom
  (imenu-list-position 'right)
  (imenu-list-size 0.20)
  (imenu-list-focus-after-activation nil)
  (imenu-list-auto-resize nil))

;; ---- Terminal: eshell (built-in, spawned on demand) ----
(setq eshell-directory-name (expand-file-name "eshell/" user-emacs-directory))

;; ---- Workspace orchestration ----

(defun my/workspace-open-treemacs ()
  "Open treemacs rooted at NoteHQ."
  (let ((note-dir my/note-home))
    (make-directory note-dir t)
    (treemacs-select-window)
    (let ((ws (treemacs-current-workspace)))
      (unless (cl-find (file-name-as-directory note-dir)
                       (treemacs-workspace->projects ws)
                       :test (lambda (a b)
                               (let ((b-norm (file-name-as-directory b)))
                                 (if (eq system-type 'windows-nt)
                                     (string= (downcase a) (downcase b-norm))
                                   (string= a b-norm))))
                       :key #'treemacs-project->path)
        (treemacs-do-add-project-to-workspace note-dir "NoteHQ")))))

(defun my/workspace-open-terminal ()
  "Open eshell terminal in the selected window, rooted at NoteHQ."
  (let ((default-directory my/note-home))
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

    ;; Step 3: split editor -> editor (~80%) | right panel (~20%)
    (let* ((right-cols (max 28 (floor (* (window-total-width editor-win) 0.20))))
           (right-win (split-window editor-win (- (window-total-width editor-win) right-cols)
                                    'right)))

      ;; Step 4: right panel -> outline (top 60%) | terminal (bottom 40%)
      (let* ((term-rows (max 8 (floor (* (window-total-height right-win) 0.40))))
             (term-win (split-window right-win (- (window-total-height right-win) term-rows)
                                     'below)))
        (select-window term-win)
        (my/workspace-open-terminal))

      ;; Enable imenu-list from editor window so it tracks the right buffer
      (select-window editor-win)
      (imenu-list-minor-mode 1)))

  ;; Step 5: focus back to main editor, show dashboard if no file is open
  (let ((editor-win (car (cl-remove-if
                          (lambda (w)
                            (string-match-p "\\*Treemacs\\|\\*Ilist\\|\\*NoteHQ"
                                            (buffer-name (window-buffer w))))
                          (window-list)))))
    (when editor-win
      (select-window editor-win)
      (when-let ((dash (get-buffer "*dashboard*")))
        (unless (cl-some #'buffer-file-name (buffer-list))
          (switch-to-buffer dash))))))

(defun my/workspace-startup ()
  "Startup layout: treemacs + dashboard. Outline and terminal are on demand."
  (delete-other-windows)
  (my/workspace-open-treemacs)
  (let ((editor-win (car (cl-remove-if
                          (lambda (w) (string-match-p "Treemacs"
                                                      (buffer-name (window-buffer w))))
                          (window-list)))))
    (when editor-win
      (select-window editor-win)
      (when-let ((dash (get-buffer "*dashboard*")))
        (switch-to-buffer dash)))))

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
  "Toggle NoteHQ terminal. When opening, split below the current window."
  (interactive)
  (let ((term-buf (get-buffer "*NoteHQ-term*")))
    (if (and term-buf (get-buffer-window term-buf))
        (delete-window (get-buffer-window term-buf))
      (let ((win (split-window nil (floor (* (window-total-height) 0.6)) 'below)))
        (select-window win)
        (if term-buf
            (switch-to-buffer term-buf)
          (my/workspace-open-terminal))))))

;; Startup: lightweight layout (treemacs + dashboard, no terminal)
;; Use SPC l l for full 3-column layout with terminal
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (display-graphic-p)
              (run-at-time 0.3 nil #'my/workspace-startup))))

(provide 'init-workspace)
;;; init-workspace.el ends here
