;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

;; Requires: init-org   (my/note-home)
;; Requires: init-dired (dirvish as general file manager)
(defvar my/note-home)

(require 'cl-lib)
(require 'subr-x)

(defvar eshell-directory-name)

(defcustom my/workspace-startup-delay 0.3
  "Idle delay (seconds) before opening the startup workspace layout.
Gives package autoloads (treemacs, dashboard, nerd-icons) time to settle
before the layout function tries to attach them.  Increase on slow systems
if the sidebar fails to open on startup."
  :type 'number
  :group 'org-seq)

(defcustom my/workspace-sidebar-width 36
  "Fallback treemacs sidebar width in columns.

When `my/workspace-adaptive-layout' is non-nil, org-seq computes a
screen-aware width instead and uses this value only as a conservative
fallback."
  :type 'integer
  :group 'org-seq)

(defcustom my/workspace-adaptive-layout t
  "When non-nil, size frames and workspace panes from the current display."
  :type 'boolean
  :group 'org-seq)

(defcustom my/workspace-frame-width-max 2400
  "Maximum startup frame width in pixels.

This keeps ultra-wide and 4K displays from turning prose buffers into a
runway.  The frame still gets centered and can be manually maximized."
  :type 'integer
  :group 'org-seq)

(defcustom my/workspace-frame-height-max 1360
  "Maximum startup frame height in pixels."
  :type 'integer
  :group 'org-seq)

(defcustom my/workspace-frame-margin-pixels 48
  "Minimum margin to keep around auto-sized GUI frames."
  :type 'integer
  :group 'org-seq)

(defcustom my/workspace-sidebar-width-range '(30 . 46)
  "Minimum and maximum adaptive treemacs sidebar width in columns."
  :type '(cons integer integer)
  :group 'org-seq)

(defcustom my/workspace-outline-width-range '(32 . 54)
  "Minimum and maximum adaptive outline sidebar width in columns."
  :type '(cons integer integer)
  :group 'org-seq)

(defcustom my/workspace-min-width-for-outline 108
  "Minimum editor-area width before the full outline column is created."
  :type 'integer
  :group 'org-seq)

(defcustom my/workspace-terminal-height-range '(8 . 18)
  "Minimum and maximum adaptive terminal height in rows."
  :type '(cons integer integer)
  :group 'org-seq)

(defcustom my/workspace-rebalance-on-resize t
  "When non-nil, rebalance managed workspace panes after frame resize."
  :type 'boolean
  :group 'org-seq)

(defcustom my/workspace-startup-focus-sidebar nil
  "When non-nil, focus treemacs after building the startup layout.

The default keeps focus on the dashboard/editor so startup remains calm.
Users who prefer a sidebar-first workflow can enable this option."
  :type 'boolean
  :group 'org-seq)

(defcustom my/workspace-open-sidebar-when-visiting-file nil
  "When non-nil, auto-open treemacs even if startup already visits a file.

Keeping this nil makes `emacs file.org' and `emacsclient -c file.org'
feel faster because the requested file becomes the only initial pane."
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

;; ---- Adaptive frame and pane sizing ----

(defvar my/workspace--resize-timer nil
  "Debounce timer for workspace pane rebalancing.")

(defvar my/workspace--rebalancing nil
  "Non-nil while org-seq is applying managed workspace sizes.")

(defun my/workspace--clamp (value min-value max-value)
  "Clamp VALUE between MIN-VALUE and MAX-VALUE."
  (max min-value (min max-value value)))

(defun my/workspace--range-min (range)
  "Return RANGE minimum."
  (car range))

(defun my/workspace--range-max (range)
  "Return RANGE maximum."
  (cdr range))

(defun my/workspace--monitor-workarea (&optional frame)
  "Return monitor workarea for FRAME as (LEFT TOP WIDTH HEIGHT)."
  (or (when (and (fboundp 'frame-monitor-attributes)
                 (display-graphic-p frame))
        (let* ((attrs (frame-monitor-attributes frame))
               (workarea (cdr (assq 'workarea attrs)))
               (geometry (cdr (assq 'geometry attrs))))
          (or workarea geometry)))
      (list 0 0 (display-pixel-width) (display-pixel-height))))

(defun my/workspace--frame-width-ratio (monitor-width)
  "Return an ergonomic frame width ratio for MONITOR-WIDTH pixels."
  (cond
   ((< monitor-width 1500) 0.98)
   ((< monitor-width 2000) 0.92)
   ((< monitor-width 2800) 0.86)
   ((< monitor-width 3600) 0.74)
   (t 0.66)))

(defun my/workspace--target-frame-geometry (&optional frame)
  "Return target GUI frame geometry for FRAME as (LEFT TOP WIDTH HEIGHT)."
  (cl-destructuring-bind (mx my mw mh) (my/workspace--monitor-workarea frame)
    (let* ((margin (min my/workspace-frame-margin-pixels
                        (max 0 (/ (min mw mh) 20))))
           (max-width (max 720 (min my/workspace-frame-width-max
                                    (- mw (* 2 margin)))))
           (max-height (max 560 (min my/workspace-frame-height-max
                                      (- mh (* 2 margin)))))
           (target-width (my/workspace--clamp
                          (floor (* mw (my/workspace--frame-width-ratio mw)))
                          (min 1180 max-width)
                          max-width))
           (target-height (my/workspace--clamp
                           (floor (* mh 0.90))
                           (min 760 max-height)
                           max-height))
           (left (+ mx (/ (- mw target-width) 2)))
           (top (+ my (/ (- mh target-height) 2))))
      (list left top target-width target-height))))

(defun my/workspace-install-frame-defaults ()
  "Install adaptive defaults for new GUI frames."
  (when (and my/workspace-adaptive-layout (display-graphic-p))
    (cl-destructuring-bind (_left _top width height)
        (my/workspace--target-frame-geometry)
      (push `(width . (text-pixels . ,width)) default-frame-alist)
      (push `(height . (text-pixels . ,height)) default-frame-alist))))

(defun my/workspace-apply-frame-size (&optional frame)
  "Resize and center FRAME from the current monitor workarea."
  (interactive)
  (let ((frame (or frame (selected-frame))))
    (when (and my/workspace-adaptive-layout
               (display-graphic-p frame)
               (not (memq (frame-parameter frame 'fullscreen)
                          '(fullboth maximized))))
      (cl-destructuring-bind (left top width height)
          (my/workspace--target-frame-geometry frame)
        (set-frame-size frame width height t)
        (set-frame-position frame left top)))))

(defun my/workspace-apply-frame-size-later (&optional frame)
  "Apply adaptive frame sizing to FRAME after the window system settles."
  (let ((frame (or frame (selected-frame))))
    (when (frame-live-p frame)
      (dolist (delay '(0.05 0.30))
        (run-with-idle-timer
         delay nil
         (lambda (target-frame)
           (when (frame-live-p target-frame)
             (my/workspace-apply-frame-size target-frame)))
         frame)))))

(defun my/workspace-apply-selected-client-frame-size ()
  "Apply adaptive sizing to the selected emacsclient frame."
  (my/workspace-apply-frame-size-later (selected-frame)))

(defun my/workspace-startup-later (&optional frame)
  "Open the startup workspace in FRAME after client buffers settle."
  (let ((frame (or frame (selected-frame))))
    (when (and (frame-live-p frame)
               (display-graphic-p frame))
      (run-with-idle-timer
       (max my/workspace-startup-delay 0.45)
       nil
       (lambda (target-frame)
         (when (and (frame-live-p target-frame)
                    (display-graphic-p target-frame))
           (with-selected-frame target-frame
             (my/workspace-startup target-frame))))
       frame))))

(defun my/workspace-startup-selected-client-frame ()
  "Open the default sidebar layout in the selected emacsclient frame."
  (my/workspace-startup-later (selected-frame)))

(defun my/workspace--target-sidebar-width (&optional frame)
  "Return adaptive treemacs sidebar width for FRAME."
  (if my/workspace-adaptive-layout
      (let* ((cols (frame-width frame))
             (min-width (my/workspace--range-min my/workspace-sidebar-width-range))
             (max-width (my/workspace--range-max my/workspace-sidebar-width-range)))
        (my/workspace--clamp (floor (* cols 0.17)) min-width max-width))
    my/workspace-sidebar-width))

(defun my/workspace--target-outline-width (&optional frame)
  "Return adaptive outline width for FRAME."
  (let* ((cols (frame-width frame))
         (min-width (my/workspace--range-min my/workspace-outline-width-range))
         (max-width (my/workspace--range-max my/workspace-outline-width-range))
         (ratio (cond
                 ((< cols 150) 0.22)
                 ((< cols 220) 0.20)
                 (t 0.18))))
    (my/workspace--clamp (floor (* cols ratio)) min-width max-width)))

(defun my/workspace--target-terminal-height (&optional window)
  "Return adaptive terminal height for WINDOW."
  (let* ((rows (window-total-height window))
         (min-height (my/workspace--range-min my/workspace-terminal-height-range))
         (max-height (my/workspace--range-max my/workspace-terminal-height-range)))
    (my/workspace--clamp (floor (* rows 0.34)) min-height max-height)))

(defun my/workspace--resize-window-width (window target-width)
  "Resize WINDOW horizontally to TARGET-WIDTH columns when possible."
  (when (and (window-live-p window) (> target-width 0))
    (let ((delta (- target-width (window-total-width window))))
      (unless (= delta 0)
        (condition-case nil
            (let ((window-size-fixed nil))
              (window-resize window delta t t))
          (error nil))))))

(defun my/workspace--resize-window-height (window target-height)
  "Resize WINDOW vertically to TARGET-HEIGHT rows when possible."
  (when (and (window-live-p window) (> target-height 0))
    (let ((delta (- target-height (window-total-height window))))
      (unless (= delta 0)
        (condition-case nil
            (let ((window-size-fixed nil))
              (window-resize window delta nil t))
          (error nil))))))

(my/workspace-install-frame-defaults)
(add-hook 'window-setup-hook #'my/workspace-apply-frame-size)

;; In daemon mode `after-make-frame-functions' runs for every new frame,
;; but server-client frames are also handled by `server-after-make-frame-hook'.
;; Skip client frames here to avoid double layout timer races.
(defun my/workspace--apply-frame-size-unless-client (frame)
  "Apply adaptive sizing to FRAME unless it's an emacsclient frame."
  (unless (frame-parameter frame 'client)
    (my/workspace-apply-frame-size-later frame)))

(add-hook 'after-make-frame-functions #'my/workspace--apply-frame-size-unless-client)

(with-eval-after-load 'server
  (add-hook 'server-after-make-frame-hook
            #'my/workspace-apply-selected-client-frame-size)
  (add-hook 'server-after-make-frame-hook
            #'my/workspace-startup-selected-client-frame))

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
  (treemacs-width (my/workspace--target-sidebar-width))
  (treemacs-width-is-initially-locked nil)
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
  (imenu-list-size (my/workspace--target-outline-width))
  (imenu-list-focus-after-activation nil)
  (imenu-list-auto-resize nil))

;; ---- Terminal: eshell (built-in, spawned on demand) ----
(setq eshell-directory-name (expand-file-name "eshell/" user-emacs-directory))

;; ---- Workspace orchestration ----

(defun my/workspace--set-layout-kind (kind)
  "Remember KIND as the current managed workspace layout for this frame."
  (set-frame-parameter nil 'my/workspace-layout-kind kind))

(defun my/workspace--utility-buffer-p (buffer)
  "Return non-nil when BUFFER is one of org-seq's managed utility panes."
  (let ((name (buffer-name buffer)))
    (or (string-prefix-p "*Treemacs" name)
        (member name '("*Ilist*" "*NoteHQ-term*")))))

(defun my/workspace--utility-window-p (window)
  "Return non-nil when WINDOW belongs to a managed sidebar or tool pane."
  (or (memq (window-parameter window 'window-side)
            '(left right bottom top))
      (my/workspace--utility-buffer-p (window-buffer window))))

(defun my/workspace--startup-target-buffer ()
  "Return the buffer that should stay in the main startup window."
  (let* ((buffer (window-buffer (selected-window)))
         (name (buffer-name buffer)))
    (cond
     ((and (buffer-live-p buffer)
           (not (my/workspace--utility-buffer-p buffer))
           (not (member name '("*scratch*" "*Messages*"))))
      buffer)
     ((get-buffer "*dashboard*"))
     ((buffer-live-p buffer) buffer))))

(defun my/workspace--startup-open-sidebar-p (buffer)
  "Return non-nil when startup should auto-open treemacs for BUFFER."
  (or my/workspace-open-sidebar-when-visiting-file
      (not (buffer-live-p buffer))
      (null (buffer-file-name buffer))))

(defun my/workspace-sidebar-visible-p ()
  "Return the live treemacs sidebar window in the current frame, or nil."
  (when (and (fboundp 'treemacs-current-visibility)
             (eq (treemacs-current-visibility) 'visible)
             (fboundp 'treemacs-get-local-window))
    (let ((window (treemacs-get-local-window)))
      (and (window-live-p window) window))))

(defun my/workspace--outline-window ()
  "Return the visible imenu-list outline window, or nil."
  (when (and (boundp 'imenu-list-buffer-name)
             (bufferp (get-buffer imenu-list-buffer-name)))
    (get-buffer-window imenu-list-buffer-name nil)))

(defun my/workspace--terminal-window ()
  "Return the visible NoteHQ terminal window, or nil."
  (when-let ((buffer (get-buffer "*NoteHQ-term*")))
    (get-buffer-window buffer nil)))

(defun my/workspace--apply-sidebar-width ()
  "Apply the adaptive treemacs sidebar width to the current frame."
  (let ((target-width (my/workspace--target-sidebar-width)))
    (when (boundp 'treemacs-width)
      (setq treemacs-width target-width))
    (when-let ((window (my/workspace-sidebar-visible-p)))
      (my/workspace--resize-window-width window target-width))))

(defun my/workspace--apply-outline-width ()
  "Apply the adaptive outline sidebar width to the current frame."
  (let ((target-width (my/workspace--target-outline-width)))
    (when (boundp 'imenu-list-size)
      (setq imenu-list-size target-width))
    (when-let ((window (my/workspace--outline-window)))
      (my/workspace--resize-window-width window target-width))))

(defun my/workspace--apply-terminal-height ()
  "Apply the adaptive terminal height to the current frame."
  (when-let ((window (my/workspace--terminal-window)))
    (my/workspace--resize-window-height
     window (my/workspace--target-terminal-height window))))

(defun my/workspace-rebalance (&optional frame)
  "Rebalance the managed workspace panes in FRAME."
  (interactive)
  (let ((frame (or frame (selected-frame))))
    (when (frame-live-p frame)
      (with-selected-frame frame
        (let ((my/workspace--rebalancing t))
          (my/workspace--apply-sidebar-width)
          (when (eq (frame-parameter frame 'my/workspace-layout-kind) 'editing)
            (my/workspace--apply-outline-width)
            (my/workspace--apply-terminal-height)))))))

(defun my/workspace--schedule-rebalance (&optional frame)
  "Debounce adaptive pane rebalancing for FRAME."
  (let ((frame (or frame (selected-frame))))
    (when (and my/workspace-rebalance-on-resize
               (not my/workspace--rebalancing)
               (frame-parameter frame 'my/workspace-layout-kind))
      (when my/workspace--resize-timer
        (cancel-timer my/workspace--resize-timer))
      (setq my/workspace--resize-timer
            (run-with-idle-timer 0.15 nil #'my/workspace-rebalance frame)))))

(add-hook 'window-size-change-functions #'my/workspace--schedule-rebalance)

(defun my/workspace-open-sidebar ()
  "Open treemacs rooted at NoteHQ.

This mirrors the old Doom-style workflow: the left sidebar is a stable
navigation tree for NoteHQ, while dirvish remains available separately as
the full-window file manager."
  (interactive)
  (require 'treemacs)
  (setq treemacs-width (my/workspace--target-sidebar-width))
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
       (message "WARNING org-seq: treemacs NoteHQ project name invalid: %s" name)))
    (my/workspace--apply-sidebar-width)))

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
  "Return windows suitable for the main editor area."
  (cl-remove-if #'my/workspace--utility-window-p
                 (window-list nil 'no-minibuffer)))

(defun my/workspace--main-window ()
  "Return a live non-side window suitable for workspace layout changes."
  (or (car (my/workspace--non-sidebar-windows))
      (let ((selected (selected-window)))
        (unless (my/workspace--utility-window-p selected)
          selected))))

(defun my/workspace-open-terminal ()
  "Open eshell terminal in the selected window, rooted at NoteHQ."
  (let ((default-directory my/note-home))
    (make-directory default-directory t)
    (if-let ((buffer (get-buffer "*NoteHQ-term*")))
        (switch-to-buffer buffer)
      (let ((buffer (eshell 'new)))
        (with-current-buffer buffer
          (rename-buffer "*NoteHQ-term*" t))))))

(defun my/workspace-setup ()
  "Set up three-column workspace layout.
Wrapped in `condition-case' so a failure (e.g. treemacs not yet loaded,
display window too small) leaves the user with a usable Emacs instead
of a half-built layout."
  (interactive)
  (condition-case err
      (progn
        (require 'imenu-list)
        (when (bound-and-true-p imenu-list-minor-mode)
          (imenu-list-minor-mode -1))

        (let ((editor-win (my/workspace--main-window)))
          (unless editor-win
            (user-error "No editable window available for workspace layout"))
          (select-window editor-win)
          (delete-other-windows editor-win))

        ;; Step 1: treemacs sidebar on the left (uses Emacs side-window slot).
        (my/workspace-open-sidebar)
        ;; Briefly wait for the side-window parameter to settle so that
        ;; `my/workspace--non-sidebar-windows' does not misclassify the sidebar
        ;; as the main editor area.
        (let ((n 0))
          (while (and (< n 20) (not (my/workspace-sidebar-visible-p)))
            (sit-for 0.01)
            (cl-incf n)))

        ;; Step 2: create a right outline column only when the editor area is
        ;; wide enough to keep the center column useful.
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when editor-win
            (select-window editor-win)
            (when (>= (window-total-width editor-win)
                      my/workspace-min-width-for-outline)
              (setq imenu-list-size (my/workspace--target-outline-width))
              (imenu-list-minor-mode 1)
              (my/workspace--apply-outline-width))))

        ;; Step 3: terminal lives under the center editor column, leaving the
        ;; right column for structure/navigation instead of command output.
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when (and editor-win (>= (window-total-height editor-win) 22))
            (select-window editor-win)
            (let* ((term-rows (my/workspace--target-terminal-height editor-win))
                   (term-win (split-window editor-win
                                            (- (window-total-height editor-win)
                                               term-rows)
                                            'below)))
              (select-window term-win)
              (my/workspace-open-terminal))))

        ;; Step 4: focus back to main editor, show dashboard if no file is open.
        (my/workspace--set-layout-kind 'editing)
        (my/workspace-rebalance)
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when editor-win
            (select-window editor-win)
            (when-let ((dash (get-buffer "*dashboard*")))
              (unless (cl-some #'buffer-file-name (buffer-list))
                (switch-to-buffer dash))))))
    (error
     (message "WARNING org-seq: workspace setup failed: %s" err))))

(defun my/workspace-startup (&optional frame)
  "Startup layout for FRAME: treemacs sidebar plus dashboard or client buffer.
Wrapped in `condition-case' so a failure during startup/client frame setup
does not break other hooks or leave the frame empty."
  (let ((frame (or frame (selected-frame))))
    (condition-case err
        (with-selected-frame frame
          (let* ((target-buffer (my/workspace--startup-target-buffer))
                 (open-sidebar (my/workspace--startup-open-sidebar-p
                                target-buffer)))
            (when-let ((editor-win (my/workspace--main-window)))
              (select-window editor-win)
              (delete-other-windows editor-win))
            (when open-sidebar
              (my/workspace-open-sidebar))
            (let ((editor-win (or (car (my/workspace--non-sidebar-windows))
                                  (selected-window))))
              (when editor-win
                (select-window editor-win)
                (when (buffer-live-p target-buffer)
                  (switch-to-buffer target-buffer))))
            (if open-sidebar
                (progn
                  (my/workspace--set-layout-kind 'startup)
                  (my/workspace-rebalance)
                  (when my/workspace-startup-focus-sidebar
                    (my/workspace-focus-sidebar)))
              (set-frame-parameter frame 'my/workspace-layout-kind nil))))
      (error
       (message "WARNING org-seq: workspace startup failed: %s" err)))))

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
  (require 'imenu-list)
  (setq imenu-list-size (my/workspace--target-outline-width))
  (imenu-list-smart-toggle)
  (my/workspace--apply-outline-width))

(defun my/workspace-toggle-terminal ()
  "Toggle NoteHQ terminal. When opening, split below the current window."
  (interactive)
  (let ((term-buf (get-buffer "*NoteHQ-term*")))
    (if (and term-buf (get-buffer-window term-buf))
        (delete-window (get-buffer-window term-buf))
      (let* ((base-win (or (my/workspace--main-window) (selected-window)))
             (term-rows (my/workspace--target-terminal-height base-win))
             (win (split-window base-win
                                (- (window-total-height base-win) term-rows)
                                'below)))
        (select-window win)
        (if term-buf
            (switch-to-buffer term-buf)
          (my/workspace-open-terminal))
        (my/workspace--apply-terminal-height)))))

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
              (my/workspace-startup-later (selected-frame)))))

(provide 'init-workspace)
;;; init-workspace.el ends here
