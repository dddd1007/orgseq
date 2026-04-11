;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

;; Requires: init-org   (my/note-home)
;; Requires: init-dired (dirvish as general file manager)
(defvar my/note-home)

(require 'cl-lib)
(require 'subr-x)

(defcustom my/workspace-startup-delay 0.3
  "Idle delay (seconds) before opening the startup workspace layout.
Gives package autoloads (treemacs, dashboard, nerd-icons) time to settle
before the layout function tries to attach them.  Increase on slow systems
if the sidebar fails to open on startup."
  :type 'number
  :group 'org-seq)

(defcustom my/workspace-sidebar-width 36
  "Preferred treemacs sidebar width in columns.

The value is intentionally a bit wider than treemacs defaults so mixed
English/CJK note names remain readable in the left navigation tree."
  :type 'integer
  :group 'org-seq)

(defcustom my/workspace-startup-focus-sidebar nil
  "When non-nil, focus treemacs after building the startup layout.

The default keeps focus on the dashboard/editor so startup remains calm.
Users who prefer a sidebar-first workflow can enable this option."
  :type 'boolean
  :group 'org-seq)

;; Layout (16:9 display):
;;   ┌──────────┬────────────────────────┬────────────┐
;;   │ treemacs │                        │  outline   │
;;   │ sidebar  │     main editor        │   (~20%)   │
;;   │ (~15%)   │       (~65%)           ├────────────┤
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

;; ---- treemacs: Doom-style project/file sidebar ----
(use-package treemacs
  :commands (treemacs treemacs-select-window treemacs-current-visibility
                      treemacs-get-local-window treemacs-find-file
                      treemacs-do-add-project-to-workspace
                      treemacs-goto-node treemacs-collapse-all-projects
                      treemacs-set-width treemacs-toggle-fixed-width
                      treemacs-follow-mode treemacs-filewatch-mode
                      treemacs-git-mode)
  :custom
  ;; Doom keeps follow-mode off by default because constant auto-jumps are
  ;; distracting.  For PKM workflows we keep startup similarly calm and use
  ;; one-shot reveal (`SPC l r`) when the user wants explicit navigation.
  (treemacs-follow-after-init nil)
  (treemacs-recenter-after-file-follow 'on-distance)
  (treemacs-recenter-distance 0.15)
  (treemacs-is-never-other-window t)
  (treemacs-no-delete-other-windows t)
  (treemacs-select-when-already-in-treemacs 'move-back)
  (treemacs-workspace-switch-cleanup 'files)
  (treemacs-width my/workspace-sidebar-width)
  (treemacs-width-is-initially-locked t)
  (treemacs-position 'left)
  (treemacs-show-hidden-files nil)
  (treemacs-no-png-images nil)
  (treemacs-collapse-dirs 0)
  (treemacs-sorting 'alphabetic-case-insensitive-asc)
  (treemacs-persist-file (expand-file-name ".cache/treemacs-persist" user-emacs-directory))
  (treemacs-last-error-persist-file
   (expand-file-name ".cache/treemacs-last-error-persist" user-emacs-directory))
  :config
  (treemacs-follow-mode -1)
  (treemacs-filewatch-mode 1)
  (treemacs-fringe-indicator-mode 'only-when-focused)
  (treemacs-git-mode 'simple))

(use-package treemacs-evil
  :after (treemacs evil))

(use-package treemacs-projectile
  :after (treemacs projectile))

(use-package treemacs-magit
  :after (treemacs magit))

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config
  (treemacs-load-theme "nerd-icons"))

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

(defun my/workspace-sidebar-visible-p ()
  "Return the live treemacs sidebar window in the current frame, or nil."
  (when (and (fboundp 'treemacs-current-visibility)
             (eq (treemacs-current-visibility) 'visible)
             (fboundp 'treemacs-get-local-window))
    (let ((window (treemacs-get-local-window)))
      (and (window-live-p window) window))))

(defun my/workspace-open-sidebar ()
  "Open treemacs rooted at NoteHQ.

This mirrors the old Doom-style workflow: the left sidebar is a stable
navigation tree for NoteHQ, while dirvish remains available separately as
the full-window file manager."
  (interactive)
  (require 'treemacs)
  (let ((note-dir (file-truename my/note-home)))
    (make-directory note-dir t)
    (unless (my/workspace-sidebar-visible-p)
      (treemacs))
    ;; `treemacs-do-add-project-to-workspace' is the project-local API the
    ;; previous treemacs sidebar implementation in this repo used.  Re-running
    ;; it lets us keep the sidebar rooted at NoteHQ across fresh sessions.
    (pcase (treemacs-do-add-project-to-workspace note-dir "NoteHQ")
      (`(success ,_project) nil)
      (`(duplicate-project ,_project) nil)
      (`(includes-project ,_project) nil)
      (`(duplicate-name ,_project) nil)
      (`(invalid-path ,reason)
       (message "WARNING org-seq: treemacs NoteHQ root invalid: %s" reason))
      (`(invalid-name ,name)
       (message "WARNING org-seq: treemacs NoteHQ project name invalid: %s" name)))))

(defun my/workspace-focus-sidebar ()
  "Focus the treemacs sidebar, opening it first if necessary."
  (interactive)
  (my/workspace-open-sidebar)
  (treemacs-select-window))

(defun my/workspace-sidebar-jump-to-notehq ()
  "Focus treemacs and jump to the NoteHQ root node."
  (interactive)
  (let ((note-dir (file-truename my/note-home)))
    (my/workspace-focus-sidebar)
    (treemacs-goto-node note-dir)))

(defun my/workspace-reveal-sidebar ()
  "Reveal the current file in treemacs without enabling follow-mode."
  (interactive)
  (if (or buffer-file-name default-directory)
      (let ((origin (selected-window)))
        (my/workspace-open-sidebar)
        (when (window-live-p origin)
          (select-window origin))
        (treemacs-find-file))
    (message "org-seq: current buffer is not visiting a file")))

(defun my/workspace-reveal-and-focus-sidebar ()
  "Reveal the current file in treemacs and then focus the sidebar."
  (interactive)
  (my/workspace-reveal-sidebar)
  (my/workspace-focus-sidebar))

(defun my/workspace-sidebar-collapse-all ()
  "Collapse all expanded nodes in treemacs for a clean tree view."
  (interactive)
  (my/workspace-open-sidebar)
  (treemacs-collapse-all-projects))

(defun my/workspace-sidebar-set-width ()
  "Interactively set the treemacs sidebar width.

This wraps `treemacs-set-width' and also stores the chosen width in
`my/workspace-sidebar-width' for the current session's later layout calls.
The chosen width is also persisted via Customize."
  (interactive)
  (require 'treemacs)
  (treemacs-set-width)
  (setq my/workspace-sidebar-width treemacs-width)
  (customize-save-variable 'my/workspace-sidebar-width treemacs-width))

(defun my/workspace-sidebar-toggle-width-lock ()
  "Toggle whether the treemacs sidebar keeps a fixed width."
  (interactive)
  (require 'treemacs)
  (treemacs-toggle-fixed-width))

(defun my/workspace--non-sidebar-windows ()
  "Return the list of windows that are NOT the treemacs sidebar or other side panes."
  (cl-remove-if (lambda (w)
                  (or (eq (window-parameter w 'window-side) 'left)
                      (eq (window-parameter w 'window-side) 'right)
                      (eq (window-parameter w 'window-side) 'bottom)
                       (eq (window-parameter w 'window-side) 'top)))
                 (window-list nil 'no-minibuffer)))

(defun my/workspace--main-window ()
  "Return a live non-side window suitable for workspace layout changes."
  (or (car (my/workspace--non-sidebar-windows))
      (let ((selected (selected-window)))
        (unless (window-parameter selected 'window-side)
          selected))))

(defun my/workspace-open-terminal ()
  "Open eshell terminal in the selected window, rooted at NoteHQ."
  (let ((default-directory my/note-home))
    (make-directory default-directory t)
    (let ((buf (eshell 'new)))
      (with-current-buffer buf
        (rename-buffer "*NoteHQ-term*" t)))))

(defun my/workspace-setup ()
  "Set up three-column workspace layout.
Wrapped in `condition-case' so a failure (e.g. treemacs not yet loaded,
display window too small) leaves the user with a usable Emacs instead
of a half-built layout."
  (interactive)
  (condition-case err
      (progn
        (let ((editor-win (my/workspace--main-window)))
          (unless editor-win
            (user-error "No editable window available for workspace layout"))
          (select-window editor-win)
          (delete-other-windows editor-win))

         ;; Step 1: treemacs sidebar on the left (uses Emacs side-window slot)
         (my/workspace-open-sidebar)

        ;; Step 2: select the main (non-side) window as the editor
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when editor-win
            (select-window editor-win)

            ;; Step 3: split editor -> editor (~80%) | right panel (~20%)
            (let* ((right-cols (max 28 (floor (* (window-total-width editor-win) 0.20))))
                   (right-win (split-window editor-win
                                            (- (window-total-width editor-win) right-cols)
                                            'right)))

              ;; Step 4: right panel -> outline (top 60%) | terminal (bottom 40%)
              (let* ((term-rows (max 8 (floor (* (window-total-height right-win) 0.40))))
                     (term-win (split-window right-win
                                              (- (window-total-height right-win) term-rows)
                                              'below)))
                (select-window term-win)
                (my/workspace-open-terminal))

              ;; Enable imenu-list from editor window so it tracks the right buffer
              (select-window editor-win)
              (imenu-list-minor-mode 1))))

        ;; Step 5: focus back to main editor, show dashboard if no file is open
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when editor-win
            (select-window editor-win)
            (when-let ((dash (get-buffer "*dashboard*")))
              (unless (cl-some #'buffer-file-name (buffer-list))
                (switch-to-buffer dash))))))
    (error
     (message "WARNING org-seq: workspace setup failed: %s" err))))

(defun my/workspace-startup ()
  "Startup layout: treemacs sidebar + dashboard. Outline and terminal are on demand.
Wrapped in `condition-case' so a failure during emacs-startup-hook does
not break other startup hooks or leave the frame empty."
  (condition-case err
      (progn
        (when-let ((editor-win (my/workspace--main-window)))
          (select-window editor-win)
          (delete-other-windows editor-win))
        (my/workspace-open-sidebar)
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when editor-win
            (select-window editor-win)
            (when-let ((dash (get-buffer "*dashboard*")))
              (switch-to-buffer dash))))
        (when my/workspace-startup-focus-sidebar
          (my/workspace-focus-sidebar)))
    (error
     (message "WARNING org-seq: workspace startup failed: %s" err))))

(defun my/workspace-toggle-sidebar ()
  "Toggle the treemacs sidebar."
  (interactive)
  (require 'treemacs)
  (pcase (treemacs-current-visibility)
    ('visible (delete-window (treemacs-get-local-window)))
    (_ (my/workspace-open-sidebar))))

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

;; Startup: lightweight layout (treemacs sidebar + dashboard, no terminal)
;; Use SPC l l for full 3-column layout with terminal.
;;
;; The delay (`my/workspace-startup-delay') gives package autoloads
;; (treemacs, dashboard, nerd-icons) time to register before the layout
;; function tries to attach them.  Use `run-with-idle-timer' so the layout
;; runs only after Emacs settles into idle, not after a fixed wall-clock
;; period -- this matches "ready to use" semantics across slow and fast
;; machines.
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (display-graphic-p)
              (run-with-idle-timer my/workspace-startup-delay nil
                                   #'my/workspace-startup))))

(provide 'init-workspace)
;;; init-workspace.el ends here
