;;; init-dired.el --- Dired + dirvish modern file manager -*- lexical-binding: t; -*-

;; Requires: init-org       (my/note-home, my/roam-dir)
;; Requires: init-supertag  (my/outputs-dir, my/practice-dir,
;;                           my/library-dir, my/archives-dir)
;; Requires: init-ui        (nerd-icons for file-type icons)
(defvar my/note-home)      ; forward-declare from init-org
(defvar my/roam-dir)       ; forward-declare from init-org
(defvar my/outputs-dir)    ; forward-declare from init-supertag
(defvar my/practice-dir)   ; forward-declare from init-supertag
(defvar my/library-dir)    ; forward-declare from init-supertag
(defvar my/archives-dir)   ; forward-declare from init-supertag

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Built-in dired — base configuration
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Dired is the canonical file manager in Emacs.  We configure the built-in
;; package with modern defaults, then layer `dirvish' on top for a polished
;; UI.  dirvish uses dired underneath, so every dired keybinding still works.

(use-package dired
  :ensure nil
  :commands (dired dired-jump)
  :custom
  ;; Long listing, human-readable sizes, dirs first, sort by name (the
  ;; default with -l is name, -v would switch to version-sort; we keep
  ;; name-sort so the sidebar listing is alphabetical).
  (dired-listing-switches "-alh --group-directories-first")
  ;; Smart default target: if two dired windows are open, use the other as target
  (dired-dwim-target t)
  ;; Reuse the current dired buffer instead of piling up new ones
  (dired-kill-when-opening-new-dired-buffer t)
  ;; Recursive copy/delete with minimal prompting
  (dired-recursive-copies 'always)
  (dired-recursive-deletes 'top)
  ;; Refresh buffer on file system changes
  (dired-auto-revert-buffer t)
  :config
  ;; Enable `a' (dired-find-alternate-file) — reuses the current buffer
  (put 'dired-find-alternate-file 'disabled nil)

  ;; Windows: GNU ls may not be available; fall back silently.
  ;; When `ls-lisp' is used, --group-directories-first is ignored but harmless.
  (when (eq system-type 'windows-nt)
    (setq ls-lisp-dirs-first t
          ls-lisp-use-insert-directory-program nil))

  ;; ---- dired-omit-mode: hide dot-files and CLAUDE.md by default ----
  ;;
  ;; `dired-x' provides `dired-omit-mode' as a minor mode that filters
  ;; the displayed file list.  We enable it globally via `dired-mode-hook'
  ;; so both regular dired buffers and dirvish-side start hidden.
  ;;
  ;; The regex hides:
  ;;   - Anything starting with a dot (`.git', `.DS_Store', `.orgseq', ...)
  ;;     This also catches the `.' and `..' entries automatically.
  ;;   - Exactly `CLAUDE.md' files (the Claude Code project-instruction file
  ;;     that lives in many repos and rarely needs to be visible to the user).
  ;;
  ;; Toggle visibility at any time with `M-x dired-omit-mode' or `SPC t h'.
  (require 'dired-x)
  (setq dired-omit-files
        (concat "\\`[.]"                  ; dot-prefixed files/dirs
                "\\|\\`CLAUDE\\.md\\'"))  ; and CLAUDE.md exactly
  (setq dired-omit-verbose nil)
  (add-hook 'dired-mode-hook #'dired-omit-mode))

;; ---- diredfl: colorize dired lines by file type ----
(use-package diredfl
  :hook (dired-mode . diredfl-mode))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: dirvish — modern file manager UI over dired
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; dirvish replaces treemacs as the primary file navigation UI.  It:
;;   - is based on dired (keybindings, semantics, wdired all still work)
;;   - adds nerd-icons, git status, file size, preview pane
;;   - provides `dirvish-side' mode for use as a sidebar
;;   - has an active maintainer and fast release cycle
;;
;; `dirvish-override-dired-mode' makes every dired call (C-x d, dired-jump,
;; project-dired, etc.) open the dirvish UI transparently.  Keybindings are
;; unchanged; only the visuals upgrade.
;;
;; For previewing binary files (images, PDFs), dirvish can use external tools
;; like `ffmpegthumbnailer', `mediainfo', `imagemagick'.  These are optional
;; and only matter if you browse media files — PKM text files preview with
;; the built-in elisp peeker.

(use-package dirvish
  :demand t
  :after (dired nerd-icons)
  :custom
  ;; Sidebar width (treemacs was 24; dirvish-side feels better a bit wider)
  (dirvish-side-width 28)
  ;; Main-view attributes: icons + file-size + collapse arrows + VC state.
  ;;
  ;; Note: `git-msg' (which shows the last commit message for each file)
  ;; was removed from this list because it spawns a `git log' subprocess
  ;; per directory and fails with "Fetch dir data failed: (end-of-file)"
  ;; on Windows when the subprocess output cannot be parsed, or when the
  ;; directory is not a git repository.  If you want commit messages back,
  ;; re-add `git-msg' but expect the error to reappear on non-repo
  ;; directories.
  (dirvish-attributes '(nerd-icons file-size collapse subtree-state vc-state))
  ;; Sidebar view is more compact: only icons + collapse + VC state
  (dirvish-side-attributes '(nerd-icons collapse vc-state))
  ;; Hide the built-in mode-line in dirvish buffers; use the header line instead
  (dirvish-use-mode-line nil)
  (dirvish-use-header-line t)
  ;; Auto-follow the sidebar selection to the main window
  (dirvish-side-follow-mode t)

  :config
  ;; Global takeover: every dired invocation opens dirvish.
  ;; Set this here (not :custom) because it's a minor-mode toggle.
  (dirvish-override-dired-mode 1)

  ;; Peek mode: when the minibuffer shows a file candidate (e.g. consult-find),
  ;; show its contents in a preview window automatically.
  (dirvish-peek-mode 1)

  ;; Quick-access entries: SPC n a (or `a' inside dirvish) shows a menu
  ;; rooted at these paths.  Wire them to the NoteHQ layout so jumping
  ;; into captures/dailies is one keystroke.
  (setq dirvish-quick-access-entries
        `(("h" "~/"                                         "Home")
          ("n" ,my/note-home                                 "NoteHQ")
          ("r" ,my/roam-dir                                  "Roam")
          ("c" ,(expand-file-name "capture/" my/roam-dir)    "Captures")
          ("d" ,(expand-file-name "daily/"   my/roam-dir)    "Daily")
          ("b" ,(expand-file-name "dashboards/" my/roam-dir) "Dashboards")
          ("o" ,my/outputs-dir                               "Outputs")
          ("p" ,my/practice-dir                              "Practice")
          ("l" ,my/library-dir                               "Library")
          ("a" ,my/archives-dir                              "Archives")
          ("e" ,user-emacs-directory                         "Emacs config")))

  :bind (:map dirvish-mode-map
         ;; Single-click: open file in main editor window, or toggle
         ;; directory subtree in place (see `my/dirvish-mouse-click'
         ;; below for the full semantics).
         ([mouse-1]        . my/dirvish-mouse-click)
         ([double-mouse-1] . my/dirvish-mouse-click)
         ;; Dirvish's own menus (Transient-based)
         ("a"   . dirvish-quick-access)
         ("f"   . dirvish-file-info-menu)
         ("y"   . dirvish-yank-menu)
         ("N"   . dirvish-narrow)
         ("^"   . dirvish-history-last)
         ("s"   . dirvish-quicksort)
         ("v"   . dirvish-vc-menu)
         ("TAB" . dirvish-subtree-toggle)
         ("M-f" . dirvish-history-go-forward)
         ("M-b" . dirvish-history-go-backward)
         ("M-l" . dirvish-ls-switches-menu)
         ("M-m" . dirvish-mark-menu)
         ("M-t" . dirvish-layout-toggle)
         ("M-s" . dirvish-setup-menu)
         ("M-j" . dirvish-fd-jump)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Sidebar helpers + mouse click behavior
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; `init-workspace.el' consumes the side-window helpers to build the
;; 3-column layout.  The mouse-click handler makes the dirvish sidebar
;; behave like a modern file tree: single-click opens a file in the
;; main editor window, or expands a directory in place without leaving
;; the sidebar.

(defun my/dirvish-mouse-click (event)
  "Handle a mouse click inside a dirvish buffer.

Default dired binds mouse-1 to `mouse-set-point', which only moves
point without opening anything -- fine for full-window dired, but
unintuitive for a sidebar where you expect a click to do something.

This handler:

  - On a directory, calls `dirvish-subtree-toggle' so the subtree
    expands or collapses in place, keeping the sidebar as a tree
    view instead of jumping into the directory.

  - On a regular file, picks the first non-side (main editor)
    window in the current frame and opens the file there with
    `find-file'.  The sidebar itself stays put.

Called via `[mouse-1]' in `dirvish-mode-map' (see `:bind' above)."
  (interactive "e")
  ;; First, move point to the line under the click inside the dirvish window.
  (let* ((posn (event-end event))
         (window (posn-window posn))
         (point (posn-point posn)))
    (when (windowp window)
      (select-window window))
    (when (integerp point)
      (goto-char point)))
  ;; Then act on whatever file the point now refers to.
  (when-let* ((file (ignore-errors (dired-get-file-for-visit)))
              (basename (file-name-nondirectory (directory-file-name file))))
    (cond
     ;; Ignore the `.' and `..' pseudo-entries entirely.
     ((member basename '("." "..")) nil)
     ;; Directory -> toggle subtree in place (tree-view behavior).
     ((file-directory-p file)
      (if (fboundp 'dirvish-subtree-toggle)
          (dirvish-subtree-toggle)
        (dired-find-alternate-file)))
     ;; Regular file -> open in the main editor window.
     (t
      (let ((editor (seq-find
                     (lambda (w) (null (window-parameter w 'window-side)))
                     (window-list nil 'no-minibuffer))))
        (if editor
            (progn (select-window editor)
                   (find-file file))
          ;; No non-side window available (rare) — fall back to other-window.
          (find-file-other-window file)))))))

(defun my/dirvish-side-visible-p ()
  "Return the dirvish-side window if visible in the current frame, else nil."
  (cl-find-if (lambda (window)
                (eq (window-parameter window 'window-side) 'left))
              (window-list nil 'no-minibuffer)))

(defun my/dirvish-side-open-at-notehq ()
  "Open dirvish-side rooted at NoteHQ (idempotent — does nothing if visible)."
  (require 'dirvish-side)
  (make-directory my/note-home t)
  (unless (my/dirvish-side-visible-p)
    (let ((default-directory my/note-home))
      (dirvish-side my/note-home))))

(defun my/dirvish-side-toggle ()
  "Toggle dirvish-side visibility.  First open uses NoteHQ as root."
  (interactive)
  (require 'dirvish-side)
  (if-let ((win (my/dirvish-side-visible-p)))
      (delete-window win)
    (my/dirvish-side-open-at-notehq)))

(provide 'init-dired)
;;; init-dired.el ends here
