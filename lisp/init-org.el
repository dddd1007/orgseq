;;; init-org.el --- Org-mode base + GTD dashboard -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Core variables and agenda cache
;; ═══════════════════════════════════════════════════════════════════════════

(defvar my/note-home (file-truename "~/NoteHQ/")
  "Root directory for all notes. org-roam lives under Roam/ subdirectory.")

(defvar my/agenda-cache nil
  "Cached list of .org files under `my/note-home'.")

(defvar my/agenda-cache-timestamp 0
  "Time (float seconds) when `my/agenda-cache' was last populated.")

(defvar my/agenda-cache-ttl 300
  "Seconds before the agenda file cache expires.  Default 5 minutes.")

(defun my/org-roam-agenda-files (&optional force)
  "Return .org files under NoteHQ, using a TTL cache.
With non-nil FORCE (or prefix arg interactively), bypass the cache."
  (interactive "P")
  (let ((now (float-time)))
    (when (or force
              (null my/agenda-cache)
              (> (- now my/agenda-cache-timestamp) my/agenda-cache-ttl))
      (let ((root my/note-home))
        (setq my/agenda-cache
              (if (file-directory-p root)
                  (directory-files-recursively root "\\.org\\'")
                nil)
              my/agenda-cache-timestamp now))
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

(defvar my/gtd-context-tags '("@work" "@home" "@computer" "@errands" "@phone")
  "GTD context tags. Customize to match your workflow.")

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
      (if (> count 1)
          (when (y-or-n-p (format "Complete \"%s\" and %d child task%s? "
                                  (org-get-heading t t t t)
                                  (1- count)
                                  (if (= count 2) "" "s")))
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
      (if (> count 1)
          (when (y-or-n-p (format "Cancel \"%s\" and %d child task%s? "
                                  (org-get-heading t t t t)
                                  (1- count)
                                  (if (= count 2) "" "s")))
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
          (if (fboundp 'org-fold-region)
              (org-fold-region start end flag 'outline)
            (org-flag-region start end flag 'outline)))))))

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
;; Section 8: Upcoming view
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-open-upcoming ()
  "Show upcoming scheduled tasks grouped by day then month."
  (interactive)
  (my/org-refresh-agenda-files)
  (let* ((entries '())
         (today-d (decode-time))
         (today-start (float-time
                       (encode-time 0 0 0
                                    (nth 3 today-d) (nth 4 today-d) (nth 5 today-d)))))
    (dolist (file (my/org-roam-agenda-files))
      (when (file-exists-p file)
        (with-current-buffer (find-file-noselect file)
          (save-restriction
            (widen)
            (org-map-entries
             (lambda ()
               (let* ((state (org-get-todo-state))
                      (sched (org-get-scheduled-time (point))))
                 (when (and state
                            (not (member state my/gtd-closed-states))
                            (not (equal state "SOMEDAY"))
                            sched
                            (>= (float-time sched) today-start))
                   (push (list (float-time sched)
                               (org-get-heading t t t t)
                               state
                               (point-marker))
                         entries))))
             nil 'file)))))
    (setq entries (sort entries (lambda (a b) (< (car a) (car b)))))
    (let ((buf (get-buffer-create "*GTD Upcoming*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (special-mode)
          (setq-local mode-line-format nil)
          (use-local-map (copy-keymap special-mode-map))
          (local-set-key (kbd "q") #'quit-window)
          (local-set-key (kbd "RET") #'my/org-upcoming-goto)
          (local-set-key [mouse-1]
                         (lambda (event) (interactive "e")
                           (mouse-set-point event)
                           (my/org-upcoming-goto)))
          (insert "\n")
          (if (null entries)
              (insert (propertize "\n  No upcoming tasks.\n" 'face 'shadow))
            (let ((current-section nil))
              (dolist (entry entries)
                (pcase-let* ((`(,sched-f ,htext ,_state ,mark) entry)
                             (days (/ (- sched-f today-start) 86400))
                             (section (cond
                                       ((< days 1) "Today")
                                       ((< days 2) "Tomorrow")
                                       ((< days 7)
                                        (nth (nth 6 (decode-time (seconds-to-time sched-f)))
                                             '("Sunday" "Monday" "Tuesday" "Wednesday"
                                               "Thursday" "Friday" "Saturday")))
                                       (t (format-time-string "%B" (seconds-to-time sched-f))))))
                  (unless (equal section current-section)
                    (setq current-section section)
                    (insert (propertize (format "\n  %s\n" section) 'face '(:inherit shadow :weight bold))))
                  (let ((start (point)))
                    (insert (format "    %s\n" htext))
                    (add-text-properties start (1- (point))
                                         (list 'gtd-marker mark 'mouse-face 'highlight)))))))
          (goto-char (point-min))))
      (display-buffer buf '((display-buffer-reuse-window display-buffer-same-window))))))

(defun my/org-upcoming-goto ()
  "Open the task at point in the upcoming view, narrowed to subtree."
  (interactive)
  (when-let ((mark (get-text-property (point) 'gtd-marker)))
    (switch-to-buffer (marker-buffer mark))
    (widen)
    (goto-char mark)
    (org-narrow-to-subtree)
    (goto-char (point-min))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 9: Agenda visual polish
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/org-agenda-state-prefix ()
  "Return the TODO state of the current agenda entry, for prefix-format."
  (or (org-get-at-bol 'todo-state) ""))

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
    ;; Highlight active row
    (when (overlayp my/gtd-dashboard--active-ov)
      (delete-overlay my/gtd-dashboard--active-ov))
    (setq my/gtd-dashboard--active-ov
          (make-overlay (line-beginning-position) (line-end-position)))
    (overlay-put my/gtd-dashboard--active-ov 'face 'secondary-selection)
    ;; Open view in right pane if available
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
  "Build and display the GTD dashboard with live counts."
  (my/org-refresh-agenda-files)
  (let ((inbox 0) (today 0) (upcoming 0) (anytime 0) (waiting 0) (someday 0)
        (logbook 0)
        (ctx-counts (mapcar (lambda (tag) (cons tag 0)) my/gtd-context-tags))
        (proj-names '())
        (proj-data (make-hash-table :test 'equal))
        (now-f (float-time))
        (today-d (let ((d (decode-time))) (list (nth 4 d) (nth 3 d) (nth 5 d)))))
    ;; Scan all agenda files
    (dolist (file (my/org-roam-agenda-files))
      (when (file-exists-p file)
        (with-current-buffer (find-file-noselect file)
          (save-restriction
            (widen)
            (org-map-entries
             (lambda ()
               (let* ((state (org-get-todo-state))
                      (tags (org-get-tags))
                      (sched (org-get-scheduled-time (point)))
                      (dead (org-get-deadline-time (point)))
                      (active (and state (not (member state my/gtd-closed-states))
                                   (not (equal state "SOMEDAY"))))
                      (ctx (seq-find (lambda (tg) (string-prefix-p "@" tg)) tags)))
                 ;; Inbox: fleeting tagged entries with no TODO state
                 (when (and (not state) (member "fleeting" tags))
                   (cl-incf inbox))
                 ;; Today: scheduled/deadline today or overdue
                 (when (and active
                            (or (and sched
                                     (equal (let ((s (decode-time sched)))
                                              (list (nth 4 s) (nth 3 s) (nth 5 s)))
                                            today-d))
                                (and dead (<= (float-time dead) now-f))))
                   (cl-incf today))
                 ;; Upcoming: future scheduled
                 (when (and active sched (> (float-time sched) now-f))
                   (cl-incf upcoming))
                 ;; Anytime: NEXT with no schedule and no deadline
                 (when (and (equal state "NEXT") (not sched) (not dead))
                   (cl-incf anytime))
                 ;; Waiting / Someday / Logbook
                 (when (equal state "WAITING") (cl-incf waiting))
                 (when (equal state "SOMEDAY") (cl-incf someday))
                 (when (member state my/gtd-closed-states) (cl-incf logbook))
                 ;; Context counts (NEXT tasks only)
                 (when (equal state "NEXT")
                   (when ctx
                     (when-let ((cell (assoc ctx ctx-counts)))
                       (cl-incf (cdr cell)))))
                 ;; Project detection
                 (when (and (my/org-project-p)
                            (not (member state my/gtd-closed-states)))
                   (let* ((htext (org-get-heading t t t t))
                          (subtree-end (save-excursion (org-end-of-subtree t) (point)))
                          (child-active 0) (child-next 0) (child-total 0))
                     (save-excursion
                       (while (re-search-forward org-heading-regexp subtree-end t)
                         (let ((cs (org-get-todo-state)))
                           (when cs (cl-incf child-total))
                           (when (member cs my/gtd-active-states) (cl-incf child-active))
                           (when (equal cs "NEXT") (cl-incf child-next)))))
                     (let ((proj-key (concat (or buffer-file-name "") "\0" htext)))
                       (unless (gethash proj-key proj-data)
                         (push (cons proj-key htext) proj-names)
                         (puthash proj-key (vector child-active child-total (point-marker) child-next)
                                  proj-data)))))))
             nil 'file)))))
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
          (when proj-names
            (insert "\n")
            (my/gtd--dash-section "Projects")
            (dolist (entry (nreverse proj-names))
              (let* ((proj-key (car entry))
                     (name (cdr entry))
                     (v (gethash proj-key proj-data))
                     (child-active (aref v 0))
                     (child-total (aref v 1))
                     (mark (aref v 2))
                     (has-next (aref v 3))
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
;; Section 12: use-package org — base configuration
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org
  :demand t
  :config
  (setq org-startup-indented t
        org-indent-indentation-per-level 2)

  (setq org-startup-folded 'content)
  (setq org-hide-leading-stars t)
  (setq org-ellipsis " ⤵")

  (setq org-return-follows-link t
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-catch-invisible-edits 'show-and-error
        org-pretty-entities t)

  (setq org-log-done 'time
        org-log-into-drawer t)

  ;; TODO keywords (PROJECT added for org-gtd compatibility)
  (setq org-todo-keywords
        '((sequence "PROJECT(P)" "TODO(t)" "NEXT(n)" "IN-PROGRESS(i)"
                    "WAITING(w@/!)" "SOMEDAY(s)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))

  (setq org-enforce-todo-dependencies t)

  ;; Agenda prefix: clean format, hide file names
  (setq org-agenda-prefix-format
        '((agenda . " %i %?-12t% s")
          (todo   . " ")
          (tags   . " ")
          (search . " %i %-12:c")))
  (setq org-agenda-window-setup 'current-window)

  ;; Agenda views
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

  ;; Refile
  (setq org-refile-targets '((nil :maxlevel . 3)
                              (org-agenda-files :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

  ;; Tags
  (setq org-auto-align-tags nil
        org-tags-column 0)

  ;; Hooks: visual polish + auto-refresh + done-sink
  (add-hook 'org-agenda-finalize-hook #'my/org-agenda-apply-logbook-faces)
  (add-hook 'org-agenda-finalize-hook #'my/org-agenda-empty-state)
  (add-hook 'org-agenda-mode-hook (lambda ()
                                    (setq-local mode-line-format nil)
                                    (setq-local cursor-type nil)))
  (add-hook 'org-after-todo-state-change-hook #'my/org-move-done-to-bottom)
  (add-hook 'org-after-todo-state-change-hook #'my/gtd-auto-refresh)
  (add-hook 'org-cycle-hook #'my/gtd--reapply-hide-done)

  ;; Auto-refresh on schedule/deadline
  (advice-add 'org-schedule :after (lambda (&rest _) (my/gtd-auto-refresh)))
  (advice-add 'org-deadline :after (lambda (&rest _) (my/gtd-auto-refresh))))

;; ---- org-modern: visual enhancement ----
(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq org-modern-star '("◉" "○" "◈" "◇" "⁕")
        org-modern-table nil))

;; ---- evil-org: Evil keybindings for org-mode ----
(use-package evil-org
  :after (org evil)
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar))
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;; ---- Local leader keys for Org buffers ----
(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'org-mode-map
   :prefix ","
   :global-prefix "M-,"

   ""   '(nil :wk "org")

   "r"  '(org-refile :wk "Refile")
   "a"  '(org-archive-subtree :wk "Archive")
   "t"  '(org-set-tags-command :wk "Set tags")
   "p"  '(org-set-property :wk "Set property")
   "e"  '(org-set-effort :wk "Set effort")
   "x"  '(org-export-dispatch :wk "Export")
   "l"  '(org-insert-link :wk "Insert link")
   "L"  '(org-store-link :wk "Store link")
   "s"  '(org-schedule :wk "Schedule")
   "d"  '(org-deadline :wk "Deadline")
   "i"  '(org-time-stamp :wk "Timestamp")
   "I"  '(org-time-stamp-inactive :wk "Timestamp (inactive)")
   "n"  '(org-narrow-to-subtree :wk "Narrow to subtree")
   "w"  '(widen :wk "Widen")
   "c"  '(org-toggle-checkbox :wk "Toggle checkbox")
   "q"  '(my/gtd-set-state :wk "State picker")
   "h"  '(my/gtd-toggle-hide-done :wk "Hide/show done")

   ;; , k — Clock
   "k"  '(:ignore t :wk "clock")
   "ki" '(org-clock-in :wk "Clock in")
   "ko" '(org-clock-out :wk "Clock out")
   "kg" '(org-clock-goto :wk "Goto clock")
   "kr" '(org-clock-report :wk "Report")
   "kc" '(org-clock-cancel :wk "Cancel")

   ;; , b — Babel
   "b"  '(:ignore t :wk "babel")
   "be" '(org-babel-execute-src-block :wk "Execute block")
   "bb" '(org-babel-execute-buffer :wk "Execute buffer")
   "bt" '(org-babel-tangle :wk "Tangle")))

(provide 'init-org)
;;; init-org.el ends here
