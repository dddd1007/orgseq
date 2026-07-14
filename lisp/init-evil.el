;;; init-evil.el --- Evil mode + SPC leader keys -*- lexical-binding: t; -*-

;; Requires: init-keymap (leader prefix and critical binding contract)
(declare-function my/keymap-apply-general-contract "init-keymap" ())

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

;; ---- evil-surround: manage delimiters/pairs (vim-surround) ----
;; ys/cs/ds add/change/delete surroundings; visual S surrounds a selection.
;; In org, the single-char inline markers are pairs already (= ~ * / _ +),
;; so `S =` wraps a selection as verbatim, `cs = *` swaps to bold, `ds *`
;; removes the bold.
(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1))

;; ---- avy: jump to any character on screen (Helix-style labels) ----
;; SPC j reads a few chars, then labels every on-screen match with a key.
(use-package avy
  :defer t
  :custom
  (avy-timeout-seconds 0.4))

;; ---- evil-multiedit: select/edit occurrences like Sublime Ctrl+D ----
;; M-d adds the next match under point to the edit, M-D the previous one,
;; and visual R selects every match inside the region.  The M-d binding
;; lives in evil normal/visual state; the corfu completion popup also uses
;; M-d inside corfu-map, but only while a candidate menu is visible (insert
;; state), so the two never collide.
(use-package evil-multiedit
  :after evil
  :config
  (evil-multiedit-default-keybinds))

;; ---- vundo: visual undo tree (VS Code Timeline's kin) ----
;; Works on top of evil-undo-system 'undo-redo (Emacs native undo), so no
;; undo-tree needed.  SPC b u opens the tree for the current buffer.
(use-package vundo
  :defer t
  :custom
  (vundo-glyph-alist vundo-unicode-symbols))

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
  ;;
  ;; Ergonomic rules (documented in README "Key Bindings"):
  ;;   1. Groups are nouns: n notes, t tasks, a AI, f file, u UI, ...
  ;;   2. Doubled key = the group's primary action: SPC f f find file,
  ;;      SPC n n find note, SPC t t today, SPC g g git status.
  ;;   3. Highest-frequency actions are single top-level keys:
  ;;      SPC d Daily, SPC c capture note, SPC / search, SPC m menu.
  ;; ═══════════════════════════════════════════════════════════════

  (my/leader-keys
    ;; ── Top-level direct actions ──
    "SPC" '(execute-extended-command :wk "M-x")
    "d"   '(my/daily-workspace-open :wk "Daily workspace")
    "c"   '(org-roam-capture :wk "New note")
    "m"   '(casual-editkit-main-tmenu :wk "Menu (Casual)")
    "/"   '(consult-ripgrep :wk "Search project")
    "TAB" '(evil-switch-to-windows-last-buffer :wk "Last buffer")
    "'"   '(my/terminal-popup-toggle :wk "Terminal popup")
    "j"   '(avy-goto-char-timer :wk "Jump to char")

    ;; ── SPC t — Tasks / GTD / Focus ──
    "t"   '(:ignore t :wk "tasks")
    "tt"  '(my/org-open-today :wk "Today")
    "td"  '(my/org-dashboard :wk "GTD Dashboard")
    "to"  '(my/org-open-task-dashboard :wk "Overview")
    "tp"  '(my/org-open-project-dashboard :wk "Projects")
    "tr"  '(my/org-open-weekly-review :wk "Weekly review")
    "ti"  '(my/org-open-inbox :wk "Inbox")
    "tu"  '(my/org-open-upcoming :wk "Upcoming")
    "ta"  '(my/org-open-anytime :wk "Anytime (NEXT)")
    "tw"  '(my/org-open-waiting :wk "Waiting")
    "ts"  '(my/org-open-someday :wk "Someday")
    "tl"  '(my/org-open-logbook :wk "Logbook")
    "tx"  '(my/org-pick-context :wk "Context view")
    "tc"  '(org-capture :wk "Capture task")
    "te"  '(my/gtd-set-state :wk "Set state")
    "tg"  '(org-agenda :wk "Agenda dispatcher")
    "tR"  '((lambda () (interactive) (my/org-roam-agenda-files t)) :wk "Refresh cache")
    ;; Focus timer (Vitamin-R-style slices)
    "tf"  '(org-focus-start :wk "Focus: start slice")
    "tF"  '(org-focus-dashboard :wk "Focus: dashboard")
    "tX"  '(org-focus-abort :wk "Focus: abort current")

    ;; ── SPC b — Buffer ──
    "b"   '(:ignore t :wk "buffer")
    "bb"  '(consult-buffer :wk "Switch")
    "bk"  '(kill-current-buffer :wk "Kill")
    "bs"  '(save-buffer :wk "Save")
    "bS"  '(evil-write-all :wk "Save all")
    "bn"  '(evil-buffer-new :wk "New")
    "br"  '(revert-buffer-quick :wk "Revert")
    "bl"  '(ibuffer :wk "List (ibuffer)")
    "bm"  '(bookmark-set :wk "Bookmark set")
    "bj"  '(bookmark-jump :wk "Jump to bookmark")
    "bp"  '(previous-buffer :wk "Previous")
    "bN"  '(next-buffer :wk "Next")
    "bu"  '(vundo :wk "Undo history")

    ;; ── SPC e — Eval / Execute ──
    "e"   '(:ignore t :wk "eval")
    "ee"  '(eval-last-sexp :wk "Last sexp")
    "eb"  '(eval-buffer :wk "Buffer")
    "er"  '(eval-region :wk "Region")
    "ed"  '(eval-defun :wk "Defun")

    ;; ── SPC f — File ──
    "f"   '(:ignore t :wk "file")
    "ff"  '(find-file :wk "Find file")
    "fr"  '(consult-recent-file :wk "Recent files")
    "fs"  '(save-buffer :wk "Save")
    "fS"  '(write-file :wk "Save as")
    "fp"  '((lambda () (interactive) (find-file user-init-file)) :wk "Config file")
    "fe"  '((lambda () (interactive) (find-file user-emacs-directory)) :wk "Config dir")
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
    "gn"  '(diff-hl-next-hunk :wk "Next hunk")
    "gp"  '(diff-hl-previous-hunk :wk "Previous hunk")

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

    ;; ── SPC a — AI ──
    "a"   '(:ignore t :wk "AI")
    "aa"  '(gptel-send :wk "Send to LLM")
    "am"  '(gptel-menu :wk "Menu (models/params)")
    "ac"  '(gptel :wk "Chat buffer")
    "ar"  '(gptel-rewrite :wk "Rewrite region")
    "a+"  '(gptel-add :wk "Add context")
    "as"  '(my/ai-summarize :wk "Summarize")
    "at"  '(my/ai-suggest-tags :wk "Suggest tags")
    "al"  '(my/ai-translate :wk "Translate")
    "ak"  '(my/ai-connections :wk "Find connections")
    "ap"  '(my/ai-improve :wk "Improve writing")
    "ao"  '(my/ai-overview :wk "KB overview")
    "ai"  '(my/ai--ensure-context-files :wk "Init AI context")
    "ax"  '(my/codex-popup-toggle :wk "Codex CLI popup")
    "aO"  '(my/opencode-toggle :wk "OpenCode popup")
    "aK"  '(my/kimi-cli-popup-toggle :wk "kimi-cli popup")
    "aC"  '(claude-code-transient :wk "Claude Code")

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
    "ld"  '(my/switch-to-dashboard :wk "Dashboard")

    ;; ── SPC n — Notes / org-roam ──
    "n"   '(:ignore t :wk "notes")
    "nn"  '(org-roam-node-find :wk "Find note")
    "nc"  '(org-roam-capture :wk "New note")
    "ns"  '(deft :wk "Search all notes")
    "n/"  '(my/org-roam-rg-search :wk "Search note text")
    "ni"  '(org-roam-node-insert :wk "Insert link")
    "nb"  '(org-roam-buffer-toggle :wk "Backlinks")
    "ng"  '(org-roam-ui-mode :wk "Graph view")
    "no"  '(my/node-action :wk "Node actions")
    "na"  '(org-roam-alias-add :wk "Add alias")
    "nr"  '(org-roam-ref-add :wk "Add ref")
    "nL"  '(org-cliplink :wk "Paste link (cliplink)")
    "nI"  '(org-download-clipboard :wk "Paste image")
    "nl"  '(consult-org-roam-forward-links :wk "Forward links")
    "nB"  '(consult-org-roam-backlinks :wk "Backlinks (consult)")
    "n?"  '(consult-org-roam-search :wk "Search (consult)")

    ;; SPC n v — Views / dashboards (read-only query windows)
    "nv"  '(:ignore t :wk "views")
    "nvv" '(my/dashboard-find :wk "Open dashboard")
    "nvw" '(my/dash-review :wk "Weekly review")
    "nvi" '(my/dash-index :wk "Dashboard index")

    ;; ── SPC # — SuperTag (structured data + schema/meta) ──
    ;; Mirrors the org local-leader `, #` mnemonic: # means supertag.
    "#"   '(:ignore t :wk "supertag")
    "##"  '(my/supertag-quick-action :wk "Quick action")
    "#a"  '(org-supertag-tag-add-tag :wk "Add tag")
    "#e"  '(org-supertag-node-edit-field :wk "Edit field")
    "#x"  '(org-supertag-tag-remove :wk "Remove tag")
    "#l"  '(org-supertag-node-list-fields :wk "List fields")
    "#j"  '(org-supertag-node-follow-ref :wk "Jump linked")
    "#k"  '(supertag-view-kanban :wk "Kanban")
    "#s"  '(supertag-search :wk "Search DB")
    "#S"  '(supertag-sync-status :wk "Sync status")
    "#r"  '(supertag-sync-check-now :wk "Sync now")
    "#R"  '(supertag-sync-full-initialize :wk "Full rebuild")
    ;; Schema / templates / dashboards (extensibility hub)
    "#t"  '(my/edit-supertag-schema :wk "Edit tag schema")
    "#T"  '(my/reload-supertag-schema :wk "Reload tag schema")
    "#c"  '(my/edit-capture-templates :wk "Edit capture templates")
    "#C"  '(my/reload-capture-templates :wk "Reload capture templates")
    "#d"  '(my/dashboard-create :wk "Create new dashboard")

    ;; SPC n d — Dailies
    "nd"  '(:ignore t :wk "dailies")
    "ndd" '(my/daily-workspace-open :wk "Daily workspace")
    "nda" '(my/daily-new-node :wk "Append node")
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
    "oD"  '(my/switch-to-dashboard :wk "Dashboard")
    "oa"  '(org-agenda :wk "Agenda")
    "of"  '(dirvish :wk "Dirvish (file manager)")
    "oy"  '(my/yazi-popup-toggle :wk "Yazi popup")
    "oY"  '(my/yazi-open :wk "Yazi full window")
    "od"  '(dired-jump :wk "Dired (jump to file)")
    "oj"  '(dired :wk "Dired (pick directory)")
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
    "sn"  '(my/org-roam-rg-search :wk "Notes text")
    "si"  '(consult-imenu :wk "Imenu")
    "so"  '(consult-outline :wk "Outline")
    "sb"  '(consult-bookmark :wk "Bookmark")
    "sf"  '(consult-find :wk "File by name")
    "sr"  '(query-replace :wk "Replace")
    "sR"  '(query-replace-regexp :wk "Replace regexp")

    ;; ── SPC u — UI / toggles ──
    "u"   '(:ignore t :wk "UI/toggles")
    "ut"  '(consult-theme :wk "Theme")
    "ul"  '(display-line-numbers-mode :wk "Line numbers")
    "uw"  '(visual-line-mode :wk "Word wrap")
    "uf"  '(toggle-frame-fullscreen :wk "Fullscreen")
    "ui"  '(org-modern-mode :wk "Org-modern")
    "un"  '(org-num-mode :wk "Heading numbers")
    "um"  '(mixed-pitch-mode :wk "Mixed pitch")
    "ub"  '(menu-bar-mode :wk "Menu bar")
    "us"  '(org-sticky-header-mode :wk "Sticky header")
    "uT"  '(global-tab-line-mode :wk "Buffer tabs")
    "ua"  '(auto-save-visited-mode :wk "Auto-save")
    "uh"  '(dired-omit-mode :wk "Hide dot-files / AGENTS.md (dired)")

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

    ;; ── SPC q — Quit / session ──
    "q"   '(:ignore t :wk "quit")
    "qq"  '(save-buffers-kill-emacs :wk "Quit Emacs")
    "qu"  '(my/package-update-all :wk "Update packages")
    "qr"  '(my/package-snapshot-rollback :wk "Rollback packages"))

  ;; Reapply the tested contract last so it describes effective bindings.
  (my/keymap-apply-general-contract))

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
