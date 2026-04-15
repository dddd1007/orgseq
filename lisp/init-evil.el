;;; init-evil.el --- Evil mode + SPC leader keys -*- lexical-binding: t; -*-

;; ---- Utility functions for leader keys ----

(defun my/copy-file-path ()
  "Copy the current buffer's file path to the kill ring."
  (interactive)
  (if-let ((path (buffer-file-name)))
      (progn (kill-new path) (message "Copied: %s" path))
    (message "Buffer has no file")))

(defun my/delete-current-file ()
  "Delete the current file and kill its buffer."
  (interactive)
  (let ((file (buffer-file-name)))
    (when (and file (yes-or-no-p (format "Delete %s?" file)))
      (delete-file file) (kill-buffer))))

(defun my/switch-to-dashboard ()
  "Switch to the *dashboard* buffer, or refresh if absent."
  (interactive)
  (if-let ((buf (get-buffer "*dashboard*")))
      (switch-to-buffer buf)
    (if (fboundp 'dashboard-open)
        (dashboard-open)
      (message "dashboard-open unavailable; try M-x dashboard-refresh-buffer"))))

;; Set before either evil or evil-collection loads to suppress the
;; evil-collection runtime warning.
(defvar evil-want-keybinding)
(setq evil-want-keybinding nil)

;; ---- Evil core ----
(use-package evil
  :demand t
  :init
  (setq evil-want-integration t
        evil-want-C-u-scroll t
        evil-want-C-i-jump nil          ; free C-i for org-mode TAB
        evil-want-Y-yank-to-eol t
        evil-undo-system 'undo-redo     ; Emacs 28+ native undo/redo
        evil-split-window-below t
        evil-vsplit-window-right t)
  :config
  (evil-mode 1)
  (evil-global-set-key 'motion "j" 'evil-next-visual-line)
  (evil-global-set-key 'motion "k" 'evil-previous-visual-line))

(use-package evil-collection
  :after evil
  :config (evil-collection-init
           '(bookmark dired ibuffer info magit org org-roam)))

;; ---- general.el: leader key framework ----
(use-package general
  :demand t
  :config
  (general-evil-setup t)

  ;; Primary leader: SPC (normal/visual/emacs), M-SPC (insert)
  (general-create-definer my/leader-keys
    :states '(normal visual emacs)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "M-SPC")

  ;; ═══════════════════════════════════════════════════════════════
  ;; SPC leader key system
  ;; ═══════════════════════════════════════════════════════════════

  (my/leader-keys
    ;; ── Top-level shortcuts ──
    "SPC" '(execute-extended-command :wk "M-x")
    "."   '(find-file :wk "Find file")
    ","   '(consult-buffer :wk "Switch buffer")
    "/"   '(consult-ripgrep :wk "Project search")
    "TAB" '(evil-switch-to-windows-last-buffer :wk "Last buffer")
    "RET" '(bookmark-jump :wk "Jump to bookmark")
    "'"   '(my/workspace-toggle-terminal :wk "Terminal popup")

    ;; ── SPC a — Agenda / GTD / Focus ──
    "a"   '(:ignore t :wk "agenda")
    "ad"  '(my/org-dashboard :wk "GTD Dashboard")
    "aa"  '(org-agenda :wk "Dispatcher")
    "an"  '(my/org-open-task-dashboard :wk "GTD overview")
    "ap"  '(my/org-open-project-dashboard :wk "Projects")
    "aw"  '(my/org-open-weekly-review :wk "Weekly review")
    "ac"  '(org-capture :wk "Capture")
    "ae"  '(my/gtd-set-state :wk "State picker")
    "au"  '(my/org-open-upcoming :wk "Upcoming")
    "a0"  '(my/org-open-inbox :wk "Inbox")
    "a1"  '(my/org-open-today :wk "Today")
    "a3"  '(my/org-open-anytime :wk "Anytime")
    "a4"  '(my/org-open-waiting :wk "Waiting")
    "a5"  '(my/org-open-someday :wk "Someday")
    "a6"  '(my/org-open-logbook :wk "Logbook")
    "a7"  '(my/org-pick-context :wk "Context view")
    "ar"  '((lambda () (interactive) (my/org-roam-agenda-files t)) :wk "Refresh cache")
    ;; Focus timer (Vitamin-R-style slices)
    "af"  '(org-focus-start :wk "Focus: start slice")
    "aF"  '(org-focus-dashboard :wk "Focus: dashboard")
    "aX"  '(org-focus-abort :wk "Focus: abort current")

    ;; ── SPC b — Buffer ──
    "b"   '(:ignore t :wk "buffer")
    "bb"  '(consult-buffer :wk "Switch")
    "bd"  '(kill-current-buffer :wk "Kill")
    "bs"  '(save-buffer :wk "Save")
    "bS"  '(evil-write-all :wk "Save all")
    "bn"  '(evil-buffer-new :wk "New")
    "br"  '(revert-buffer-quick :wk "Revert")
    "bl"  '(ibuffer :wk "List (ibuffer)")
    "bm"  '(bookmark-set :wk "Bookmark set")
    "bp"  '(previous-buffer :wk "Previous")
    "bN"  '(next-buffer :wk "Next")

    ;; ── SPC c — Casual (contextual Transient menus) ──
    "c"   '(:ignore t :wk "casual")
    "cc"  '(casual-editkit-main-tmenu :wk "EditKit (global)")
    "ca"  '(casual-agenda-tmenu :wk "Agenda menu")
    "cd"  '(casual-dired-tmenu :wk "Dired menu")
    "cb"  '(casual-bookmarks-tmenu :wk "Bookmarks menu")
    "cs"  '(casual-isearch-tmenu :wk "I-Search menu")

    ;; ── SPC e — Eval / Execute ──
    "e"   '(:ignore t :wk "eval")
    "ee"  '(eval-last-sexp :wk "Last sexp")
    "eb"  '(eval-buffer :wk "Buffer")
    "er"  '(eval-region :wk "Region")
    "ed"  '(eval-defun :wk "Defun")

    ;; ── SPC f — File ──
    "f"   '(:ignore t :wk "file")
    "ff"  '(find-file :wk "Open file")
    "fr"  '(consult-recent-file :wk "Recent files")
    "fs"  '(save-buffer :wk "Save")
    "fS"  '(write-file :wk "Save as")
    "fp"  '((lambda () (interactive) (find-file user-init-file)) :wk "Config")
    "fd"  '(consult-find :wk "Find by name (fd)")
    "fR"  '(rename-visited-file :wk "Rename")
    "fD"  '(my/delete-current-file :wk "Delete")
    "fy"  '(my/copy-file-path :wk "Copy path")
    "fj"  '(dired-jump :wk "Dired jump")

    ;; ── SPC g — Git ──
    "g"   '(:ignore t :wk "git")
    "gg"  '(magit-status :wk "Status")
    "gb"  '(magit-blame-addition :wk "Blame")
    "gl"  '(magit-log-current :wk "Log")
    "gd"  '(magit-diff-dwim :wk "Diff")
    "gf"  '(magit-file-dispatch :wk "File ops")

    ;; ── SPC h — Help (helpful-powered where available) ──
    "h"   '(:ignore t :wk "help")
    "hf"  '(helpful-callable :wk "Function")
    "hv"  '(helpful-variable :wk "Variable")
    "hk"  '(helpful-key :wk "Key")
    "hc"  '(helpful-command :wk "Command")
    "h."  '(helpful-at-point :wk "At point")
    "hm"  '(describe-mode :wk "Mode")
    "hi"  '(info :wk "Info manual")
    "hp"  '(describe-package :wk "Package")
    "ha"  '(apropos :wk "Apropos")

    ;; ── SPC i — AI ──
    "i"   '(:ignore t :wk "AI")
    "ii"  '(gptel-send :wk "Send to LLM")
    "im"  '(gptel-menu :wk "Menu (models/params)")
    "ic"  '(gptel :wk "Chat buffer")
    "ir"  '(gptel-rewrite :wk "Rewrite region")
    "ia"  '(gptel-add :wk "Add context")
    "is"  '(my/ai-summarize :wk "Summarize")
    "it"  '(my/ai-suggest-tags :wk "Suggest tags")
    "il"  '(my/ai-translate :wk "Translate")
    "ik"  '(my/ai-connections :wk "Find connections")
    "ip"  '(my/ai-improve :wk "Improve writing")
    "io"  '(my/ai-overview :wk "KB overview")
    "ig"  '(my/ai--ensure-context-files :wk "Init AI context")
    "iC"  '(claude-code-transient :wk "Claude Code")

    ;; ── SPC l — Layout / workspace ──
    "l"   '(:ignore t :wk "layout")
    "ll"  '(my/workspace-setup :wk "Open workspace")
    "l="  '(my/workspace-rebalance :wk "Rebalance layout")
    "lF"  '(my/workspace-apply-frame-size :wk "Fit frame")
    "lt"  '(my/workspace-toggle-sidebar :wk "Toggle sidebar (treemacs)")
    "lT"  '(treemacs-follow-mode :wk "Toggle sidebar follow current file")
    "lr"  '(my/workspace-reveal-sidebar :wk "Reveal current file in sidebar")
    "lR"  '(my/workspace-reveal-and-focus-sidebar :wk "Reveal and focus sidebar")
    "lf"  '(my/workspace-focus-sidebar :wk "Focus sidebar")
    "lh"  '(my/workspace-sidebar-jump-to-notehq :wk "Jump to NoteHQ root")
    "lc"  '(my/workspace-sidebar-collapse-all :wk "Collapse sidebar tree")
    "lw"  '(my/workspace-sidebar-set-width :wk "Set sidebar width")
    "lW"  '(my/workspace-sidebar-toggle-width-lock :wk "Toggle width lock")
    "lo"  '(my/workspace-toggle-outline :wk "Toggle outline")
    "le"  '(my/workspace-toggle-terminal :wk "Toggle terminal")
    "ld"  '(my/switch-to-dashboard :wk "Dashboard")

    ;; ── SPC n — Notes / org-roam ──
    "n"   '(:ignore t :wk "notes")
    "nn"  '(my/node-action :wk "Node actions")
    "nf"  '(deft :wk "Search all notes")
    "nF"  '(org-roam-node-find :wk "Find note (roam)")
    "ni"  '(org-roam-node-insert :wk "Insert link")
    "nc"  '(org-roam-capture :wk "New note")
    "nb"  '(org-roam-buffer-toggle :wk "Backlinks")
    "ng"  '(org-roam-ui-mode :wk "Graph view")
    "n/"  '(my/org-roam-rg-search :wk "Search note text")
    "na"  '(org-roam-alias-add :wk "Add alias")
    "nr"  '(org-roam-ref-add :wk "Add ref")
    "nL"  '(org-cliplink :wk "Paste link (cliplink)")
    "nI"  '(org-download-clipboard :wk "Paste image")
    "nl"  '(consult-org-roam-forward-links :wk "Forward links")
    "nB"  '(consult-org-roam-backlinks :wk "Backlinks (consult)")
    "n?"  '(consult-org-roam-search :wk "Search (consult)")

    ;; SPC n p — SuperTag (structured data operations)
    "np"  '(:ignore t :wk "supertag")
    "npp" '(my/supertag-quick-action :wk "Quick action")
    "npa" '(org-supertag-tag-add-tag :wk "Add tag")
    "npe" '(org-supertag-node-edit-field :wk "Edit field")
    "npx" '(org-supertag-tag-remove :wk "Remove tag")
    "npl" '(org-supertag-node-list-fields :wk "List fields")
    "npj" '(org-supertag-node-follow-ref :wk "Jump linked")
    "npk" '(supertag-view-kanban :wk "Kanban")
    "nps" '(supertag-search :wk "Search DB")
    "npS" '(supertag-sync-status :wk "Sync status")
    "npr" '(supertag-sync-check-now :wk "Sync now")
    "npR" '(supertag-sync-full-initialize :wk "Full rebuild")

    ;; SPC n v — Views / dashboards (read-only query windows)
    "nv"  '(:ignore t :wk "views")
    "nvv" '(my/dashboard-find :wk "Open dashboard")
    "nvw" '(my/dash-review :wk "Weekly review")
    "nvi" '(my/dash-index :wk "Dashboard index")

    ;; SPC n m — Meta: schema, templates, dashboards (extensibility hub)
    "nm"  '(:ignore t :wk "meta/extend")
    "nmt" '(my/edit-supertag-schema :wk "Edit tag schema")
    "nmT" '(my/reload-supertag-schema :wk "Reload tag schema")
    "nmc" '(my/edit-capture-templates :wk "Edit capture templates")
    "nmC" '(my/reload-capture-templates :wk "Reload capture templates")
    "nmd" '(my/dashboard-create :wk "Create new dashboard")

    ;; SPC n d — Dailies
    "nd"  '(:ignore t :wk "dailies")
    "ndd" '(my/org-roam-dailies-open-today :wk "Open today")
    "ndt" '(my/org-roam-dailies-open-today :wk "Open today")
    "ndy" '(org-roam-dailies-goto-yesterday :wk "Yesterday")
    "ndT" '(org-roam-dailies-goto-tomorrow :wk "Tomorrow")
    "ndf" '(org-roam-dailies-find-date :wk "Find date")
    "ndc" '(org-roam-dailies-capture-today :wk "Capture today")
    "ndC" '(org-roam-dailies-capture-date :wk "Capture date")
    "ndp" '(org-roam-dailies-goto-previous-note :wk "Previous note")
    "ndn" '(org-roam-dailies-goto-next-note :wk "Next note")

    ;; SPC n t — Transclusion
    "nt"  '(:ignore t :wk "transclusion")
    "nta" '(org-transclusion-add :wk "Add")
    "ntt" '(org-transclusion-mode :wk "Toggle mode")
    "ntm" '(org-transclusion-transient-menu :wk "Menu")
    "ntr" '(org-transclusion-refresh :wk "Refresh")

    ;; SPC n q — Query (org-ql)
    "nq"  '(:ignore t :wk "query")
    "nqs" '(org-ql-search :wk "Search")
    "nqv" '(org-ql-view :wk "View")

    ;; ── SPC o — Open ──
    "o"   '(:ignore t :wk "open")
    "ot"  '(my/workspace-toggle-terminal :wk "Terminal")
    "oD"  '(my/switch-to-dashboard :wk "Dashboard")
    "oa"  '(org-agenda :wk "Agenda")
    "of"  '(dirvish :wk "Dirvish (file manager)")
    "od"  '(dired-jump :wk "Dired (jump to file)")
    "oj"  '(dired :wk "Dired (pick directory)")
    "oe"  '((lambda () (interactive) (find-file user-emacs-directory)) :wk "Config dir")
    "oN"  '((lambda () (interactive) (dirvish my/note-home)) :wk "Dirvish @ NoteHQ")

    ;; ── SPC P — PARA layer navigation ──
    "P"   '(:ignore t :wk "PARA")
    "Po"  '(my/find-in-outputs :wk "Outputs")
    "Pp"  '(my/find-in-practice :wk "Practice")
    "Pl"  '(my/find-in-library :wk "Library")
    "Pg"  '(my/ripgrep-notehq :wk "Ripgrep all NoteHQ")

    ;; ── SPC p — Project ──
    "p"   '(:ignore t :wk "project")
    "pp"  '(project-switch-project :wk "Switch project")
    "pf"  '(project-find-file :wk "Find file")
    "ps"  '(consult-ripgrep :wk "Search")
    "pb"  '(project-switch-to-buffer :wk "Buffer")

    ;; ── SPC s — Search ──
    "s"   '(:ignore t :wk "search")
    "ss"  '(consult-line :wk "Buffer")
    "sp"  '(consult-ripgrep :wk "Project")
    "si"  '(consult-imenu :wk "Imenu")
    "so"  '(consult-outline :wk "Outline")
    "sb"  '(consult-bookmark :wk "Bookmark")
    "sf"  '(consult-find :wk "File by name")
    "sr"  '(query-replace :wk "Replace")
    "sR"  '(query-replace-regexp :wk "Replace regexp")

    ;; ── SPC t — Toggle ──
    "t"   '(:ignore t :wk "toggle")
    "tt"  '(consult-theme :wk "Theme")
    "tl"  '(display-line-numbers-mode :wk "Line numbers")
    "tw"  '(visual-line-mode :wk "Word wrap")
    "tf"  '(toggle-frame-fullscreen :wk "Fullscreen")
    "ti"  '(org-modern-mode :wk "Org-modern")
    "tn"  '(org-num-mode :wk "Heading numbers")
    "tm"  '(mixed-pitch-mode :wk "Mixed pitch")
    "th"  '(dired-omit-mode :wk "Hide dot-files / CLAUDE.md (dired)")

    ;; ── SPC w — Window ──
    "w"   '(:ignore t :wk "window")
    "wv"  '(evil-window-vsplit :wk "Vsplit")
    "ws"  '(evil-window-split :wk "Hsplit")
    "wd"  '(delete-window :wk "Close")
    "wm"  '(delete-other-windows :wk "Maximize")
    "wh"  '(evil-window-left :wk "Left")
    "wj"  '(evil-window-down :wk "Down")
    "wk"  '(evil-window-up :wk "Up")
    "wl"  '(evil-window-right :wk "Right")
    "w="  '(balance-windows :wk "Balance")
    "w>"  '(evil-window-increase-width :wk "Width +")
    "w<"  '(evil-window-decrease-width :wk "Width -")
    "w+"  '(evil-window-increase-height :wk "Height +")
    "w-"  '(evil-window-decrease-height :wk "Height -")
    "wo"  '(other-window :wk "Other window")

    ;; ── SPC q — Quit ──
    "q"   '(:ignore t :wk "quit")
    "qq"  '(save-buffers-kill-emacs :wk "Quit Emacs")
    "qu"  '(my/package-update-all :wk "Update packages")))

;; ---- magit: Git interface ----
;; Windows: may be slow on large repos, set magit-git-executable to full path if needed
(use-package magit
  :commands (magit-status magit-blame-addition magit-log-current
             magit-diff-dwim magit-file-dispatch))

;; ---- which-key: key hint popup (built-in on Emacs 30+) ----
(use-package which-key
  :ensure nil
  :demand t
  :init (which-key-mode)
  :config (setq which-key-idle-delay 0.3))

;; ---- Auto-dismiss which-key popup after 10s of inactivity ----
(defvar my/which-key-auto-dismiss-seconds 10
  "Seconds of idle time before auto-dismissing the which-key popup.")

(run-with-idle-timer
 my/which-key-auto-dismiss-seconds t
 (lambda ()
   (when (and (fboundp 'which-key--popup-showing-p)
              (which-key--popup-showing-p))
     (if (fboundp 'which-key--hide-popup)
         (which-key--hide-popup)
       (when (fboundp 'which-key-abort)
         (which-key-abort))))))

;; ---- Casual: Transient keyboard menus for built-in modes ----
(use-package casual
  :defer t
  :config
  ;; Mode-specific C-o bindings
  (with-eval-after-load 'org-agenda
    (keymap-set org-agenda-mode-map "C-o" #'casual-agenda-tmenu)
    (keymap-set org-agenda-mode-map "M-j" #'org-agenda-clock-goto)
    (keymap-set org-agenda-mode-map "J" #'bookmark-jump))
  (with-eval-after-load 'dired
    (keymap-set dired-mode-map "C-o" #'casual-dired-tmenu))
  (with-eval-after-load 'ibuffer
    (keymap-set ibuffer-mode-map "C-o" #'casual-ibuffer-tmenu)
    (keymap-set ibuffer-mode-map "s" #'casual-ibuffer-sortby-tmenu))
  (with-eval-after-load 'info
    (keymap-set Info-mode-map "C-o" #'casual-info-tmenu))
  (with-eval-after-load 'bookmark
    (keymap-set bookmark-bmenu-mode-map "C-o" #'casual-bookmarks-tmenu))
  (with-eval-after-load 'isearch
    (keymap-set isearch-mode-map "C-o" #'casual-isearch-tmenu))
  (with-eval-after-load 'calc
    (keymap-set calc-mode-map "C-o" #'casual-calc-tmenu))
  (with-eval-after-load 're-builder
    (keymap-set reb-mode-map "C-o" #'casual-re-builder-tmenu)))

;; ---- helpful: richer *Help* buffers (remaps describe-*) ----
(use-package helpful
  :commands (helpful-callable helpful-variable helpful-command
             helpful-key helpful-at-point helpful-symbol)
  :init
  (global-set-key [remap describe-function] #'helpful-callable)
  (global-set-key [remap describe-variable] #'helpful-variable)
  (global-set-key [remap describe-key]      #'helpful-key)
  (global-set-key [remap describe-command]  #'helpful-command)
  (global-set-key [remap describe-symbol]   #'helpful-symbol))

(provide 'init-evil)
;;; init-evil.el ends here
