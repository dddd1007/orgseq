;;; init-welcome.el --- First-run welcome page -*- lexical-binding: t; -*-

;; A read-only page that tells a new user where the library is, what to do
;; next, what the health checks found and which keys matter.  The page
;; explains state instead of nagging: finished steps stay visible, marked
;; as done.
;;
;; Section 1  Settings and state
;; Section 2  Page content as data (pure)
;; Section 3  Key lookup
;; Section 4  Rendering
;; Section 5  Mode and commands
;; Section 6  First-run logic

;; Requires: init-org  (the org-seq group, my/note-home)
;; Requires: init-sync (my/storage-info and the device-local state file)

(require 'cl-lib)
(require 'subr-x)
(require 'button)

(defvar my/workspace-startup-delay)
(defvar general-override-mode-map)

(declare-function my/storage-info "init-sync" ())
(declare-function my/sync--state "init-sync" ())
(declare-function my/sync--state-put "init-sync" (&rest changes))
(declare-function my/doctor-run "init-doctor" ())
(declare-function evil-set-initial-state "evil-core" (mode state))
(declare-function evil-define-key* "evil-core" (state keymap key def &rest bindings))
(declare-function evil-get-auxiliary-keymap "evil-core" (map state &optional create))

;; ---- Section 1: Settings and state ----

(defcustom my/welcome-at-startup 'first-run
  "When to show the welcome page at startup.
`first-run' shows it once per device, `always' on every interactive
start and `never' not at all.  The page stays available through
\\[my/welcome]."
  :type '(choice (const :tag "Once, on the first start of this device" first-run)
                 (const :tag "On every start" always)
                 (const :tag "Never" never))
  :group 'org-seq)

(defconst my/welcome-buffer-name "*org-seq welcome*"
  "Name of the welcome buffer.")

(defconst my/welcome--margin 3
  "Columns kept free at the right edge of the window.")

(defconst my/welcome--max-problems 6
  "Most health problems listed before the page points at the full report.")

(defvar-local my/welcome--data nil
  "Page content last rendered in this buffer.")

(defvar-local my/welcome--width nil
  "Window width the page was last rendered for.")

;; ---- Section 2: Page content as data (pure) ----
;;
;; A section is (:id SYMBOL :title STRING :lines LINES).  A line is one of
;;   (:text STRING [:face FACE])
;;   (:pair LABEL VALUE)
;;   (:item t :done BOOL :label STRING :command SYMBOL :key STRING [:note STRING])
;;   (:key KEY :label STRING :command SYMBOL)
;;   (:problem t :status SYMBOL :label STRING :detail STRING :remedy STRING)
;;   (:more STRING :command SYMBOL)
;;   (:blank)

(defconst my/welcome--documented-keys
  '((my/daily-workspace-open . "SPC d")
    (my/note-capture . "SPC c")
    (my/palette . "SPC k")
    (my/node-find . "SPC n n")
    (consult-ripgrep . "SPC /")
    (execute-extended-command . "SPC SPC")
    (my/sync-now . "SPC n S s")
    (my/sync-setup . "SPC n S c")
    (my/storage-import . "SPC n S i")
    (my/storage-snapshot . "SPC n S b")
    (my/storage-status . "SPC n S t"))
  "Documented leader keys, used when the live keymaps do not answer.")

(defconst my/welcome--key-rows
  '((my/daily-workspace-open "Daily workspace")
    (my/note-capture "New note")
    (my/palette "Command palette")
    (my/node-find "Find a note")
    (consult-ripgrep "Search text")
    (execute-extended-command "Any command (M-x)")
    (my/storage-snapshot "Snapshot the library")
    (my/sync-now "Sync now"))
  "Commands listed under Keys to remember, as (COMMAND LABEL), at most eight.")

(defun my/welcome--sync-on-p (info)
  "Return non-nil when INFO says a sync remote is configured."
  (let ((sync (plist-get info :sync)))
    (and (stringp sync) (not (string-prefix-p "sync off" sync)))))

(defun my/welcome--plural (count singular)
  "Return \"COUNT SINGULAR\", pluralised with an s when COUNT is not 1."
  (format "%d %s%s" count singular (if (= count 1) "" "s")))

(defun my/welcome--key-of (keymap command)
  "Return the key text for COMMAND from KEYMAP, an alist of (COMMAND . TEXT)."
  (cdr (assq command keymap)))

(defun my/welcome--library-lines (info)
  "Return the Your library lines for storage plist INFO."
  (let ((notes (or (plist-get info :notes) 0))
        (snapshots (or (plist-get info :snapshots) 0))
        (last (plist-get info :last-snapshot)))
    (list
     (list :pair "Location"
           (abbreviate-file-name (or (plist-get info :library) "unknown")))
     (list :pair "Notes"
           (format "%s (%s in all)"
                   (my/welcome--plural notes "Org file")
                   (my/welcome--plural (or (plist-get info :files) 0) "file")))
     (list :pair "Snapshots"
           (if (> snapshots 0)
               (format "%d in %s%s" snapshots
                       (abbreviate-file-name (or (plist-get info :snapshot-dir) ""))
                       (if last (format ", newest %s" last) ""))
             (format "none yet; they go to %s"
                     (abbreviate-file-name (or (plist-get info :snapshot-dir) "")))))
     (list :pair "Sync" (or (plist-get info :sync) "unknown")))))

(defun my/welcome--item (done label command keymap &optional note)
  "Return a checklist line: DONE flag, LABEL, COMMAND, KEYMAP lookup, NOTE."
  (append (list :item t :done (and done t) :label label :command command
                :key (or (my/welcome--key-of keymap command)
                         (format "M-x %s" command)))
          (and note (list :note note))))

(defun my/welcome--steps-lines (info keymap)
  "Return the Next steps lines for storage plist INFO and KEYMAP."
  (let* ((notes (or (plist-get info :notes) 0))
         (snapshots (or (plist-get info :snapshots) 0))
         (legacy (plist-get info :legacy))
         (sync-on (my/welcome--sync-on-p info)))
    (list
     (my/welcome--item (and (> notes 0) (not legacy))
                       "Bring existing notes in" 'my/storage-import keymap
                       (and legacy
                            (format "The old library at %s has not been imported."
                                    (abbreviate-file-name legacy))))
     (my/welcome--item sync-on "Set up sync" 'my/sync-setup keymap
                       (and sync-on (plist-get info :sync)))
     (my/welcome--item (> snapshots 0) "Take a first snapshot"
                       'my/storage-snapshot keymap
                       (and (> snapshots 0)
                            (format "%s taken."
                                    (my/welcome--plural snapshots "snapshot"))))
     (my/welcome--item nil "Open today's Daily" 'my/daily-workspace-open keymap)
     (my/welcome--item (> notes 0) "Create a first note" 'my/note-capture keymap)
     (my/welcome--item nil "Open the command palette" 'my/palette keymap))))

(defun my/welcome--health-lines (results)
  "Return the Health lines for doctor RESULTS (plists)."
  (let ((problems (cl-remove-if
                   (lambda (result) (eq (plist-get result :status) 'pass))
                   results)))
    (if (null problems)
        (list (list :text "Everything passed."))
      (append
       (mapcar (lambda (result)
                 (list :problem t
                       :status (plist-get result :status)
                       :label (plist-get result :label)
                       :detail (plist-get result :detail)
                       :remedy (plist-get result :remedy)))
               (seq-take problems my/welcome--max-problems))
       (when (> (length problems) my/welcome--max-problems)
         (list (list :more (format "%d more checks need attention."
                                   (- (length problems) my/welcome--max-problems))
                     :command 'my/doctor)))))))

(defun my/welcome--keys-lines (keymap)
  "Return the Keys to remember lines using KEYMAP."
  (mapcar (lambda (row)
            (let ((command (car row)))
              (list :key (or (my/welcome--key-of keymap command)
                             (format "M-x %s" command))
                    :label (cadr row)
                    :command command)))
          (seq-take my/welcome--key-rows 8)))

(defun my/welcome-data (info results keymap)
  "Return the welcome page as a list of sections.
INFO is a plist as returned by `my/storage-info', RESULTS a list of
doctor result plists and KEYMAP an alist of (COMMAND . KEY-TEXT).  No
buffer or window is involved."
  (list
   (list :id 'header :title nil
         :lines (list (list :text "org-seq" :face 'bold)
                      (list :text "Your notes are plain Org files on your own disk.")))
   (list :id 'library :title "Your library"
         :lines (my/welcome--library-lines info))
   (list :id 'steps :title "Next steps"
         :lines (my/welcome--steps-lines info keymap))
   (list :id 'health :title "Health"
         :lines (my/welcome--health-lines results))
   (list :id 'keys :title "Keys to remember"
         :lines (my/welcome--keys-lines keymap))
   (list :id 'footer :title nil
         :lines (list (list :text
                            (format "Reopen this page with %s. To stop it showing at startup, set my/welcome-at-startup to never."
                                    (or (my/welcome--key-of keymap 'my/welcome)
                                        "M-x my/welcome"))
                            :face 'shadow)))))

;; ---- Section 3: Key lookup ----

(defun my/welcome--lookup-maps ()
  "Return the keymaps searched for a command's keys, as `where-is-internal' wants.
The global and active maps come first, then the override map that holds
the SPC leader, including its Evil state maps when Evil is loaded."
  (let (maps)
    (when (and (boundp 'general-override-mode-map)
               (keymapp general-override-mode-map))
      (push general-override-mode-map maps)
      (when (fboundp 'evil-get-auxiliary-keymap)
        (dolist (state '(normal visual emacs))
          (let ((aux (ignore-errors
                       (evil-get-auxiliary-keymap general-override-mode-map state))))
            (when (keymapp aux) (push aux maps))))))
    (nreverse maps)))

(defun my/welcome--live-key (command)
  "Return the shortest leader key text for COMMAND from live keymaps, or nil."
  (let (texts)
    (dolist (map (cons nil (my/welcome--lookup-maps)))
      (dolist (key (ignore-errors (where-is-internal command map)))
        (push (key-description key) texts)))
    (let ((leader (cl-remove-if-not (lambda (text) (string-prefix-p "SPC " text))
                                    texts))
          (plain (cl-remove-if (lambda (text)
                                 (or (string-prefix-p "M-SPC" text)
                                     (string-match-p "state>" text)
                                     (string-match-p "\\`<" text)))
                               texts)))
      (car (sort (copy-sequence (or leader plain))
                 (lambda (a b) (< (length a) (length b))))))))

(defun my/welcome-key-alist ()
  "Return (COMMAND . KEY-TEXT) for every command the page mentions.
Keys come from the live keymaps so the page cannot drift from the real
bindings; the documented key is the fallback."
  (let (alist)
    (dolist (command (append (mapcar #'car my/welcome--key-rows)
                             '(my/storage-import my/sync-setup my/welcome)))
      (let ((text (or (my/welcome--live-key command)
                      (cdr (assq command my/welcome--documented-keys)))))
        (when text (push (cons command text) alist))))
    (dolist (entry my/welcome--documented-keys)
      (unless (assq (car entry) alist) (push entry alist)))
    (nreverse alist)))

;; ---- Section 4: Rendering ----

(defun my/welcome--wrap (text width)
  "Split TEXT into lines of at most WIDTH columns.
Break at spaces; a word longer than WIDTH, such as a path, is broken at
a slash or at the column limit."
  (let (lines (rest (string-trim text)))
    (while (> (string-width rest) width)
      (let* ((head (truncate-string-to-width rest width))
             (cut (or (let ((pos (string-match-p " [^ ]*\\'" head)))
                        (and pos (> pos 0) pos))
                      (let ((pos (string-match-p "/[^/]*\\'" head)))
                        (and pos (> pos 0) (1+ pos)))
                      (length head))))
        (push (string-trim-right (substring rest 0 cut)) lines)
        (setq rest (string-trim-left (substring rest cut)))))
    (push rest lines)
    (nreverse lines)))

(defun my/welcome--insert-wrapped (text width &optional indent face)
  "Insert TEXT wrapped to WIDTH columns, each line indented by INDENT."
  (let ((pad (make-string (or indent 0) ?\s)))
    (dolist (line (my/welcome--wrap text (- width (or indent 0))))
      (insert pad (if face (propertize line 'face face) line) "\n"))))

(defun my/welcome--run-command (button)
  "Run the command stored on BUTTON."
  (let ((command (button-get button 'my/welcome-command)))
    (when (commandp command)
      (call-interactively command))))

(defun my/welcome--insert-button (label command)
  "Insert LABEL as a button that runs COMMAND."
  (insert-text-button label
                      'action #'my/welcome--run-command
                      'my/welcome-command command
                      'follow-link t
                      'help-echo (format "Run %s" command)))

(defun my/welcome--render-pair (label value width)
  "Insert LABEL and VALUE, in one row when they fit and in two otherwise."
  (let ((col 11))
    (if (<= (+ col (string-width value)) width)
        (insert (propertize (string-pad label col) 'face 'shadow) value "\n")
      (insert (propertize label 'face 'shadow) "\n")
      (my/welcome--insert-wrapped value width 2))))

(defun my/welcome--render-item (line width)
  "Insert checklist LINE within WIDTH columns."
  (let* ((done (plist-get line :done))
         (label (plist-get line :label))
         (key (plist-get line :key))
         (note (plist-get line :note))
         (mark (if done "[x] " "[ ] ")))
    (insert (propertize mark 'face (if done 'success 'shadow)))
    (my/welcome--insert-button label (plist-get line :command))
    (if (<= (+ 4 (string-width label) 2 (string-width key)) width)
        (insert "  " (propertize key 'face 'shadow) "\n")
      (insert "\n")
      (my/welcome--insert-wrapped key width 4 'shadow))
    (when note
      (my/welcome--insert-wrapped note width 4 'shadow))))

(defun my/welcome--render-key (line key-width width)
  "Insert key row LINE with the key column KEY-WIDTH inside WIDTH columns."
  (let ((key (plist-get line :key))
        (label (plist-get line :label)))
    (if (<= (+ key-width 2 (string-width label)) width)
        (progn (insert (propertize (string-pad key (+ key-width 2)) 'face 'bold))
               (my/welcome--insert-button label (plist-get line :command))
               (insert "\n"))
      (insert (propertize key 'face 'bold) "\n  ")
      (my/welcome--insert-button label (plist-get line :command))
      (insert "\n"))))

(defun my/welcome--render-problem (line width)
  "Insert health problem LINE within WIDTH columns."
  (let* ((status (plist-get line :status))
         (tag (if (eq status 'fail) "FAIL" "WARN")))
    (insert (propertize tag 'face (if (eq status 'fail) 'error 'warning))
            "  " (plist-get line :label) "\n")
    (when-let* ((detail (plist-get line :detail)))
      (my/welcome--insert-wrapped detail width 6 'shadow))
    (when-let* ((remedy (plist-get line :remedy)))
      (my/welcome--insert-wrapped (concat "Fix: " remedy) width 6))))

(defun my/welcome--render-line (line key-width width)
  "Insert one page LINE for a window of WIDTH columns and key column KEY-WIDTH."
  (pcase (car line)
    (:text (my/welcome--insert-wrapped (cadr line) width 0 (plist-get line :face)))
    (:pair (my/welcome--render-pair (nth 1 line) (nth 2 line) width))
    (:item (my/welcome--render-item line width))
    (:key (my/welcome--render-key line key-width width))
    (:problem (my/welcome--render-problem line width))
    (:more (my/welcome--insert-wrapped (cadr line) width 0 'shadow)
           (my/welcome--insert-button "Open the full report"
                                      (plist-get line :command))
           (insert "\n"))
    (:blank (insert "\n"))))

(defun my/welcome-render (data width)
  "Insert DATA, the result of `my/welcome-data', at point for WIDTH columns."
  (dolist (section data)
    (let ((title (plist-get section :title))
          (lines (plist-get section :lines)))
      (when title
        (insert (propertize title 'face 'bold) "\n"))
      (let ((key-width (apply #'max 0
                              (mapcar (lambda (line)
                                        (if (eq (car line) :key)
                                            (string-width (plist-get line :key))
                                          0))
                                      lines))))
        (dolist (line lines)
          (my/welcome--render-line line key-width width)))
      (insert "\n"))))

(defun my/welcome--width ()
  "Return the page width for the window showing the welcome buffer."
  (let ((window (or (get-buffer-window (current-buffer) t) (selected-window))))
    (max 30 (- (window-body-width window) my/welcome--margin))))

(defun my/welcome--redraw ()
  "Render the cached page data into the current buffer, keeping point's line."
  (let ((line (line-number-at-pos))
        (inhibit-read-only t)
        (width (my/welcome--width)))
    (erase-buffer)
    (my/welcome-render my/welcome--data width)
    (setq my/welcome--width width)
    (goto-char (point-min))
    (forward-line (1- line))))

;; ---- Section 5: Mode and commands ----

(defvar my/welcome-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'push-button)
    (define-key map (kbd "TAB") #'forward-button)
    (define-key map (kbd "<backtab>") #'backward-button)
    (define-key map (kbd "g") #'my/welcome-refresh)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `my/welcome-mode'.")

(define-derived-mode my/welcome-mode special-mode "org-seq-welcome"
  "Major mode of the org-seq welcome page.
\\{my/welcome-mode-map}"
  (setq-local revert-buffer-function (lambda (&rest _) (my/welcome-refresh)))
  (add-hook 'window-configuration-change-hook
            #'my/welcome--maybe-redraw nil t))

(with-eval-after-load 'evil
  (when (fboundp 'evil-set-initial-state)
    (evil-set-initial-state 'my/welcome-mode 'normal))
  (when (fboundp 'evil-define-key*)
    (evil-define-key* 'normal my/welcome-mode-map
      (kbd "RET") #'push-button
      (kbd "TAB") #'forward-button
      (kbd "<backtab>") #'backward-button
      "g" #'my/welcome-refresh
      "q" #'quit-window)))

(defun my/welcome--maybe-redraw ()
  "Render again when the window showing this buffer changed width."
  (when (and my/welcome--data (get-buffer-window (current-buffer))
             (not (eql my/welcome--width (my/welcome--width))))
    (my/welcome--redraw)))

(defun my/welcome--collect ()
  "Gather storage info and doctor results and return the page data."
  (my/welcome-data
   (ignore-errors (my/storage-info))
   (and (fboundp 'my/doctor-run) (ignore-errors (my/doctor-run)))
   (my/welcome-key-alist)))

(defun my/welcome-refresh ()
  "Read the library state again and redraw the welcome page."
  (interactive)
  (setq my/welcome--data (my/welcome--collect))
  (my/welcome--redraw)
  (message "org-seq welcome refreshed"))

(defun my/welcome--target-window ()
  "Return the window that should show the welcome page.
The selected window, unless it is a dedicated or side window such as the
Daily sidebar; then the first ordinary window of the frame."
  (let ((window (selected-window)))
    (if (or (window-dedicated-p window) (window-parameter window 'window-side))
        (or (cl-find-if (lambda (candidate)
                          (not (or (window-dedicated-p candidate)
                                   (window-parameter candidate 'window-side)
                                   (window-minibuffer-p candidate))))
                        (window-list))
            window)
      window)))

;;;###autoload
(defun my/welcome ()
  "Show the org-seq welcome page in the main window.
\\<my/welcome-mode-map>\\[quit-window] returns to the previous buffer."
  (interactive)
  (let ((buffer (get-buffer-create my/welcome-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'my/welcome-mode)
        (my/welcome-mode)))
    (with-selected-window (my/welcome--target-window)
      (pop-to-buffer-same-window buffer))
    (select-window (or (get-buffer-window buffer) (selected-window)))
    (with-current-buffer buffer
      (setq my/welcome--data (my/welcome--collect))
      (my/welcome--redraw)
      (goto-char (point-min))
      (ignore-errors (forward-button 1)))
    buffer))

;; ---- Section 6: First-run logic ----

(defun my/welcome--shown-p ()
  "Return non-nil when this device has recorded showing the page."
  (and (plist-get (my/sync--state) :welcome-shown) t))

(defun my/welcome--record-shown ()
  "Record in the device-local state that the page was shown, once."
  (unless (my/welcome--shown-p)
    (my/sync--state-put :welcome-shown (format-time-string "%Y-%m-%d"))))

(defun my/welcome--startup-show ()
  "Show the page for the startup path and record that it was shown."
  (when (not (eq my/welcome-at-startup 'never))
    (my/welcome)
    (my/welcome--record-shown)))

(defun my/welcome--daemon-without-frame-p ()
  "Return non-nil in a daemon whose only frame is the initial one."
  (and (daemonp)
       (equal (terminal-name (frame-terminal)) "initial_terminal")))

(defun my/welcome--startup-delay ()
  "Return the idle delay that lets the startup workspace settle first."
  (+ (if (boundp 'my/workspace-startup-delay) my/workspace-startup-delay 0.3)
     0.7))

(defun my/welcome--schedule-in-new-frame ()
  "Show the page on the first frame created after a frameless daemon start."
  (let (hook)
    (setq hook (lambda (_frame)
                 (remove-hook 'after-make-frame-functions hook)
                 (my/welcome-maybe-show)))
    (add-hook 'after-make-frame-functions hook)))

(defun my/welcome-maybe-show ()
  "Show the welcome page when `my/welcome-at-startup' asks for it.
This is the one function to call at startup.  It does nothing in batch
mode.  In a daemon without a frame it waits for the first frame.  The
page is shown after an idle delay so that the Daily workspace layout is
built first and stays intact; the shown flag lands in the device-local
state file the first time only."
  (cond
   (noninteractive nil)
   ((eq my/welcome-at-startup 'never) nil)
   ((and (eq my/welcome-at-startup 'first-run) (my/welcome--shown-p)) nil)
   ((my/welcome--daemon-without-frame-p)
    (my/welcome--schedule-in-new-frame)
    'deferred)
   (t (run-with-idle-timer (my/welcome--startup-delay) nil
                           #'my/welcome--startup-show)
      'scheduled)))

;; Shown once on the first interactive start of a device; see
;; `my/welcome-at-startup'.  Does nothing in a batch session.
(add-hook 'emacs-startup-hook #'my/welcome-maybe-show)

(provide 'init-welcome)
;;; init-welcome.el ends here
