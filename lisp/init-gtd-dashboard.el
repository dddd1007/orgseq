;;; init-gtd-dashboard.el --- Live-count GTD dashboard buffer -*- lexical-binding: t; -*-
;;
;; The *GTD* dashboard buffer and its auto-refresh machinery.  Split out of
;; init-gtd.el: that module owns the agenda views, state machine, and GTD
;; org configuration; this module owns the interactive dashboard rendered
;; from org-ql live counts plus the debounced refresh that keeps visible
;; GTD views current after captures and state changes.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │                       Table of Contents                          │
;; ├─────────────────────────────────────────────────────────────────┤
;; │ Section  1  GTD Dashboard buffer (*GTD*)                         │
;; │              live-count dashboard with projects + contexts;      │
;; │              `my/org-dashboard' is the main entry point          │
;; │                                                                  │
;; │ Section  2  Auto-refresh                                         │
;; │              debounced refresh on capture / state change /       │
;; │              schedule / deadline changes                         │
;; └─────────────────────────────────────────────────────────────────┘

;; Requires: init-gtd (agenda cache, view openers, GTD state predicates)

(require 'cl-lib)
(require 'org)
(require 'org-agenda)

(defvar org-agenda-overriding-header)
(defvar org-agenda-todo-keyword-format)
(defvar my/gtd-context-tags)  ; forward-declare from init-gtd
(declare-function org-ql-select "org-ql")
(declare-function my/org-refresh-agenda-files "init-gtd")
(declare-function my/org-roam-agenda-files "init-gtd" (&optional force))
(declare-function my/gtd--active-state-p "init-gtd" (state))
(declare-function my/org-open-inbox "init-gtd")
(declare-function my/org-open-today "init-gtd")
(declare-function my/org-open-upcoming "init-gtd")
(declare-function my/org-open-anytime "init-gtd")
(declare-function my/org-open-waiting "init-gtd")
(declare-function my/org-open-someday "init-gtd")
(declare-function my/org-open-logbook "init-gtd")

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: GTD Dashboard buffer (*GTD*)
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/gtd--refresh-timer nil
  "Debounce timer for refreshing visible GTD views.")

(defvar my/gtd-dashboard--active-ov nil
  "Overlay highlighting the last activated dashboard row.")

(define-derived-mode my/gtd-dashboard-mode special-mode "GTD"
  "Live-count GTD dashboard. RET or click opens the view at point."
  (setq-local mode-line-format nil)
  (setq-local cursor-type nil)
  (add-hook 'kill-buffer-hook #'my/gtd--cleanup-markers nil t)
  (add-hook 'kill-buffer-hook
            (lambda ()
              ;; Cancel orphaned refresh timer
              (when (timerp my/gtd--refresh-timer)
                (cancel-timer my/gtd--refresh-timer)
                (setq my/gtd--refresh-timer nil))
              ;; Clean up active row overlay
              (when (overlayp my/gtd-dashboard--active-ov)
                (delete-overlay my/gtd-dashboard--active-ov)
                (setq my/gtd-dashboard--active-ov nil)))
            nil t))



(defvar my/gtd--old-markers nil
  "Markers from previous dashboard render, freed on rebuild.")

(defun my/gtd--cleanup-markers ()
  "Free markers from the previous dashboard render."
  (dolist (m my/gtd--old-markers)
    (when (markerp m) (set-marker m nil)))
  (setq my/gtd--old-markers nil))

(defun my/gtd--dash-row (label count action)
  "Insert a dashboard row: LABEL, COUNT, ACTION on RET."
  (let ((start (point)))
    (insert (format "  %-14s%s" label
                    (cond ((or (equal count "") (eql count 0)) "")
                          ((stringp count) (format " %s" count))
                          (t (format " %d" count)))))
    (add-text-properties start (point)
                         (list 'gtd-action action 'mouse-face 'highlight)))
  (insert "\n"))

(defun my/gtd--dash-section (text)
  "Insert a non-clickable section label."
  (let ((start (point)))
    (insert (format "  %s\n" text))
    (add-text-properties start (point)
                         '(face (:inherit shadow :height 1.0)))))

(defun my/gtd-dashboard-activate ()
  "Open the GTD view for the current dashboard row."
  (interactive)
  (when-let ((action (get-text-property (point) 'gtd-action)))
    (when (overlayp my/gtd-dashboard--active-ov)
      (delete-overlay my/gtd-dashboard--active-ov))
    (setq my/gtd-dashboard--active-ov
          (make-overlay (line-beginning-position) (line-end-position)))
    (overlay-put my/gtd-dashboard--active-ov 'face 'secondary-selection)
    (let ((right (window-in-direction 'right)))
      (if right
          (with-selected-window right (funcall action))
        (funcall action)))))

(defun my/gtd--display-window ()
  "Return the best non-side window for displaying the GTD dashboard."
  (or (and (null (window-parameter (selected-window) 'window-side))
           (selected-window))
      (cl-find-if (lambda (window)
                    (null (window-parameter window 'window-side)))
                  (window-list nil 'no-minibuffer))))

(defun my/gtd--show-buffer (buffer)
  "Display BUFFER without flattening the current frame layout."
  (if-let ((window (get-buffer-window buffer nil)))
      (progn
        (select-window window)
        window)
    (let ((target (my/gtd--display-window)))
      (unless target
        (user-error "org-seq GTD: no non-side window available for dashboard"))
      (select-window target)
      (set-window-buffer target buffer)
      (unless (window-in-direction 'right target)
        (let ((right (split-window target (floor (* 0.7 (window-total-width target))) 'right)))
          (set-window-buffer right (or (get-buffer "*dashboard*")
                                       (get-buffer "*scratch*")
                                       (get-buffer-create "*scratch*")))))
      target)))

(defun my/org-dashboard ()
  "Toggle the GTD dashboard. If visible, close it; otherwise open it."
  (interactive)
  (let ((dash-win (get-buffer-window "*GTD*")))
    (if dash-win
        (delete-window dash-win)
      (my/org-dashboard--open))))

(defun my/org-dashboard--open ()
  "Build and display the GTD dashboard with live counts.
Uses org-ql for efficient querying across agenda files."
  (require 'org-ql)
  (my/org-refresh-agenda-files)
  (my/gtd--cleanup-markers)
  (let* ((files (my/org-roam-agenda-files))
         (inbox    (length (org-ql-select files
                             '(and (tags "fleeting") (not (todo)))
                             :action 'element)))
         (today    (length (org-ql-select files
                             '(and (not (done)) (not (todo "SOMEDAY"))
                                   (or (scheduled :on today) (deadline :to today)))
                             :action 'element)))
         (upcoming (length (org-ql-select files
                             '(and (not (done)) (not (todo "SOMEDAY"))
                                   (scheduled :from tomorrow))
                             :action 'element)))
         (anytime  (length (org-ql-select files
                             '(and (todo "NEXT") (not (scheduled)) (not (deadline)))
                             :action 'element)))
         (waiting  (length (org-ql-select files '(todo "WAITING") :action 'element)))
         (someday  (length (org-ql-select files '(todo "SOMEDAY") :action 'element)))
         (logbook  (length (org-ql-select files '(done) :action 'element)))
         (ctx-counts (mapcar
                      (lambda (tag)
                        (cons tag (length (org-ql-select files
                                           `(and (todo "NEXT") (tags ,tag))
                                           :action 'element))))
                      my/gtd-context-tags))
         (proj-entries (org-ql-select files
                         '(and (todo) (not (done)) (children (todo)))
                         :action (lambda ()
                                   (let* ((htext (org-get-heading t t t t))
                                          (mark (point-marker))
                                          (subtree-end (save-excursion (org-end-of-subtree t) (point)))
                                          (child-next 0) (child-active 0) (child-total 0))
                                      (save-excursion
                                        (while (re-search-forward org-heading-regexp subtree-end t)
                                          (let ((cs (org-get-todo-state)))
                                            (when cs (cl-incf child-total))
                                            (when (my/gtd--active-state-p cs) (cl-incf child-active))
                                            (when (equal cs "NEXT") (cl-incf child-next)))))
                                      (push mark my/gtd--old-markers)
                                      (vector htext mark child-active child-total child-next))))))
    ;; Render dashboard
    (let ((buf (get-buffer-create "*GTD*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (my/gtd-dashboard-mode)
          (define-key my/gtd-dashboard-mode-map (kbd "RET") #'my/gtd-dashboard-activate)
          (define-key my/gtd-dashboard-mode-map (kbd "g") #'my/org-dashboard--open)
          (define-key my/gtd-dashboard-mode-map (kbd "q") #'quit-window)
          (define-key my/gtd-dashboard-mode-map [mouse-1]
            (lambda (event) (interactive "e")
              (mouse-set-point event)
              (my/gtd-dashboard-activate)))

          (insert "\n")
          (my/gtd--dash-row "Inbox"    inbox    (lambda () (my/org-open-inbox)))
          (my/gtd--dash-row "Today"    today    (lambda () (my/org-open-today)))
          (my/gtd--dash-row "Upcoming" upcoming #'my/org-open-upcoming)
          (my/gtd--dash-row "Anytime"  anytime  (lambda () (my/org-open-anytime)))
          (my/gtd--dash-row "Waiting"  waiting  (lambda () (my/org-open-waiting)))
          (my/gtd--dash-row "Someday"  someday  (lambda () (my/org-open-someday)))
          (my/gtd--dash-row "Logbook"  logbook  (lambda () (my/org-open-logbook)))

          ;; Projects section
          (when proj-entries
            (insert "\n")
            (my/gtd--dash-section "Projects")
            (dolist (entry proj-entries)
              (let* ((name (aref entry 0))
                     (mark (aref entry 1))
                     (child-active (aref entry 2))
                     (child-total (aref entry 3))
                     (has-next (aref entry 4))
                     (indicator (cond ((= child-total 0) "?")
                                      ((> has-next 0) " ")
                                      ((> child-active 0) "~")
                                       (t "*")))
                     (max-len (- (min 30 (window-width)) 6))
                     (display (if (> (length name) max-len)
                                  (concat (substring name 0 (1- max-len)) "…")
                                name))
                     (label (if (string= indicator " ")
                                display
                              (concat indicator " " display)))
                     (start (point))
                     (action (let ((m mark))
                                (lambda ()
                                  (if-let ((source-buffer (marker-buffer m)))
                                      (progn
                                        (switch-to-buffer source-buffer)
                                        (widen)
                                        (goto-char m)
                                        (org-narrow-to-subtree)
                                        (goto-char (point-min)))
                                    (message "org-seq GTD: project source moved; refresh dashboard"))))))
                 (insert (format "  %s\n" label))
                 (add-text-properties start (1- (point))
                                      (list 'gtd-action action
                                            'mouse-face 'highlight
                                            'face 'default)))))

          ;; Context section
          (when my/gtd-context-tags
            (insert "\n")
            (my/gtd--dash-section "Contexts")
            (dolist (pair ctx-counts)
              (let ((tag (car pair)) (n (cdr pair)))
                (my/gtd--dash-row tag n
                  (let ((tg tag))
                    (lambda ()
                      (my/org-refresh-agenda-files)
                      (let ((org-agenda-overriding-header tg)
                            (org-agenda-todo-keyword-format ""))
                        (org-tags-view t (format "%s+TODO=\"NEXT\"" tg)))))))))

          (insert "\n")
          (goto-char (point-min))))
      (my/gtd--show-buffer buf)
      (with-current-buffer buf
        (goto-char (point-min))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Auto-refresh
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/gtd--do-refresh ()
  "Actually refresh visible GTD dashboard and agenda views."
  (setq my/gtd--refresh-timer nil)
  (let ((dash-visible (get-buffer-window "*GTD*"))
         (agenda-wins '()))
    (dolist (win (window-list nil 'no-minibuffer))
      (when (window-live-p win)
        (let ((buffer (window-buffer win)))
          (when (and (buffer-live-p buffer)
                     (with-current-buffer buffer
                       (derived-mode-p 'org-agenda-mode)))
            (push win agenda-wins)))))
    (when (or dash-visible agenda-wins)
      (when dash-visible
        (my/org-dashboard--open))
      (dolist (win agenda-wins)
        (when (window-live-p win)
          (with-selected-window win
            (when (derived-mode-p 'org-agenda-mode)
              (org-agenda-redo t))))))))

(defun my/gtd-auto-refresh ()
  "Schedule a debounced refresh (0.3s idle)."
  (when my/gtd--refresh-timer
    (cancel-timer my/gtd--refresh-timer))
  (setq my/gtd--refresh-timer
        (run-with-idle-timer 0.3 nil #'my/gtd--do-refresh)))

(defun my/gtd--refresh-after-schedule (&rest _)
  "Auto-refresh GTD views after scheduling."
  (my/gtd-auto-refresh))

(defun my/gtd--refresh-after-deadline (&rest _)
  "Auto-refresh GTD views after setting a deadline."
  (my/gtd-auto-refresh))

(with-eval-after-load 'org
  (add-hook 'org-capture-after-finalize-hook #'my/gtd-auto-refresh)
  (add-hook 'org-after-todo-state-change-hook #'my/gtd-auto-refresh)
  (advice-add 'org-schedule :after #'my/gtd--refresh-after-schedule)
  (advice-add 'org-deadline :after #'my/gtd--refresh-after-deadline))

(provide 'init-gtd-dashboard)
;;; init-gtd-dashboard.el ends here
