;;; init-frame.el --- Adaptive GUI frame sizing and centering -*- lexical-binding: t; -*-
;;
;; Screen-aware frame geometry, split out of init-workspace.el: this module
;; owns how big a GUI frame should be and where it sits on the monitor;
;; init-workspace owns what windows appear inside the frame.
;;
;; NOTE(naming): functions and defcustoms keep the historical my/workspace-
;; prefix because they are referenced by leader bindings (SPC l F), saved
;; Customize values, and docs.  New frame-geometry code added here should
;; still use the my/workspace- prefix for consistency with that surface.

(require 'cl-lib)

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

(defun my/workspace--clamp (value min-value max-value)
  "Clamp VALUE between MIN-VALUE and MAX-VALUE."
  (max min-value (min max-value value)))

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
            #'my/workspace-apply-selected-client-frame-size))

(provide 'init-frame)
;;; init-frame.el ends here
