;;; init-dired.el --- Dired + dirvish modern file manager -*- lexical-binding: t; -*-

;; Requires: init-org (my/note-home, my/roam-dir)
;; Requires: init-ui  (nerd-icons for file-type icons)
(defvar my/note-home)  ; forward-declare from init-org
(defvar my/roam-dir)   ; forward-declare from init-org

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
  ;; Long listing, human-readable sizes, dirs first, show dotfiles
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
          ls-lisp-use-insert-directory-program nil)))

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
  ;; Main-view attributes: icons + file-size + collapse arrows + VC state
  ;; `git-msg' shows the last commit message for each file (nice for notes
  ;; versioned in git).
  (dirvish-attributes '(nerd-icons file-size collapse subtree-state vc-state git-msg))
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
        `(("h" "~/"                                     "Home")
          ("n" ,my/note-home                             "NoteHQ")
          ("r" ,my/roam-dir                              "Roam")
          ("c" ,(expand-file-name "capture/" my/roam-dir) "Captures")
          ("d" ,(expand-file-name "daily/"   my/roam-dir) "Daily")
          ("b" ,(expand-file-name "dashboards/" my/roam-dir) "Dashboards")
          ("o" ,(expand-file-name "Outputs/"  my/note-home) "Outputs")
          ("p" ,(expand-file-name "Practice/" my/note-home) "Practice")
          ("l" ,(expand-file-name "Library/"  my/note-home) "Library")
          ("a" ,(expand-file-name "Archives/" my/note-home) "Archives")
          ("e" ,user-emacs-directory                     "Emacs config")))

  :bind (:map dirvish-mode-map
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
;; Section 3: Sidebar helpers
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; `init-workspace.el' consumes these to build the 3-column layout.

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
