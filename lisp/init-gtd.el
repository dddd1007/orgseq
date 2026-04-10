;;; init-gtd.el --- GTD task management system -*- lexical-binding: t; -*-
;;
;; This is the largest module in the project (~700 lines). It implements a
;; complete GTD workflow on top of org-mode's agenda system, including:
;; a live dashboard with org-ql counts, a state machine, context views,
;; and auto-refresh hooks. Everything happens inside org buffers and uses
;; org-mode's native task state transitions -- this module only adds
;; higher-level ergonomics.
;;
;; ┌─────────────────────────────────────────────────────────────────┐
;; │                       Table of Contents                          │
;; ├─────────────────────────────────────────────────────────────────┤
;; │ Section  1  Agenda file cache                                    │
;; │              `my/agenda-cache', `my/org-roam-agenda-files'       │
;; │                                                                  │
;; │ Section  2  GTD constants and context tags                       │
;; │              `my/gtd-closed-states', `my/gtd-active-states',     │
;; │              `my/gtd-context-tags'                               │
;; │                                                                  │
;; │ Section  3  Project detection helpers                            │
;; │              `my/org-project-p', `my/org-stuck-project-p',       │
;; │              `my/org-skip-non-projects'                          │
;; │                                                                  │
;; │ Section  4  Agenda view openers                                  │
;; │              `my/org-open-task-dashboard',                       │
;; │              `my/org-open-today', `my/org-open-inbox', ...       │
;; │                                                                  │
;; │ Section  5  State picker + complete/cancel with child handling   │
;; │              `my/gtd-set-state', `my/gtd-complete',              │
;; │              `my/gtd-cancel' -- bound to `, q' in org buffers    │
;; │                                                                  │
;; │ Section  6  DONE sink + hide/show toggle                         │
;; │              auto-moves DONE tasks to bottom;                    │
;; │              `my/gtd-toggle-hide-done' bound to `, h'            │
;; │                                                                  │
;; │ Section  7  Context views                                        │
;; │              `my/org-pick-context' prompts for @work/@home/...   │
;; │                                                                  │
;; │ Section  8  Upcoming view (org-ql powered)                       │
;; │              `my/org-open-upcoming' -- scheduled from today on   │
;; │                                                                  │
;; │ Section  9  Agenda visual polish                                 │
;; │              strikethrough CANCELLED, checkmark DONE,            │
;; │              empty-state placeholders                            │
;; │                                                                  │
;; │ Section 10  GTD Dashboard buffer (*GTD*)                         │
;; │              live-count dashboard with projects + contexts;      │
;; │              `my/org-dashboard' is the main entry point          │
;; │                                                                  │
;; │ Section 11  Auto-refresh                                         │
;; │              debounced refresh on state change / schedule /      │
;; │              deadline changes                                    │
;; │                                                                  │
;; │ Section 12  GTD-specific org config (hooks + agenda commands)    │
;; │              `org-agenda-custom-commands' definitions for the    │
;; │              "0 / 1 / 3 / 4 / 5 / 6 / n / p / w" views           │
;; └─────────────────────────────────────────────────────────────────┘

;; Requires: init-org (my/note-home)

(require 'cl-lib)
(require 'subr-x)
(defvar my/note-home)  ; forward-declare from init-org

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Agenda file cache
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/agenda-cache nil
  "Cached list of .org files under `my/note-home'.")

(defvar my/agenda-cache-timestamp 0
  "Time (float seconds) when `my/agenda-cache' was last populated.")

(defcustom my/agenda-cache-ttl 300
  "Seconds before the agenda file cache expires."
  :type 'integer :group 'org-seq)

(defun my/org-roam-agenda-files (&optional force)
  "Return .org files under Roam/ + Outputs/ + Practice/, using org-mem when available.
Library/ and Archives/ are excluded (no actionable tasks).
With non-nil FORCE (or prefix arg interactively), bypass the cache."
  (interactive "P")
  (let ((now (float-time)))
    (when (or force
              (null my/agenda-cache)
              (> (- now my/agenda-cache-timestamp) my/agenda-cache-ttl))
      (setq my/agenda-cache
            (cond
             ;; Fast path: org-mem's async-built file list (Roam/ only)
             ((and (fboundp 'org-mem-all-files)
                   (bound-and-true-p org-node-cache-mode))
              (cl-remove-if-not
               (lambda (f) (string-suffix-p ".org" f))
               (org-mem-all-files)))
             ;; Slow path: scan 00_Roam + 10_Outputs + 20_Practice.
             ;; The numeric prefixes match the NoteHQ layer convention
             ;; defined in init-org.el (`my/roam-dir') and init-supertag.el
             ;; (`my/outputs-dir', `my/practice-dir').  We do not use
             ;; those variables directly here because init-gtd loads
             ;; before init-supertag; when the load order changes this
             ;; can be simplified to reference the defined constants.
             (t (let ((dirs (list (expand-file-name "00_Roam/"     my/note-home)
                                  (expand-file-name "10_Outputs/"  my/note-home)
                                  (expand-file-name "20_Practice/" my/note-home))))
                  (cl-mapcan (lambda (d)
                               (when (file-directory-p d)
                                 (directory-files-recursively d "\\.org\\'")))
                             dirs))))
            my/agenda-cache-timestamp now)
      (message "org-seq: agenda cache refreshed (%d files)" (length my/agenda-cache))))
  my/agenda-cache)

(defun my/org-refresh-agenda-files ()
  "Set `org-agenda-files' from the cached file list."
  (setq org-agenda-files (my/org-roam-agenda-files)))

(defun my/org-invalidate-agenda-cache ()
  "Force the next agenda access to rescan NoteHQ."
  (setq my/agenda-cache nil
        my/agenda-cache-timestamp 0))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: GTD constants and context tags
;; ═══════════════════════════════════════════════════════════════════════════

(defconst my/gtd-closed-states '("DONE" "CANCELLED"))
(defconst my/gtd-active-states '("NEXT" "IN-PROGRESS" "WAITING" "SOMEDAY"))

(defcustom my/gtd-context-tags '("@work" "@home" "@computer" "@errands" "@phone")
  "GTD context tags.  Customize to match your workflow."
  :type '(repeat string) :group 'org-seq)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Project detection helpers
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org--subtree-has-todo-state-p (todo-keyword)
  "Return non-nil when current subtree has TODO-KEYWORD child."
  (save-excursion
    (let ((subtree-end (save-excursion (org-end-of-subtree t)))
          (matched nil))
      (forward-line 1)
      (while (and (not matched)
                  (< (point) subtree-end)
                  (re-search-forward org-heading-regexp subtree-end t))
        (when (string= (org-get-todo-state) todo-keyword)
          (setq matched t)))
      matched)))

(defun my/org-project-p ()
  "Return non-nil when current heading is a project."
  (and (member (org-get-todo-state) org-not-done-keywords)
       (save-excursion
         (let ((subtree-end (save-excursion (org-end-of-subtree t)))
               (has-child-task nil))
           (forward-line 1)
           (while (and (not has-child-task)
                       (< (point) subtree-end)
                       (re-search-forward org-heading-regexp subtree-end t))
             (when (member (org-get-todo-state) org-not-done-keywords)
               (setq has-child-task t)))
           has-child-task))))

(defun my/org-stuck-project-p ()
  "Return non-nil when project has no NEXT child task."
  (and (my/org-project-p)
       (not (my/org--subtree-has-todo-state-p "NEXT"))))

(defun my/org-skip-non-projects ()
  "Skip entries that are not projects."
  (unless (my/org-project-p)
    (or (outline-next-heading) (point-max))))

(defun my/org-skip-non-stuck-projects ()
  "Skip entries that are not stuck projects."
  (unless (my/org-stuck-project-p)
    (or (outline-next-heading) (point-max))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Agenda view openers
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-open-view (key)
  "Open agenda view KEY in current window after refreshing files."
  (my/org-refresh-agenda-files)
  (org-agenda nil key))

(defun my/org-open-task-dashboard ()
  "Open unified GTD dashboard (composite view)."
  (interactive)
  (my/org-open-view "n"))

(defun my/org-open-project-dashboard ()
  "Open GTD project dashboard."
  (interactive)
  (my/org-open-view "p"))

(defun my/org-open-weekly-review ()
  "Open GTD weekly review."
  (interactive)
  (my/org-open-view "w"))

(defun my/org-open-inbox ()
  "Open inbox view."
  (interactive)
  (my/org-open-view "0"))

(defun my/org-open-today ()
  "Open today view."
  (interactive)
  (my/org-open-view "1"))

(defun my/org-open-anytime ()
  "Open anytime (NEXT, unscheduled) view."
  (interactive)
  (my/org-open-view "3"))

(defun my/org-open-waiting ()
  "Open waiting view."
  (interactive)
  (my/org-open-view "4"))

(defun my/org-open-someday ()
  "Open someday view."
  (interactive)
  (my/org-open-view "5"))

(defun my/org-open-logbook ()
  "Open logbook (completed tasks) view."
  (interactive)
  (my/org-open-view "6"))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: State picker, complete/cancel with child handling
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/gtd--collect-active-children ()
  "Collect markers of active child tasks in current subtree.
Excludes the current heading itself."
  (let ((markers '())
        (subtree-end (save-excursion (org-end-of-subtree t) (point))))
    (save-excursion
      (org-back-to-heading t)
      (forward-line 1)
      (while (re-search-forward org-heading-regexp subtree-end t)
        (when (member (org-get-todo-state) my/gtd-active-states)
          (push (point-marker) markers))))
    markers))

(defun my/gtd-complete ()
  "Mark task DONE, handling child tasks with confirmation."
  (interactive)
  (unless (equal (org-get-todo-state) "DONE")
    (let* ((markers (my/gtd--collect-active-children))
           (count (length markers)))
      (if (> count 0)
          (when (y-or-n-p (format "Complete \"%s\" and %d child task%s? "
                                  (org-get-heading t t t t)
                                  count
                                  (if (= count 1) "" "s")))
            (dolist (m markers)
              (goto-char m)
              (org-todo "DONE"))
            (save-excursion
              (org-back-to-heading t)
              (org-todo "DONE")))
        (org-todo "DONE")))))

(defun my/gtd-cancel ()
  "Mark task CANCELLED, handling child tasks with confirmation."
  (interactive)
  (unless (equal (org-get-todo-state) "CANCELLED")
    (let* ((markers (my/gtd--collect-active-children))
           (count (length markers)))
      (if (> count 0)
          (when (y-or-n-p (format "Cancel \"%s\" and %d child task%s? "
                                  (org-get-heading t t t t)
                                  count
                                  (if (= count 1) "" "s")))
            (dolist (m markers)
              (goto-char m)
              (org-todo "CANCELLED"))
            (save-excursion
              (org-back-to-heading t)
              (org-todo "CANCELLED")))
        (org-todo "CANCELLED")))))

(defun my/gtd-set-state ()
  "Single-keypress GTD state picker."
  (interactive)
  (let ((choice (read-char-choice
                 "[n]NEXT [i]IN-PROGRESS [w]WAIT [s]SOMEDAY [k]DONE [x]CANCEL [p]PROJECT [q]uit "
                 '(?n ?i ?w ?s ?k ?x ?p ?q))))
    (message nil)
    (pcase choice
      (?n (org-todo "NEXT"))
      (?i (org-todo "IN-PROGRESS"))
      (?w (org-todo "WAITING"))
      (?s (org-todo "SOMEDAY"))
      (?k (my/gtd-complete))
      (?x (my/gtd-cancel))
      (?p (org-todo "PROJECT"))
      (?q nil))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 6: DONE sink + hide/show toggle
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-move-done-to-bottom ()
  "Move DONE/CANCELLED task to bottom among siblings."
  (when (member org-state my/gtd-closed-states)
    (condition-case nil
        (while (save-excursion
                 (and (org-get-next-sibling)
                      (not (member (org-get-todo-state) my/gtd-closed-states))))
          (org-move-subtree-down))
      (error nil))))

(defvar-local my/gtd--hide-done-active nil
  "Non-nil when the hide-DONE filter is active.")

(defun my/gtd--flag-done-headings (flag)
  "Hide (FLAG=t) or show (FLAG=nil) all DONE/CANCELLED headings."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (when (member (org-get-todo-state) my/gtd-closed-states)
        (let ((start (line-beginning-position))
              (end (save-excursion (org-end-of-subtree t t) (point))))
          (org-fold-region start end flag 'outline))))))

(defun my/gtd-toggle-hide-done ()
  "Toggle visibility of DONE/CANCELLED headings."
  (interactive)
  (if my/gtd--hide-done-active
      (progn
        (setq my/gtd--hide-done-active nil)
        (my/gtd--flag-done-headings nil)
        (message "Showing DONE/CANCELLED tasks"))
    (setq my/gtd--hide-done-active t)
    (my/gtd--flag-done-headings t)
    (message "Hiding DONE/CANCELLED tasks")))

(defun my/gtd--reapply-hide-done (&rest _)
  "Re-hide DONE headings after org-cycle if filter is active."
  (when my/gtd--hide-done-active
    (my/gtd--flag-done-headings t)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 7: Context views
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-pick-context ()
  "Prompt for an @context tag and show NEXT tasks for it."
  (interactive)
  (my/org-refresh-agenda-files)
  (let* ((tag (completing-read "Context: " my/gtd-context-tags nil t))
         (org-agenda-overriding-header tag)
         (org-agenda-todo-keyword-format ""))
    (org-tags-view t (format "%s+TODO=\"NEXT\"" tag))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 8: Upcoming view (org-ql powered)
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-open-upcoming ()
  "Show upcoming scheduled tasks using org-ql."
  (interactive)
  (require 'org-ql)
  (my/org-refresh-agenda-files)
  (org-ql-search (my/org-roam-agenda-files)
    '(and (not (done))
          (not (todo "SOMEDAY"))
          (scheduled :from today))
    :sort '(scheduled)
    :title "GTD Upcoming"
    :super-groups '((:auto-planning))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 9: Agenda visual polish
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-agenda--task-text-bounds ()
  "Return (start . end) of the task text on the current agenda line."
  (save-excursion
    (let* ((bol (line-beginning-position))
           (eol (line-end-position))
           (tag-start (save-excursion
                        (goto-char eol)
                        (if (re-search-backward "[ \t]+:[a-zA-Z0-9_@:]+:[ \t]*$" bol t)
                            (match-beginning 0)
                          eol)))
           (text-start (save-excursion
                         (goto-char bol)
                         (skip-chars-forward " \t")
                         (point))))
      (when (< text-start tag-start)
        (cons text-start tag-start)))))

(defun my/org-agenda-apply-logbook-faces ()
  "Strikethrough CANCELLED and prefix DONE with checkmark in agenda."
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (let ((state (get-text-property (point) 'todo-state)))
        (cond
         ((equal state "CANCELLED")
          (when-let ((bounds (my/org-agenda--task-text-bounds)))
            (add-face-text-property (car bounds) (cdr bounds)
                                    '(:strike-through t))))
         ((equal state "DONE")
          (save-excursion
            (goto-char (line-beginning-position))
            (when (re-search-forward "\\S-" (line-end-position) t)
              (goto-char (match-beginning 0))
              (let ((inhibit-read-only t))
                (insert "✓ ")))))))
      (forward-line 1))))

(defun my/org-agenda-empty-state ()
  "Insert placeholder when agenda buffer has no entries."
  (save-excursion
    (goto-char (point-min))
    (let ((header-end (or (re-search-forward "^-+$" nil t) (point-min))))
      (goto-char header-end)
      (forward-line 1)
      (when (eobp)
        (let ((inhibit-read-only t)
              (header (or org-agenda-overriding-header ""))
              (msg nil))
          (setq msg (cond
                     ((string-match-p "Today\\|agenda" header) "\n  Nothing due today.\n")
                     ((string-match-p "Anytime" header) "\n  No actionable tasks.\n")
                     ((string-match-p "Waiting" header) "\n  Nothing waiting.\n")
                     ((string-match-p "Someday" header) "\n  No someday items.\n")
                     ((string-match-p "Logbook" header) "\n  No completed tasks.\n")
                     ((string-match-p "Inbox" header) "\n  Inbox empty.\n")
                     (t "\n  No tasks.\n")))
          (insert (propertize msg 'face 'shadow)))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 10: GTD Dashboard buffer (*GTD*)
;; ═══════════════════════════════════════════════════════════════════════════

(define-derived-mode my/gtd-dashboard-mode special-mode "GTD"
  "Live-count GTD dashboard. RET or click opens the view at point."
  (setq-local mode-line-format nil)
  (setq-local cursor-type nil))

(defvar my/gtd-dashboard--active-ov nil
  "Overlay marking the active dashboard row.")

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
                                           (when (member cs my/gtd-active-states) (cl-incf child-active))
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
                                      (t "●")))
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
                                 (switch-to-buffer (marker-buffer m))
                                 (widen)
                                 (goto-char m)
                                 (org-narrow-to-subtree)
                                 (goto-char (point-min))))))
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
      ;; Display: reuse window if visible, else split
      (if (get-buffer-window buf)
          (with-current-buffer buf (goto-char (point-min)))
        (delete-other-windows)
        (switch-to-buffer buf)
        (let ((right (split-window-right (floor (* 0.3 (frame-width))))))
          (set-window-buffer right (or (get-buffer "*dashboard*")
                                       (get-buffer "*scratch*")
                                       (get-buffer-create "*scratch*"))))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 11: Auto-refresh
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/gtd--refresh-timer nil
  "Idle timer for debounced dashboard refresh.")

(defun my/gtd--do-refresh ()
  "Actually refresh visible GTD dashboard and agenda views."
  (setq my/gtd--refresh-timer nil)
  (let ((dash-visible (get-buffer-window "*GTD*"))
        (agenda-wins '()))
    (dolist (win (window-list))
      (with-current-buffer (window-buffer win)
        (when (derived-mode-p 'org-agenda-mode)
          (push win agenda-wins))))
    (when (or dash-visible agenda-wins)
      (when dash-visible
        (my/org-dashboard--open))
      (dolist (win agenda-wins)
        (with-selected-window win
          (org-agenda-redo t))))))

(defun my/gtd-auto-refresh ()
  "Schedule a debounced refresh (0.3s idle)."
  (when my/gtd--refresh-timer
    (cancel-timer my/gtd--refresh-timer))
  (setq my/gtd--refresh-timer
        (run-with-idle-timer 0.3 nil #'my/gtd--do-refresh)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 12: GTD-specific org config (hooks, agenda commands, advice)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; These settings configure org-mode's agenda system for GTD.
;; They run after org is loaded (init-org.el loaded before this file).

(with-eval-after-load 'org
  (setq org-agenda-custom-commands
        '(("0" "Inbox" tags "fleeting"
           ((org-agenda-overriding-header "Inbox")
            (org-agenda-skip-function
             '(org-agenda-skip-entry-if 'todo 'done))))

          ("1" "Today" agenda ""
           ((org-agenda-span 1)
            (org-agenda-start-day nil)
            (org-agenda-overriding-header "Today")
            (org-agenda-skip-function
             '(org-agenda-skip-entry-if 'todo '("DONE" "CANCELLED")))))

          ("3" "Anytime" tags-todo "TODO=\"NEXT\""
           ((org-agenda-overriding-header "Anytime")
            (org-agenda-todo-keyword-format "")
            (org-agenda-skip-function
             '(org-agenda-skip-entry-if 'scheduled 'deadline))))

          ("4" "Waiting" todo "WAITING"
           ((org-agenda-overriding-header "Waiting")
            (org-agenda-todo-keyword-format "")))

          ("5" "Someday" todo "SOMEDAY"
           ((org-agenda-overriding-header "Someday")
            (org-agenda-todo-keyword-format "")))

          ("6" "Logbook" todo "DONE|CANCELLED"
           ((org-agenda-overriding-header "Logbook")
            (org-agenda-todo-keyword-format "")
            (org-agenda-sorting-strategy '(timestamp-down))))

          ("n" "GTD Overview"
           ((agenda "" ((org-agenda-span 1)
                        (org-agenda-overriding-header "Today")))
            (todo "IN-PROGRESS"
                  ((org-agenda-overriding-header "In Progress")))
            (todo "NEXT"
                  ((org-agenda-overriding-header "Next Actions")))
            (todo "TODO"
                  ((org-agenda-overriding-header "Inbox (Unscheduled)")
                   (org-agenda-skip-function
                    '(org-agenda-skip-entry-if 'scheduled 'deadline))))
            (todo "WAITING"
                  ((org-agenda-overriding-header "Waiting")))
            (todo "SOMEDAY"
                  ((org-agenda-overriding-header "Someday / Maybe")))))

          ("p" "Projects"
           ((alltodo "" ((org-agenda-overriding-header "Active projects")
                         (org-agenda-skip-function #'my/org-skip-non-projects)))
            (alltodo "" ((org-agenda-overriding-header "Stuck projects (no NEXT)")
                         (org-agenda-skip-function #'my/org-skip-non-stuck-projects)))))

          ("w" "Weekly review"
           ((agenda "" ((org-agenda-span 7)
                        (org-agenda-start-day "-3d")
                        (org-agenda-start-on-weekday nil)
                        (org-agenda-overriding-header "Weekly horizon (-3d to +3d)")))
            (todo "IN-PROGRESS|NEXT|WAITING"
                  ((org-agenda-overriding-header "Committed actions")))
            (alltodo "" ((org-agenda-overriding-header "Stuck projects (needs NEXT)")
                         (org-agenda-skip-function #'my/org-skip-non-stuck-projects)))
            (todo "SOMEDAY"
                  ((org-agenda-overriding-header "Someday / Maybe review")))))))

  (my/org-refresh-agenda-files)
  (add-hook 'org-capture-after-finalize-hook #'my/org-invalidate-agenda-cache)

  ;; Hooks: visual polish + auto-refresh + done-sink
  (add-hook 'org-agenda-finalize-hook #'my/org-agenda-apply-logbook-faces)
  (add-hook 'org-agenda-finalize-hook #'my/org-agenda-empty-state)
  (add-hook 'org-agenda-mode-hook (lambda ()
                                    (setq-local mode-line-format nil)
                                    (setq-local cursor-type nil)))
  (add-hook 'org-after-todo-state-change-hook #'my/org-move-done-to-bottom)
  (add-hook 'org-after-todo-state-change-hook #'my/gtd-auto-refresh)
  (add-hook 'org-cycle-hook #'my/gtd--reapply-hide-done)

  (advice-add 'org-schedule :after (lambda (&rest _) (my/gtd-auto-refresh)))
  (advice-add 'org-deadline :after (lambda (&rest _) (my/gtd-auto-refresh))))

(provide 'init-gtd)
;;; init-gtd.el ends here
