;;; init-mouse.el --- First-class mouse support -*- lexical-binding: t; -*-
;;
;; Mouse input is a first-class citizen in org-seq, on equal footing with
;; the keyboard: anything the leader keys can do in the daily PKM/GTD
;; workflow is reachable by mouse as well.  This module owns:
;;
;;   1. Context menus: mode-aware right-click menus for org notes, the
;;      agenda, the Daily sidebar, and the GTD dashboard (context-menu-mode
;;      itself is enabled in init-ui).
;;   2. org-mouse: clickable TODO keywords, checkboxes, timestamps, and
;;      list bullets inside org buffers.
;;   3. The menu bar with a NoteHQ menu of the core workflow commands.
;;   4. Drag and drop: files dropped into org buffers become links or
;;      attachments, dired can drag files out to other programs, and
;;      selected text can be dragged between buffers and programs.
;;   5. Single-click navigation in the agenda (Daily sidebar rows and GTD
;;      dashboard rows are already single-click buttons).

;; Requires: init-org (my/roam-dir)
;; Requires: init-gtd (GTD commands surfaced in the org context menu)
;; Requires: init-gtd-dashboard (dashboard commands in its context menu)
;; Requires: init-daily (Daily sidebar commands in its context menu)

(require 'easymenu)

(defvar my/roam-dir)  ; forward-declare from init-org
(defvar dired-mouse-drag-files)
(defvar org-agenda-mode-map)
(defvar org-yank-dnd-method)
(defvar org-yank-image-save-method)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Mode-aware context menus (right click)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; context-menu-mode is enabled in init-ui.  Each function below appends a
;; mode-specific section to the menu.  Menu commands close over CLICK and
;; move point to the clicked position first, so acting on the row or
;; heading under the pointer never depends on where point happened to be.

(defun my/mouse--command-at-click (command click)
  "Return an interactive lambda running COMMAND at CLICK's position."
  (lambda ()
    (interactive)
    (when click
      (ignore-errors (mouse-set-point click)))
    (call-interactively command)))

(defun my/mouse--add-submenu (menu symbol label entries click)
  "Append to MENU a submenu SYMBOL labeled LABEL holding ENTRIES.
Each entry is (ID LABEL COMMAND); COMMAND runs at CLICK's position."
  (let ((map (make-sparse-keymap label)))
    (dolist (entry entries)
      (pcase-let ((`(,id ,item-label ,command) entry))
        (define-key-after map (vector id)
          (list 'menu-item item-label
                (my/mouse--command-at-click command click)))))
    (define-key-after menu (vector symbol) (list 'menu-item label map))))

(defun my/mouse-org-context-menu (menu click)
  "Add org note and GTD task entries to context MENU for CLICK."
  (when (derived-mode-p 'org-mode)
    (define-key-after menu [my/mouse-org-separator] menu-bar-separator)
    (my/mouse--add-submenu
     menu 'my/mouse-org-task "Task"
     '((state    "Set State..."        my/gtd-set-state)
       (complete "Complete (DONE)"     my/gtd-complete)
       (cancel   "Cancel Task"         my/gtd-cancel)
       (schedule "Schedule..."         org-schedule)
       (deadline "Deadline..."         org-deadline)
       (tags     "Set Tags..."         org-set-tags-command)
       (effort   "Set Effort..."       org-set-effort)
       (refile   "Refile..."           org-refile)
       (archive  "Archive Subtree"     org-archive-subtree))
     click)
    (my/mouse--add-submenu
     menu 'my/mouse-org-note "Note"
     '((link       "Insert Note Link..."  org-roam-node-insert)
       (backlinks  "Toggle Backlinks"     org-roam-buffer-toggle)
       (transclude "Add Transclusion"     org-transclusion-add)
       (daily-node "Append Daily Node"    my/daily-new-node))
     click)
    (my/mouse--add-submenu
     menu 'my/mouse-org-supertag "Supertag"
     '((quick  "Quick Action..."  my/supertag-quick-action)
       (add    "Add Tag..."       org-supertag-tag-add-tag)
       (edit   "Edit Field..."    org-supertag-node-edit-field)
       (remove "Remove Tag..."    org-supertag-tag-remove))
     click))
  menu)

(defun my/mouse-agenda-context-menu (menu click)
  "Add agenda entry actions to context MENU for CLICK."
  (when (derived-mode-p 'org-agenda-mode)
    (define-key-after menu [my/mouse-agenda-separator] menu-bar-separator)
    (my/mouse--add-submenu
     menu 'my/mouse-agenda "Agenda Entry"
     '((goto     "Open Entry"        org-agenda-goto)
       (todo     "Set TODO State..." org-agenda-todo)
       (schedule "Schedule..."       org-agenda-schedule)
       (deadline "Deadline..."       org-agenda-deadline)
       (priority "Set Priority..."   org-agenda-priority))
     click))
  menu)

(defun my/mouse-daily-sidebar-context-menu (menu click)
  "Add Daily sidebar actions to context MENU for CLICK."
  (when (derived-mode-p 'my/daily-sidebar-mode)
    (define-key-after menu [my/mouse-daily-separator] menu-bar-separator)
    (my/mouse--add-submenu
     menu 'my/mouse-daily "Daily Notes"
     '((open    "Open This Date"     my/daily-sidebar-open-at-point)
       (today   "Today's Workspace"  my/daily-workspace-open)
       (choose  "Choose Date..."     my/daily-workspace-choose-date)
       (refresh "Refresh"            my/daily-sidebar-refresh)
       (close   "Close Sidebar"      my/daily-sidebar-close))
     click))
  menu)

(defun my/mouse-gtd-dashboard-context-menu (menu click)
  "Add GTD dashboard actions to context MENU for CLICK."
  (when (derived-mode-p 'my/gtd-dashboard-mode)
    (define-key-after menu [my/mouse-gtd-separator] menu-bar-separator)
    (my/mouse--add-submenu
     menu 'my/mouse-gtd "GTD Dashboard"
     '((open    "Open This View"  my/gtd-dashboard-activate)
       (refresh "Refresh Counts"  my/org-dashboard--open))
     click))
  menu)

(dolist (function '(my/mouse-org-context-menu
                    my/mouse-agenda-context-menu
                    my/mouse-daily-sidebar-context-menu
                    my/mouse-gtd-dashboard-context-menu))
  (add-hook 'context-menu-functions function))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: org-mouse -- clickable org elements
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; org-mouse (ships with Org) makes TODO keywords, checkboxes, timestamps,
;; priorities, and list bullets directly clickable.  Its own mouse-3 menu
;; is shadowed by context-menu-mode, which is intentional: the org context
;; menu above is GTD-aware and uses org-seq's state commands.

(with-eval-after-load 'org
  (require 'org-mouse nil t))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Menu bar with a NoteHQ workflow menu
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; early-init.el requests one menu-bar line per frame; this section makes
;; the mode authoritative and adds the core workflow commands as a menu so
;; the daily loop never requires remembering a key.  Toggle: SPC u b.

(unless noninteractive
  (menu-bar-mode 1))

(easy-menu-define my/mouse-notehq-menu global-map
  "NoteHQ workflow menu."
  '("NoteHQ"
    ["Today's Daily" my/daily-workspace-open t]
    ["New Note..." org-roam-capture t]
    ["Find Note..." org-roam-node-find t]
    ["Search Notes..." my/org-roam-rg-search t]
    "---"
    ["GTD Dashboard" my/org-dashboard t]
    ["Today's Tasks" my/org-open-today t]
    ["Weekly Review" my/org-open-weekly-review t]
    ["Capture Task..." org-capture t]
    "---"
    ["AI Chat" gptel t]
    ["Terminal Popup" my/terminal-popup-toggle t]
    "---"
    ["Update Packages" my/package-update-all t]
    ["Rollback Packages..." my/package-snapshot-rollback t]))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Drag and drop
;; ═══════════════════════════════════════════════════════════════════════════

;; Dragging selected text moves/copies it, including across programs.
(setq mouse-drag-and-drop-region t
      mouse-drag-and-drop-region-cross-program t)

;; Show where a drop will land and keep scrolling usable during a drag.
(setq dnd-indicate-insertion-point t
      dnd-scroll-margin 2)

;; Dired can drag files out to other programs (Emacs 29+).
(setq dired-mouse-drag-files t)

;; Files dropped into org buffers ask: attach, insert link, or insert
;; contents (Org 9.7+).  Dropped/pasted images are saved under the Roam
;; assets directory so notes stay portable.
(with-eval-after-load 'org
  (setq org-yank-dnd-method 'ask)
  (setq org-yank-image-save-method
        (expand-file-name "assets/" my/roam-dir)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Single-click navigation
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Daily sidebar rows and GTD dashboard rows are already single-click
;; buttons.  Bring the agenda to parity: mouse-1 on an entry opens it in
;; the other window (the default only binds mouse-2).

(with-eval-after-load 'org-agenda
  (define-key org-agenda-mode-map [mouse-1] #'org-agenda-goto-mouse))

(provide 'init-mouse)
;;; init-mouse.el ends here
