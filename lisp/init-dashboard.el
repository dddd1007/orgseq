;;; init-dashboard.el --- Startup dashboard -*- lexical-binding: t; -*-

(require 'cl-lib)

;; ---- recentf: track recently opened files ----
(require 'recentf)
(setq recentf-max-saved-items 30
      recentf-exclude '("\\.git/" "COMMIT_EDITMSG" "/tmp/" "/ssh:"
                        ".*-autoloads\\.el\\'" "[/\\\\]elpa/"
                        "\\.emacs\\.d/"))
(recentf-mode 1)

(defun my/dashboard-open-last-file ()
  "Open the most recently edited file."
  (interactive)
  (if recentf-list
      (find-file (car recentf-list))
    (message "No recent files found")))

(defun my/dashboard-icon (name &optional fallback)
  "Return nerd-icon for NAME, or FALLBACK string on error."
  (condition-case nil
      (nerd-icons-mdicon name)
    (error (or fallback ">"))))

;; ---- dashboard: Doom-style startup screen ----
(use-package dashboard
  :demand t
  :config
  (setq dashboard-startup-banner
        (expand-file-name "banner-compact.txt"
                          (file-name-directory
                           (or load-file-name buffer-file-name))))

  (setq dashboard-banner-logo-title nil
        dashboard-center-content t
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-icon-type 'nerd-icons
        dashboard-recentf-show-base t
        dashboard-recentf-item-format "%s")

  (setq dashboard-items '((recents . 5)))
  (setq dashboard-item-shortcuts '((recents . "r")))

  ;; Footer: random quote, Doom-style
  (defvar my/dashboard-quotes
    '(;; ── Emacs self-deprecation ──
      "The one true editor, Emacs!"
      "Who the hell uses VIM anyway? Go Evil!"
      "While any text editor can save your files, only Emacs can save your soul."
      "Vi Vi Vi, the editor of the beast."
      "Welcome to the church of Emacs."
      "I showed you my source code, pls respond."
      "Emacs is a great operating system, lacking only a decent editor."
      "M-x butterfly"
      "Emacs started as a text editor. Then it got ideas."
      "There is no place like ~"
      "~ sweet ~"
      "Your .emacs.d is a lifestyle choice."
      "The strstrstrstrstruggle is real. — Emacs Pinky"
      "Escape-Meta-Alt-Control-Shift. That's all."
      "M-x doctor — cheaper than therapy since 1985."
      "Real programmers use cat > program.c. The rest of us use Emacs."
      "(setq my-life nil) ;; it happens"
      "My software never has bugs. It just develops random features."
      "It compiles. Ship it."
      "Emacs outshines all other editors in approximately the same way that the noonday sun does the stars."
      "Free as free speech, free as free Beer."

      ;; ── Org / PKM / GTD humor ──
      "Org-mode is for keeping notes, maintaining TODO lists, and avoiding actual work. — Everyone"
      "Your mind is for having ideas, not holding them. That's what org-capture is for."
      "I don't have a system. I have 400 TODO items in 37 org files."
      "NEXT → IN-PROGRESS → WAITING → Who am I kidding → SOMEDAY"
      "I came here to write notes and chew bubblegum… and I'm all out of bubblegum."
      "The Zettelkasten doesn't think for you. It just judges you, silently."
      "Tags are just labels for things you'll never search for again."
      "If it's not in org-roam, it didn't happen."
      "One does not simply close the org-agenda."

      ;; ── Programming / nerd wisdom ──
      "Talk is cheap. Show me the code. — Linus Torvalds"
      "First, solve the problem. Then, write the code. — John Johnson"
      "Make it work, make it right, make it fast. — Kent Beck"
      "A complex system that works evolved from a simple system that worked. — John Gall"
      "The best code is no code at all."
      "Dad, what are clouds made of? Linux servers, mostly."
      "There are only two hard things in CS: cache invalidation, naming things, and off-by-one errors."
      "It works on my machine. ¯\\_(ツ)_/¯"
      "// TODO: fix this later   — commit from 2019"

      ;; ── Dark / existential ──
      "Perfection is achieved not when there is nothing more to add, but nothing left to take away."
      "Any sufficiently advanced .emacs.d is indistinguishable from an operating system."
      "The unexamined config is not worth loading."
      "You are what you (eval-buffer)."

      ;; ── Classic wisdom ──
      "The only way to do great work is to love what you do. — Steve Jobs"
      "Simplicity is the ultimate sophistication. — Leonardo da Vinci"
      "The mind is not a vessel to be filled, but a fire to be kindled. — Plutarch"
      "We are what we repeatedly do. Excellence is not an act, but a habit. — Aristotle"
      "In the middle of difficulty lies opportunity. — Albert Einstein"
      "The unexamined life is not worth living. — Socrates"
      "Knowing is not enough; we must apply. — Goethe"
      "Any sufficiently advanced technology is indistinguishable from magic. — Arthur C. Clarke"
      "The best time to plant a tree was 20 years ago. The second best time is now. — Chinese Proverb"
      "Programs must be written for people to read. — Harold Abelson"
      "The tools we use have a profound effect on our thinking habits. — Edsger Dijkstra"
      "Zettelkasten is not a method of storage, but a method of thinking. — Niklas Luhmann"
      "Your mind is for having ideas, not holding them. — David Allen"

      ;; ── Emacs tips (org-seq specific) ──
      "Tip: SPC SPC opens M-x — run any command by name."
      "Tip: SPC / searches the whole project with ripgrep."
      "Tip: SPC n f to find any org-roam note instantly."
      "Tip: SPC a d opens the GTD Dashboard with live task counts."
      "Tip: , q in org buffers opens a single-keypress state picker."
      "Tip: SPC n d d captures a daily note for today."
      "Tip: SPC i i sends the current buffer to your LLM."
      "Tip: SPC TAB switches to the last buffer you were in."
      "Tip: SPC l l opens the full three-column workspace layout."
      "Tip: C-o in Dired/Agenda/Info opens a Casual menu with all actions."
      "Tip: SPC t t lets you switch themes on the fly."
      "Tip: SPC n s a adds a supertag to the current heading."
      "Tip: SPC w m maximizes the current window. SPC w = rebalances all."
      "Tip: SPC s s searches the current buffer with consult-line."
      "Tip: SPC f r opens recent files — your most-used shortcut."
      "Tip: SPC n t a adds a transclusion link for live content embedding."
      "Tip: SPC a w opens the weekly review — check stuck projects."
      "Tip: , k i clocks into a task. , k o clocks out. , k r shows report."
      "Tip: SPC g g opens Magit status — the best Git interface ever made."
      "Tip: SPC i m opens the gptel menu — switch models, adjust params."
      "Tip: In vertico, C-j/C-k moves up/down. RET confirms."
      "Tip: SPC h f describes any function. SPC h v describes any variable."
      "Tip: SPC b d kills the current buffer. SPC b l opens ibuffer."
      "Tip: winner-mode is on — C-c <left> undoes window layout changes."
      "Tip: SPC e e evals the last sexp. SPC e b evals the whole buffer."
      "Tip: SPC ' toggles a terminal popup at the bottom."))

  (defun my/dashboard--wrap-quote (text max-width)
    "Wrap TEXT to MAX-WIDTH at word boundaries, returning a single string."
    (if (<= (length text) max-width)
        text
      (let ((pos max-width))
        (while (and (> pos 0) (not (eq (aref text pos) ?\s)))
          (cl-decf pos))
        (when (= pos 0) (setq pos max-width))
        (concat (substring text 0 pos) "\n"
                (string-trim-left (substring text pos))))))

  (defun my/dashboard--pick-quote ()
    "Pick a random quote and wrap it to fit the dashboard width."
    (let* ((quote (nth (random (length my/dashboard-quotes)) my/dashboard-quotes))
           (width (max 40 (- (min 80 (window-width)) 6))))
      (setq dashboard-footer-messages
            (list (my/dashboard--wrap-quote quote width)))))

  (my/dashboard--pick-quote)
  (setq dashboard-footer-icon
        (my/dashboard-icon "nf-md-format_quote_open" ""))

  (add-hook 'dashboard-before-initialize-hook #'my/dashboard--pick-quote)

  ;; Compact component ordering (fewer blank lines)
  (setq dashboard-startupify-list
        '(dashboard-insert-banner
          dashboard-insert-navigator
          dashboard-insert-init-info
          dashboard-insert-items
          dashboard-insert-footer))

  ;; Quick action buttons — horizontal row
  (setq dashboard-navigator-buttons
        `(((,(my/dashboard-icon "nf-md-notebook_edit")
           " Today " "Open today's daily note  [SPC n d d]"
           (lambda (&rest _) (org-roam-dailies-capture-today)))
          (,(my/dashboard-icon "nf-md-magnify")
           " Find " "Find an org-roam note  [SPC n f]"
           (lambda (&rest _) (org-roam-node-find)))
          (,(my/dashboard-icon "nf-md-format_list_checks")
           " Tasks " "Open GTD task dashboard  [SPC a n]"
           (lambda (&rest _) (my/org-open-task-dashboard)))
          (,(my/dashboard-icon "nf-md-calendar_week")
           " Review " "Open weekly review  [SPC a w]"
           (lambda (&rest _) (my/org-open-weekly-review)))
          (,(my/dashboard-icon "nf-md-history")
           " Last File " "Open the most recently edited file"
           (lambda (&rest _) (my/dashboard-open-last-file))))))

  ;; ---- Vertical centering ----

  (defvar-local my/dashboard--content-lines nil
    "Cached line count of dashboard content before padding.")

  (defun my/dashboard-vertically-center ()
    "Pad the top of the dashboard buffer to vertically center content."
    (when-let ((buf (get-buffer dashboard-buffer-name)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          ;; Strip existing top padding
          (goto-char (point-min))
          (while (and (not (eobp)) (looking-at-p "^$"))
            (delete-region (line-beginning-position)
                           (min (1+ (line-end-position)) (point-max))))
          ;; Strip trailing blank lines
          (goto-char (point-max))
          (while (and (> (point) (point-min))
                      (progn (forward-line -1) (looking-at-p "^$")))
            (delete-region (line-beginning-position)
                           (min (1+ (line-end-position)) (point-max))))
          ;; Cache the true content height
          (setq my/dashboard--content-lines
                (count-lines (point-min) (point-max)))
          ;; Insert top padding
          (let* ((win (or (get-buffer-window buf) (selected-window)))
                 (win-height (window-body-height win))
                 (pad (max 0 (/ (- win-height my/dashboard--content-lines) 2))))
            (goto-char (point-min))
            (insert (make-string pad ?\n))
            (goto-char (point-min)))))))

  (add-hook 'dashboard-after-initialize-hook #'my/dashboard-vertically-center)

  (defvar my/dashboard--resize-timer nil
    "Debounce timer for dashboard resize centering.")

  (defun my/dashboard-recenter-on-resize (&optional _frame)
    "Re-center dashboard when window size changes (debounced)."
    (when (and (get-buffer dashboard-buffer-name)
               (get-buffer-window dashboard-buffer-name))
      (when my/dashboard--resize-timer
        (cancel-timer my/dashboard--resize-timer))
      (setq my/dashboard--resize-timer
            (run-with-idle-timer 0.1 nil #'my/dashboard-vertically-center))))

  (add-hook 'window-size-change-functions #'my/dashboard-recenter-on-resize)

  (setq initial-buffer-choice
        (lambda () (get-buffer-create dashboard-buffer-name)))

  (dashboard-setup-startup-hook))

(provide 'init-dashboard)
;;; init-dashboard.el ends here
