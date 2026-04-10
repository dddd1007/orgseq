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
  ;; `C-s' inside a dired buffer searches ONLY filenames, not the full
  ;; line including permissions/size/date.  Dramatically fewer false
  ;; matches when hunting for a file by substring.
  (dired-isearch-filenames t)
  ;; Emacs 29+: enable drag-and-drop of dired files out to other apps
  ;; (file manager, browser, email client, chat apps).  Works on
  ;; Windows when the Emacs build supports `x-begin-drag'.
  (dired-mouse-drag-files t)
  ;; Hide the "total used in directory" header line at the top of
  ;; every listing.  Pure cosmetic noise for normal use; can be
  ;; restored by setting this back to 'first or 'separate.
  (dired-free-space nil)
  ;; Hide symlink targets when details are hidden so file names align.
  (dired-hide-details-hide-symlink-targets t)
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
  (add-hook 'dired-mode-hook #'dired-omit-mode)

  ;; ---- dired-hide-details-mode: show filenames only ----
  ;;
  ;; By default dired shows the full `ls -l' output per line:
  ;;   -rw-r--r-- 1 user user 4.0K Apr 10 20:00 foo.org
  ;; That's useful in a full-window dired when you need permissions
  ;; or sizes, but in a narrow sidebar it crowds the filename off
  ;; the right edge.  Enabling hide-details globally collapses each
  ;; line to just the filename (plus nerd-icon via dirvish attribute).
  ;; Toggle back on in any individual buffer by pressing `(' -- the
  ;; standard dired key for this mode.
  (add-hook 'dired-mode-hook #'dired-hide-details-mode))

;; ---- dired-narrow: live-filter a directory by substring ----
;;
;; Press `/' in any dired/dirvish buffer to enter filter mode.  As you
;; type, the listing shrinks to just the lines matching your input.
;; RET to confirm (narrowed view stays), C-g to cancel (original view
;; restored).  Much faster than isearch for "find the file I want"
;; when a directory has dozens of entries.  From the `dired-hacks'
;; collection, widely recommended on r/emacs and Emacs StackExchange.
(use-package dired-narrow
  :after dired
  :bind (:map dired-mode-map
              ("/" . dired-narrow-fuzzy)))

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

  :config
  ;; Global takeover: every dired invocation opens dirvish.
  ;; Set this here (not :custom) because it's a minor-mode toggle.
  (dirvish-override-dired-mode 1)

  ;; Explicitly load the subtree extension so `dirvish-subtree-toggle'
  ;; is available immediately -- without this, the function is only
  ;; autoloaded lazily when you press TAB in a dirvish buffer, and
  ;; our mouse-1 click handler (which calls it directly) would fall
  ;; through to a default action and open a new buffer instead of
  ;; expanding the clicked directory in place.
  (require 'dirvish-subtree)

  ;; `dirvish-side-follow-mode' (when enabled) auto-reveals the
  ;; current file's directory in the sidebar every time you switch
  ;; buffers -- similar to VSCode's file-tree auto-reveal.  We turn
  ;; it OFF by default because PKM workflows involve constantly
  ;; switching between Roam / Outputs / Practice and you usually
  ;; care more about "where I want to go" than "where I currently
  ;; am", so an auto-jumping sidebar becomes distracting.  Toggle
  ;; it on per-session with `SPC l T' (or `M-x dirvish-side-follow-mode').
  (dirvish-side-follow-mode -1)

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
         ;;
         ;; We bind BOTH mouse-1 and mouse-2 here on purpose.  Dired
         ;; declares `(define-key map [follow-link] 'mouse-face)',
         ;; which tells Emacs "a mouse-1 click on text carrying the
         ;; `mouse-face' property should be dispatched as a mouse-2
         ;; click instead".  Dirvish attaches `mouse-face' to the
         ;; filename portion of each line (for hover highlight).
         ;; Without the mouse-2 binding below, clicks that land
         ;; specifically on the filename text would get rewritten
         ;; to mouse-2 and hit `dired-mouse-find-file-other-window',
         ;; which opens the directory as a separate dired buffer --
         ;; confusing.  Binding both buttons to the same handler
         ;; means the in-place-expand behavior wins regardless of
         ;; exactly where on the line the click lands.
         ([mouse-1]        . my/dirvish-mouse-click)
         ([mouse-2]        . my/dirvish-mouse-click)
         ([double-mouse-1] . my/dirvish-mouse-click)
         ([double-mouse-2] . my/dirvish-mouse-click)
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
     ;; `dirvish-subtree' is explicitly required in :config above so
     ;; this function is guaranteed to be loaded by the time a click
     ;; can reach this branch; we call it directly without an
     ;; fboundp guard on purpose, so a missing-function error would
     ;; surface loudly instead of silently falling through to some
     ;; other behavior that looks like a bug.
     ((file-directory-p file)
      (dirvish-subtree-toggle))
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

(defun my/dirvish-side-reveal ()
  "Navigate the dirvish-side sidebar to show the current buffer's file.
This is the one-shot alternative to `dirvish-side-follow-mode':
call it when you want the sidebar to jump to where you are RIGHT
NOW, without committing to auto-reveal-every-switch behavior.

If the current buffer has no file, fall back to the buffer's
`default-directory'.  If dirvish-side is not currently open, this
will open it first."
  (interactive)
  (require 'dirvish-side)
  (let ((target (or (and buffer-file-name
                         (file-name-directory buffer-file-name))
                    default-directory)))
    (dirvish-side target)))

(provide 'init-dired)
;;; init-dired.el ends here
