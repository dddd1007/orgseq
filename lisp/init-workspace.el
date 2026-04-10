;;; init-workspace.el --- Three-column workspace layout -*- lexical-binding: t; -*-

;; Requires: init-org   (my/note-home)
;; Requires: init-dired (dirvish + my/dirvish-side-* helpers)
(defvar my/note-home)

(require 'cl-lib)
(require 'subr-x)

(defcustom my/workspace-startup-delay 0.3
  "Idle delay (seconds) before opening the startup workspace layout.
Gives package autoloads (dirvish, dashboard, nerd-icons) time to settle
before the layout function tries to attach them.  Increase on slow systems
if the sidebar fails to open on startup."
  :type 'number
  :group 'org-seq)

;; Layout (16:9 display):
;;   ┌──────────┬────────────────────────┬────────────┐
;;   │ dirvish- │                        │  outline   │
;;   │  side    │     main editor        │   (~20%)   │
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

;; The sidebar is provided by `dirvish-side' from init-dired.el.
;; Helper functions live there: `my/dirvish-side-open-at-notehq',
;; `my/dirvish-side-toggle', `my/dirvish-side-visible-p'.

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

(defun my/workspace--non-sidebar-windows ()
  "Return the list of windows that are NOT the dirvish sidebar or other side panes."
  (cl-remove-if (lambda (w)
                  (or (eq (window-parameter w 'window-side) 'left)
                      (eq (window-parameter w 'window-side) 'right)
                      (eq (window-parameter w 'window-side) 'bottom)
                      (eq (window-parameter w 'window-side) 'top)))
                (window-list nil 'no-minibuffer)))

(defun my/workspace-open-terminal ()
  "Open eshell terminal in the selected window, rooted at NoteHQ."
  (let ((default-directory my/note-home))
    (make-directory default-directory t)
    (let ((buf (eshell 'new)))
      (with-current-buffer buf
        (rename-buffer "*NoteHQ-term*" t)))))

(defun my/workspace-setup ()
  "Set up three-column workspace layout.
Wrapped in `condition-case' so a failure (e.g. dirvish not yet loaded,
display window too small) leaves the user with a usable Emacs instead
of a half-built layout."
  (interactive)
  (condition-case err
      (progn
        (delete-other-windows)

        ;; Step 1: dirvish sidebar on the left (uses Emacs side-window slot)
        (my/dirvish-side-open-at-notehq)

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
  "Startup layout: dirvish sidebar + dashboard. Outline and terminal are on demand.
Wrapped in `condition-case' so a failure during emacs-startup-hook does
not break other startup hooks or leave the frame empty."
  (condition-case err
      (progn
        (delete-other-windows)
        (my/dirvish-side-open-at-notehq)
        (let ((editor-win (car (my/workspace--non-sidebar-windows))))
          (when editor-win
            (select-window editor-win)
            (when-let ((dash (get-buffer "*dashboard*")))
              (switch-to-buffer dash)))))
    (error
     (message "WARNING org-seq: workspace startup failed: %s" err))))

(defalias 'my/workspace-toggle-sidebar 'my/dirvish-side-toggle
  "Toggle the dirvish-side sidebar.  Thin alias over `my/dirvish-side-toggle'
so existing leader keys (`SPC l t') don't need to change.")

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

;; Startup: lightweight layout (dirvish sidebar + dashboard, no terminal)
;; Use SPC l l for full 3-column layout with terminal.
;;
;; The delay (`my/workspace-startup-delay') gives package autoloads
;; (dirvish, dashboard, nerd-icons) time to register before the layout
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
