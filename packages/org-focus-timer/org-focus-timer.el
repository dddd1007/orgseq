;;; org-focus-timer.el --- Vitamin-R-style focus timer for org-mode -*- lexical-binding: t; -*-

;; Author: Xia Xiaokai
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: outlines productivity tools
;; URL: https://github.com/exrld/org-focus-timer

;;; Commentary:
;;
;; A focus timer for org-mode inspired by Vitamin-R (macOS).  Unlike a
;; fixed pomodoro, each slice snaps its end time to the nearest round
;; clock boundary within a configurable window (default 10-30 minutes,
;; snapped to 15-minute marks), so your work naturally aligns with
;; wall-clock moments like :00, :15, :30, :45.
;;
;; Core flow:
;;
;;   1. Call `org-focus-start' in any buffer.  An inline marker is
;;      inserted at point, the countdown begins, and the remaining time
;;      appears in the modeline.
;;   2. When the slice ends, Emacs beeps and prompts you to record how
;;      it felt: unfocused, normal, or flow.
;;   3. The outcome is appended both to the inline marker in the source
;;      buffer and to a persistent log file at `org-focus-log-file'.
;;   4. `org-focus-dashboard' shows recent slices as a text timeline
;;      with aggregate stats.
;;
;; Entry points:
;;
;;   `org-focus-start'     -- insert a new slice at point and start it
;;   `org-focus-abort'     -- cancel the running slice without recording
;;   `org-focus-dashboard' -- open the visualization buffer
;;
;; The package has zero external dependencies beyond Emacs 29+ itself.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'subr-x)

;; ═══════════════════════════════════════════════════════════════════════════
;; Customization
;; ═══════════════════════════════════════════════════════════════════════════

(defgroup org-focus-timer nil
  "Vitamin-R-style focus timer for org-mode."
  :group 'org
  :prefix "org-focus-")

(defcustom org-focus-log-file
  (expand-file-name "focus-log.org" user-emacs-directory)
  "Org file where completed focus slice entries are appended.
The directory is created on first write if it does not exist."
  :type 'file
  :group 'org-focus-timer)

(defcustom org-focus-min-duration 10
  "Minimum slice duration in minutes.
The snapped end time will never be closer than this many minutes from now."
  :type 'integer
  :group 'org-focus-timer)

(defcustom org-focus-max-duration 30
  "Maximum slice duration in minutes.
The snapped end time will never be further than this many minutes from now."
  :type 'integer
  :group 'org-focus-timer)

(defcustom org-focus-round-to 15
  "Round the slice end time to this many minutes.
With the default of 15, slices end at :00/:15/:30/:45 on the clock."
  :type 'integer
  :group 'org-focus-timer)

(defcustom org-focus-insert-marker-format
  "[%s] focus started -- %dm planned (ends %s)"
  "Format string for the inline marker inserted at slice start.
Arguments passed to `format': START-TIMESTAMP, PLANNED-MINUTES, END-HH:MM."
  :type 'string
  :group 'org-focus-timer)

(defcustom org-focus-complete-marker-format
  " -> ended %s (%s)"
  "Format appended to the inline marker when the slice completes.
Arguments: END-HH:MM, OUTCOME-DISPLAY-NAME."
  :type 'string
  :group 'org-focus-timer)

(defcustom org-focus-outcomes
  '((?u "unfocused" "unfocused")
    (?n "normal"    "normal focus")
    (?f "flow"      "flow state"))
  "Self-assessment choices presented when a slice ends.
Each entry is (CHAR INTERNAL-NAME DISPLAY-NAME).
CHAR is the single key to press at the prompt.
INTERNAL-NAME is stored in the log file OUTCOME property.
DISPLAY-NAME is shown to the user in messages and dashboards."
  :type '(repeat (list character string string))
  :group 'org-focus-timer)

(defcustom org-focus-ring-bell-on-end t
  "When non-nil, ring the bell when a slice ends."
  :type 'boolean
  :group 'org-focus-timer)

(defcustom org-focus-dashboard-days 14
  "Number of days of history shown in `org-focus-dashboard'."
  :type 'integer
  :group 'org-focus-timer)

;; ═══════════════════════════════════════════════════════════════════════════
;; State
;; ═══════════════════════════════════════════════════════════════════════════

(defvar org-focus--current nil
  "Plist describing the active slice, or nil when idle.
Keys:
  :start        the time the slice began (Lisp time value)
  :end          the planned end time (Lisp time value)
  :planned-min  integer, minutes originally planned
  :timer        the `run-at-time' timer that fires at :end
  :tick-timer   the modeline update timer (ticks every second)
  :buffer       the source buffer where the marker was inserted
  :marker       the point-marker at the end of the inline marker")

(defvar org-focus--modeline-string ""
  "String shown in `global-mode-string' while a slice is active.")
(put 'org-focus--modeline-string 'risky-local-variable t)

(unless (member 'org-focus--modeline-string global-mode-string)
  (setq global-mode-string
        (append (or global-mode-string '("")) '(" " org-focus--modeline-string))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Time snapping
;; ═══════════════════════════════════════════════════════════════════════════

(defun org-focus--snap-end-time (now)
  "Return the snapped end time for a slice starting at NOW.
The result is a Lisp time value inside
\[NOW + `org-focus-min-duration', NOW + `org-focus-max-duration'],
aligned to `org-focus-round-to'-minute clock boundaries when possible.
Falls back to 5-minute alignment, then to an unaligned max-end."
  (let* ((min-end (time-add now (seconds-to-time (* 60 org-focus-min-duration))))
         (max-end (time-add now (seconds-to-time (* 60 org-focus-max-duration)))))
    (or (org-focus--first-aligned min-end max-end org-focus-round-to)
        (org-focus--first-aligned min-end max-end 5)
        max-end)))

(defun org-focus--first-aligned (min-end max-end step)
  "Return the earliest STEP-minute-aligned time in [MIN-END, MAX-END], or nil.
\"Aligned\" means the minute component is divisible by STEP and seconds are 0."
  (let* ((decoded (decode-time min-end))
         (sec (nth 0 decoded))
         (minute (nth 1 decoded))
         (aligned-min-end (time-subtract min-end (seconds-to-time sec)))
         (past-boundary (mod minute step))
         (to-add (cond
                  ((and (zerop past-boundary) (zerop sec)) 0)
                  (t (- step past-boundary))))
         (candidate (time-add aligned-min-end (seconds-to-time (* 60 to-add)))))
    (unless (time-less-p max-end candidate)
      candidate)))

(defun org-focus--minutes-between (start end)
  "Return the integer minutes between START and END (rounded)."
  (round (/ (float-time (time-subtract end start)) 60.0)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Interactive commands
;; ═══════════════════════════════════════════════════════════════════════════

;;;###autoload
(defun org-focus-start (&optional prompt-duration)
  "Start a focus slice and insert a marker at point.
The slice end time is snapped to the nearest clock boundary inside
\[`org-focus-min-duration', `org-focus-max-duration'] minutes from now.

With prefix argument PROMPT-DURATION, prompt for a custom duration
in minutes (with the snapped default pre-filled).

While the slice is running, the modeline shows remaining time.
When the slice ends the user is prompted for a self-assessment."
  (interactive "P")
  (when org-focus--current
    (user-error "A focus slice is already running (ends at %s).  \
Use `org-focus-abort' to cancel first"
                (format-time-string "%H:%M"
                                    (plist-get org-focus--current :end))))
  (let* ((now (current-time))
         (snapped-end (org-focus--snap-end-time now))
         (end (if prompt-duration
                  (let ((mins (read-number
                               "Duration (minutes): "
                               (org-focus--minutes-between now snapped-end))))
                    (time-add now (seconds-to-time (* 60 mins))))
                snapped-end))
         (planned (org-focus--minutes-between now end))
         (start-ts (format-time-string "%Y-%m-%d %a %H:%M" now))
         (end-hm (format-time-string "%H:%M" end))
         (marker-text (format org-focus-insert-marker-format
                              start-ts planned end-hm)))
    (org-focus--insert-marker marker-text)
    (let ((mark (point-marker)))
      (set-marker-insertion-type mark t)
      (setq org-focus--current
            (list :start now
                  :end end
                  :planned-min planned
                  :buffer (current-buffer)
                  :marker mark
                  :timer (run-at-time end nil #'org-focus--fire)
                  :tick-timer (run-with-timer 0 1 #'org-focus--tick)))
      (org-focus--update-modeline)
      (message "Focus slice started: %d min, ends at %s.  \
M-x org-focus-abort to cancel."
               planned end-hm))))

(defun org-focus--insert-marker (text)
  "Insert marker TEXT at point, on its own line.
If the current line already contains text, inserts a newline first."
  (save-excursion
    (beginning-of-line)
    (let ((line-is-empty (looking-at-p "[ \t]*$")))
      (unless line-is-empty
        (end-of-line)
        (newline))
      (insert text)))
  (beginning-of-line)
  (unless (looking-at-p "\\[")
    (forward-line 1))
  (end-of-line))

;;;###autoload
(defun org-focus-abort ()
  "Cancel the currently running focus slice without recording an outcome.
The inline marker in the source buffer is left in place but not completed."
  (interactive)
  (unless org-focus--current
    (user-error "No focus slice is currently running"))
  (org-focus--cancel-timers)
  (let ((marker (plist-get org-focus--current :marker)))
    (when (markerp marker) (set-marker marker nil)))
  (setq org-focus--current nil
        org-focus--modeline-string "")
  (force-mode-line-update t)
  (message "Focus slice aborted"))

(defun org-focus--cancel-timers ()
  "Cancel both the end timer and the modeline tick timer."
  (when org-focus--current
    (let ((t1 (plist-get org-focus--current :timer))
          (t2 (plist-get org-focus--current :tick-timer)))
      (when (timerp t1) (cancel-timer t1))
      (when (timerp t2) (cancel-timer t2)))))

(defun org-focus--tick ()
  "Refresh the modeline remaining-time indicator."
  (when org-focus--current
    (org-focus--update-modeline)
    (force-mode-line-update t)))

(defun org-focus--update-modeline ()
  "Recompute `org-focus--modeline-string' from the active slice."
  (when org-focus--current
    (let* ((end (plist-get org-focus--current :end))
           (remaining (max 0 (round (float-time
                                     (time-subtract end (current-time))))))
           (mins (/ remaining 60))
           (secs (mod remaining 60)))
      (setq org-focus--modeline-string
            (propertize (format "[FOCUS %d:%02d]" mins secs)
                        'face 'mode-line-emphasis
                        'help-echo "Active focus slice")))))

(defun org-focus--fire ()
  "Run when the slice end time arrives."
  (when org-focus--current
    (let ((tick (plist-get org-focus--current :tick-timer)))
      (when (timerp tick) (cancel-timer tick)))
    (when org-focus-ring-bell-on-end (ding))
    (message "Focus slice ended.  Checking in...")
    (run-with-timer 0.3 nil #'org-focus--prompt-outcome)))

(defun org-focus--prompt-outcome ()
  "Prompt for the self-assessment outcome and finalize the slice."
  (unless org-focus--current
    (user-error "No active slice to finalize"))
  (let* ((choices-text (mapconcat
                        (lambda (o) (format "(%c) %s" (nth 0 o) (nth 2 o)))
                        org-focus-outcomes
                        "   "))
         (prompt (format "How did that feel?  %s : " choices-text))
         (valid-chars (mapcar #'car org-focus-outcomes))
         (char (read-char-choice prompt valid-chars))
         (outcome (cl-find char org-focus-outcomes :key #'car)))
    (org-focus--complete (nth 1 outcome) (nth 2 outcome))))

(defun org-focus--complete (outcome-internal outcome-display)
  "Finalize the active slice with OUTCOME-INTERNAL (display OUTCOME-DISPLAY)."
  (let* ((state org-focus--current)
         (start (plist-get state :start))
         (end (plist-get state :end))
         (planned (plist-get state :planned-min))
         (buffer (plist-get state :buffer))
         (marker (plist-get state :marker))
         (actual-end (current-time))
         (actual-min (org-focus--minutes-between start actual-end)))
    (when (and (buffer-live-p buffer)
               (markerp marker)
               (marker-buffer marker))
      (with-current-buffer buffer
        (save-excursion
          (goto-char marker)
          (insert (format org-focus-complete-marker-format
                          (format-time-string "%H:%M" actual-end)
                          outcome-display)))))
    (org-focus--log-entry start actual-end planned actual-min
                          outcome-internal buffer)
    (when (markerp marker) (set-marker marker nil))
    (setq org-focus--current nil
          org-focus--modeline-string "")
    (force-mode-line-update t)
    (message "Focus logged: %s (%d min actual, %d min planned)"
             outcome-display actual-min planned)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Log persistence
;; ═══════════════════════════════════════════════════════════════════════════

(defun org-focus--log-entry (start actual-end planned actual outcome source-buffer)
  "Append a completed slice entry to `org-focus-log-file'."
  (let ((log-file org-focus-log-file))
    (make-directory (file-name-directory log-file) t)
    (with-current-buffer (find-file-noselect log-file)
      (save-excursion
        (goto-char (point-min))
        (when (= (buffer-size) 0)
          (insert "#+title: Focus Timer Log\n")
          (insert "#+filetags: :focus:\n")
          (insert "#+startup: overview\n\n")
          (insert "Each level-1 heading is a day.  Each level-2 heading is a\n")
          (insert "completed focus slice.  Safe to edit by hand, but prefer\n")
          (insert "M-x org-focus-start to append new entries.\n\n"))
        (let* ((day-heading (format-time-string "* %Y-%m-%d %a" start))
               (day-pos (save-excursion
                          (goto-char (point-min))
                          (when (re-search-forward
                                 (concat "^"
                                         (regexp-quote day-heading)
                                         "\\s-*$")
                                 nil t)
                            (match-beginning 0)))))
          (if day-pos
              (progn (goto-char day-pos)
                     (forward-line 1)
                     (let ((next (save-excursion
                                   (if (re-search-forward "^\\* " nil t)
                                       (match-beginning 0)
                                     (point-max)))))
                       (goto-char next)))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert day-heading "\n\n")))
        (insert (format "** %s %s (%dm)\n"
                        (format-time-string "%H:%M" start)
                        outcome
                        actual))
        (insert ":PROPERTIES:\n")
        (insert (format ":STARTED:  %s\n"
                        (format-time-string "[%Y-%m-%d %a %H:%M]" start)))
        (insert (format ":ENDED:    %s\n"
                        (format-time-string "[%Y-%m-%d %a %H:%M]" actual-end)))
        (insert (format ":PLANNED:  %d\n" planned))
        (insert (format ":ACTUAL:   %d\n" actual))
        (insert (format ":OUTCOME:  %s\n" outcome))
        (when (and (buffer-live-p source-buffer)
                   (buffer-file-name source-buffer))
          (insert (format ":CONTEXT:  %s\n"
                          (buffer-file-name source-buffer))))
        (insert ":END:\n")
        (save-buffer)))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Dashboard
;; ═══════════════════════════════════════════════════════════════════════════

(defvar org-focus-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'org-focus-dashboard)
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "RET") #'org-focus--dashboard-open-log)
    (define-key map (kbd "s") #'org-focus-start)
    map)
  "Keymap for `org-focus-dashboard-mode'.")

(define-derived-mode org-focus-dashboard-mode special-mode "Focus"
  "Major mode for the focus dashboard buffer.
\\<org-focus-dashboard-mode-map>
\\[org-focus-dashboard] refresh
\\[org-focus--dashboard-open-log] open the raw log file
\\[org-focus-start] start a new slice (in the current buffer)
\\[quit-window] quit"
  (setq truncate-lines t
        buffer-read-only t))

(defun org-focus--dashboard-open-log ()
  "Open `org-focus-log-file' in another window."
  (interactive)
  (if (file-exists-p org-focus-log-file)
      (find-file-other-window org-focus-log-file)
    (user-error "Log file does not exist yet: %s" org-focus-log-file)))

;;;###autoload
(defun org-focus-dashboard ()
  "Open the focus dashboard buffer with recent slice history and stats."
  (interactive)
  (let ((buf (get-buffer-create "*Focus Dashboard*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-focus--render-dashboard)
        (goto-char (point-min)))
      (org-focus-dashboard-mode))
    (pop-to-buffer buf)))

(defun org-focus--render-dashboard ()
  "Render the dashboard content at point."
  (let* ((entries (org-focus--read-entries org-focus-dashboard-days))
         (by-day (org-focus--group-by-day entries)))
    (insert (propertize "FOCUS DASHBOARD\n"
                        'face '(:height 1.4 :weight bold)))
    (insert (format "  log: %s\n" org-focus-log-file))
    (insert (format "  range: last %d days\n\n" org-focus-dashboard-days))
    (if (null entries)
        (progn
          (insert "  No focus slices recorded yet.\n\n")
          (insert "  Put the cursor anywhere in an org buffer and run\n")
          (insert "  M-x org-focus-start (or SPC a f in org-seq) to begin.\n"))
      (insert (propertize "Daily timeline\n" 'face 'bold))
      (insert "   legend: ")
      (insert (propertize "flow" 'face '(:foreground "#2ca02c" :weight bold)))
      (insert " = "
              (propertize "█" 'face '(:foreground "#2ca02c"))
              "   ")
      (insert (propertize "normal" 'face '(:foreground "#1f77b4" :weight bold)))
      (insert " = "
              (propertize "▓" 'face '(:foreground "#1f77b4"))
              "   ")
      (insert (propertize "unfocused" 'face '(:foreground "#888888" :weight bold)))
      (insert " = "
              (propertize "░" 'face '(:foreground "#888888"))
              "\n\n")
      (dolist (day by-day)
        (org-focus--render-day-row (car day) (cdr day)))
      (insert "\n")
      (org-focus--render-summary entries)
      (insert "\n")
      (insert (propertize "Keys\n" 'face 'bold))
      (insert "  g         refresh\n")
      (insert "  RET       open raw log file\n")
      (insert "  s         start a new focus slice\n")
      (insert "  q         quit\n"))))

(defun org-focus--read-entries (n-days)
  "Read focus entries from the log, filtered to the last N-DAYS.
Returns nil if the log file does not exist."
  (when (file-exists-p org-focus-log-file)
    (let ((cutoff (time-subtract (current-time)
                                  (seconds-to-time (* n-days 86400))))
          entries)
      (with-temp-buffer
        (insert-file-contents org-focus-log-file)
        (org-mode)
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\* " nil t)
          (let* ((props (org-entry-properties))
                 (started-str (cdr (assoc "STARTED" props)))
                 (started-time (when started-str
                                 (org-focus--parse-org-time started-str)))
                 (ended-str (cdr (assoc "ENDED" props)))
                 (planned (cdr (assoc "PLANNED" props)))
                 (actual (cdr (assoc "ACTUAL" props)))
                 (outcome (cdr (assoc "OUTCOME" props))))
            (when (and started-time outcome
                       (not (time-less-p started-time cutoff)))
              (push (list :started-str started-str
                          :started-time started-time
                          :ended-str ended-str
                          :planned (and planned (string-to-number planned))
                          :actual (and actual (string-to-number actual))
                          :outcome outcome)
                    entries)))))
      (sort entries
            (lambda (a b) (time-less-p (plist-get a :started-time)
                                       (plist-get b :started-time)))))))

(defun org-focus--parse-org-time (ts)
  "Parse an org timestamp string TS like \"[2026-04-10 Fri 14:17]\" to a Lisp time."
  (when (string-match
         "\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)[^0-9]+\\([0-9]+\\):\\([0-9]+\\)"
         ts)
    (encode-time 0
                 (string-to-number (match-string 5 ts))
                 (string-to-number (match-string 4 ts))
                 (string-to-number (match-string 3 ts))
                 (string-to-number (match-string 2 ts))
                 (string-to-number (match-string 1 ts)))))

(defun org-focus--group-by-day (entries)
  "Group ENTRIES by date string, return alist ((DATE . ENTRIES) ...) newest first."
  (let ((groups nil))
    (dolist (e entries)
      (let* ((date (format-time-string "%Y-%m-%d %a"
                                       (plist-get e :started-time)))
             (existing (assoc date groups)))
        (if existing
            (setcdr existing (append (cdr existing) (list e)))
          (push (cons date (list e)) groups))))
    (sort groups (lambda (a b) (string> (car a) (car b))))))

(defun org-focus--render-day-row (date entries)
  "Render one day row: DATE header + timeline bar + stats."
  (let* ((n (length entries))
         (total-actual (apply #'+ (mapcar (lambda (e) (or (plist-get e :actual) 0))
                                           entries)))
         (focus-mins (apply #'+
                            (mapcar
                             (lambda (e)
                               (if (member (plist-get e :outcome)
                                           '("normal" "flow"))
                                   (or (plist-get e :actual) 0)
                                 0))
                             entries)))
         (flow-mins (apply #'+
                           (mapcar
                            (lambda (e)
                              (if (equal (plist-get e :outcome) "flow")
                                  (or (plist-get e :actual) 0)
                                0))
                            entries)))
         (ratio (if (> total-actual 0)
                    (/ (* 100.0 focus-mins) total-actual)
                  0.0)))
    (insert (format "  %s  " date))
    (insert (propertize (format "%d slice%s  %dm total  %.0f%% focused"
                                n (if (= n 1) "" "s") total-actual ratio)
                        'face 'shadow))
    (when (> flow-mins 0)
      (insert (propertize (format "  %dm flow" flow-mins)
                          'face '(:foreground "#2ca02c"))))
    (insert "\n    ")
    (dolist (e entries)
      (let* ((outcome (plist-get e :outcome))
             (glyph (pcase outcome
                      ("flow"      "█")
                      ("normal"    "▓")
                      ("unfocused" "░")
                      (_           "?")))
             (face (pcase outcome
                     ("flow"      '(:foreground "#2ca02c"))
                     ("normal"    '(:foreground "#1f77b4"))
                     ("unfocused" '(:foreground "#888888"))
                     (_           'shadow)))
             (actual (or (plist-get e :actual) 0))
             (width (max 1 (/ actual 5))))
        (insert (propertize (make-string width (string-to-char glyph))
                            'face face
                            'help-echo
                            (format "%s  %s  %d min"
                                    (plist-get e :started-str)
                                    outcome actual)))
        (insert " ")))
    (insert "\n")))

(defun org-focus--render-summary (entries)
  "Render an aggregate summary of ENTRIES."
  (let* ((counts (make-hash-table :test 'equal))
         (totals (make-hash-table :test 'equal))
         (grand-total 0))
    (dolist (e entries)
      (let ((outcome (plist-get e :outcome))
            (minutes (or (plist-get e :actual) 0)))
        (puthash outcome (1+ (gethash outcome counts 0)) counts)
        (puthash outcome (+ (gethash outcome totals 0) minutes) totals)
        (cl-incf grand-total minutes)))
    (insert (propertize (format "Summary over %d days\n" org-focus-dashboard-days)
                        'face 'bold))
    (dolist (outcome '("flow" "normal" "unfocused"))
      (let* ((count (gethash outcome counts 0))
             (mins (gethash outcome totals 0))
             (pct (if (> grand-total 0) (/ (* 100.0 mins) grand-total) 0))
             (face (pcase outcome
                     ("flow"      '(:foreground "#2ca02c" :weight bold))
                     ("normal"    '(:foreground "#1f77b4"))
                     ("unfocused" '(:foreground "#888888")))))
        (insert (format "  %-12s "
                        (propertize outcome 'face face)))
        (insert (format "%3d slices  %4d min  %5.1f%%\n" count mins pct))))
    (insert (format "  %-12s %3d slices  %4d min\n"
                    "total" (length entries) grand-total))))

(provide 'org-focus-timer)
;;; org-focus-timer.el ends here
