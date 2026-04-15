;;; init-ui.el --- Fonts, themes, modeline -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

;; ---- CJK mixed typesetting ----
(defvar my/latin-font-candidates
  '("Cascadia Code" "JetBrains Mono" "SF Mono" "Monaco" "Menlo"
    "Fira Code" "Source Code Pro" "DejaVu Sans Mono" "Noto Sans Mono"
    "Ubuntu Mono")
  "Latin monospace font candidates in preference order.")

(defvar my/cjk-font-candidates
  '("Sarasa Fixed SC" "Sarasa Mono SC" "LXGW WenKai Mono"
    "Noto Sans CJK SC" "Noto Sans Mono CJK SC"
    "PingFang SC" "Hiragino Sans GB" "Microsoft YaHei UI" "SimHei")
  "CJK font candidates in preference order.")

(defun my/first-available-font (candidates)
  "Return the first installed font from CANDIDATES."
  (cl-find-if (lambda (f) (member f (font-family-list))) candidates))

(defun my/setup-fonts ()
  "Configure mixed CJK/Latin fonts."
  (when (display-graphic-p)
    (when-let ((latin (my/first-available-font my/latin-font-candidates)))
      (set-face-attribute 'default nil
                          :family latin
                          :height 130))

    (when-let ((cjk (my/first-available-font my/cjk-font-candidates)))
      (dolist (charset '(kana han symbol cjk-misc bopomofo))
        (set-fontset-font t charset (font-spec :family cjk)))
      (setq face-font-rescale-alist
            (cond
             ((string= cjk "Sarasa Fixed SC")     `((,cjk . 1.0)))
             ((string= cjk "LXGW WenKai Mono")    `((,cjk . 1.1)))
             (t                                    `((,cjk . 1.05)))))
      (message "org-seq: CJK font → %s" cjk))))

;; Handle daemon mode
(defun my/setup-fonts-for-frame (frame)
  "Setup fonts for newly created FRAME."
  (with-selected-frame frame (my/setup-fonts)))

(if (daemonp)
    (add-hook 'after-make-frame-functions #'my/setup-fonts-for-frame)
  (my/setup-fonts))

;; ---- mixed-pitch: variable-width prose + monospace code ----
;; Prose (headings, body text) uses a proportional/variable-width font,
;; while code blocks, tables, and inline code stay monospace.  This makes
;; org buffers feel like a document editor rather than source code.
;; CJK variable-pitch candidates are probed the same way as the monospace
;; font — first available wins.
(defvar my/latin-vp-font-candidates
  '("Segoe UI" "Calibri" "Noto Sans" "Helvetica Neue" "SF Pro Text"
    "Cantarell" "DejaVu Sans" "Ubuntu" "Liberation Sans")
  "Latin variable-pitch font candidates in preference order.")

(defvar my/cjk-vp-font-candidates
  '("Sarasa Gothic SC" "Sarasa UI SC" "Noto Sans CJK SC"
    "PingFang SC" "Hiragino Sans GB" "Microsoft YaHei UI" "SimHei")
  "CJK variable-pitch font candidates in preference order.")

(defun my/setup-variable-pitch-fonts ()
  "Configure `variable-pitch' face for prose and CJK variable-pitch."
  (when (display-graphic-p)
    (when-let ((vp (my/first-available-font my/latin-vp-font-candidates)))
      (set-face-attribute 'variable-pitch nil
                          :family vp
                          :height 1.0))
    ;; Map CJK charsets to a proportional CJK font for variable-pitch
    (when-let ((cjk-vp (my/first-available-font my/cjk-vp-font-candidates)))
      (dolist (charset '(kana han cjk-misc bopomofo))
        (set-fontset-font t charset (font-spec :family cjk-vp) nil 'append))
      (message "org-seq: CJK variable-pitch → %s" cjk-vp))))

(defun my/setup-variable-pitch-fonts-for-frame (frame)
  "Setup variable-pitch fonts for newly created FRAME."
  (with-selected-frame frame (my/setup-variable-pitch-fonts)))

(if (daemonp)
    (add-hook 'after-make-frame-functions #'my/setup-variable-pitch-fonts-for-frame)
  (my/setup-variable-pitch-fonts))

(use-package mixed-pitch
  :hook (org-mode . mixed-pitch-mode)
  :config
  ;; Ensure table separators and checkboxes stay monospace
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-table)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-checkbox))

;; ---- Mouse and scrolling ----
;; Doom-style principle: mouse support is a first-class fallback, while the
;; keyboard-centric editing flow keeps its point and window semantics.
(setq mouse-yank-at-point t
      mouse-wheel-follow-mouse t
      mouse-wheel-progressive-speed nil
      mouse-wheel-scroll-amount '(5 ((shift) . hscroll))
      mouse-1-click-follows-link 450
      scroll-conservatively 101
      scroll-preserve-screen-position t
      hscroll-margin 2
      hscroll-step 1
      auto-window-vscroll nil)

(when (boundp 'fast-but-imprecise-scrolling)
  (set 'fast-but-imprecise-scrolling t))

(when (fboundp 'pixel-scroll-precision-mode)
  (when (boundp 'pixel-scroll-precision-use-momentum)
    (set 'pixel-scroll-precision-use-momentum t))
  (pixel-scroll-precision-mode 1))

(when (fboundp 'context-menu-mode)
  (context-menu-mode 1))

(defun my/enable-terminal-mouse (&optional frame)
  "Enable mouse reporting for terminal FRAMEs."
  (when (not (display-graphic-p frame))
    (xterm-mouse-mode 1)))

(my/enable-terminal-mouse)
(add-hook 'after-make-frame-functions #'my/enable-terminal-mouse)

(defun my/mouse--try-command (command)
  "Run COMMAND interactively and return non-nil when it succeeds."
  (when (fboundp command)
    (condition-case nil
        (progn
          (call-interactively command)
          t)
      (error nil))))

(defun my/mouse-go-back (event)
  "Navigate backward from mouse EVENT."
  (interactive "e")
  (ignore event)
  (or (my/mouse--try-command 'xref-go-back)
      (my/mouse--try-command 'evil-jump-backward)
      (previous-buffer)))

(defun my/mouse-go-forward (event)
  "Navigate forward from mouse EVENT."
  (interactive "e")
  (ignore event)
  (or (my/mouse--try-command 'xref-go-forward)
      (my/mouse--try-command 'evil-jump-forward)
      (next-buffer)))

(global-set-key [mouse-8] #'my/mouse-go-back)
(global-set-key [mouse-9] #'my/mouse-go-forward)

;; ---- modus-themes: accessible, WCAG AAA ----
(use-package modus-themes
  :demand t
  :config
  (setq modus-themes-mixed-fonts t
        modus-themes-italic-constructs t
        modus-themes-bold-constructs t
        modus-themes-prompts '(bold)
        modus-themes-completions '((t . (bold)))
        modus-themes-org-blocks 'tinted-background
        modus-themes-headings '((1 . (variable-pitch overline bold 1.4))
                                (2 . (overline bold 1.2))
                                (3 . (bold 1.1))
                                (t . (semibold 1.0))))
  (load-theme 'modus-operandi-tinted t))

;; ---- spacious-padding: frame/window breathing room ----
;; By Protesilaos (modus-themes author): adds internal border and divider
;; width so content doesn't crowd the frame edges.  The divider widths
;; double as a wide mouse-drag target for resizing splits.
(use-package spacious-padding
  :demand t
  :config
  (setq spacious-padding-widths
        '( :internal-border-width 24
           :header-line-width 4
           :mode-line-width 6
           :tab-width 4
           :right-divider-width 8
           :bottom-divider-width 8
           :scroll-bar-width 0
           :left-fringe-width 20
           :right-fringe-width 20))
  (spacious-padding-mode 1))

;; Paint the full divider strip with the theme's `mode-line-inactive'
;; background — the canonical subtle gray every theme tunes for
;; structural delimiters.  Combined with a narrow 4px divider width,
;; this reads as a delicate hairline that harmonizes with the theme
;; rather than a prominent painted band.  Re-applies on theme switch
;; so dividers track the active palette.
(defun my/ui-refresh-window-dividers (&rest _)
  "Paint window dividers with a subtle theme-adaptive delimiter color."
  (let ((line (face-attribute 'mode-line-inactive :background nil t)))
    (when (and line (not (eq line 'unspecified)))
      (dolist (face '(window-divider
                      window-divider-first-pixel
                      window-divider-last-pixel))
        (set-face-attribute face nil :foreground line)))))

;; Ensure window dividers are visible and painted with the theme color.
;; In daemon mode the initial load has no GUI frame, so re-apply for
;; every newly created frame.
(window-divider-mode 1)

(defun my/ui-refresh-window-dividers-for-frame (frame)
  "Apply `my/ui-refresh-window-dividers' to FRAME."
  (with-selected-frame frame (my/ui-refresh-window-dividers)))

(if (daemonp)
    (add-hook 'after-make-frame-functions #'my/ui-refresh-window-dividers-for-frame)
  (my/ui-refresh-window-dividers))

(add-hook 'enable-theme-functions #'my/ui-refresh-window-dividers)

;; ---- ef-themes: colorful & elegant light/dark themes (lazy, for switching) ----
(use-package ef-themes
  :defer t)

;; ---- doom-themes: modern IDE-style themes (lazy, for switching) ----
(use-package doom-themes
  :defer t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

;; ---- nerd-icons ----
;; Windows: after install, run M-x nerd-icons-install-fonts
;; then manually install the downloaded .ttf files (right-click -> Install)
(use-package nerd-icons
  :demand t)

;; ---- doom-modeline ----
(use-package doom-modeline
  :demand t
  :init (doom-modeline-mode 1)
  :custom
  (doom-modeline-height 22)
  (doom-modeline-bar-width 4)
  (doom-modeline-icon t)
  (doom-modeline-major-mode-icon nil)
  (doom-modeline-minor-modes nil)
  (doom-modeline-buffer-encoding nil)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-project-detection 'project))

;; ---- valign: pixel-perfect table alignment with variable-width fonts ----
;; NOTE: valign hooks into jit-lock for pixel alignment.  The layout helpers
;; below reuse this for centered prose buffers that adjust margins.
;;
;; WORKAROUND: org-indent-mode adds `line-prefix' and `wrap-prefix'
;; text properties that confuse valign's pixel-width calculations,
;; causing tables to silently fail alignment.  We selectively strip
;; these properties from table rows, then re-run valign on the table.
;; This preserves org-indent's indentation for non-table content.
;; See: https://github.com/casouri/valign/issues/31
(use-package valign
  :hook (org-mode . valign-mode)
  :config
  (defun my/valign-refresh-window (&optional window)
    "Re-align valign tables after margin changes in WINDOW."
    (let ((window (or window (selected-window))))
      (with-current-buffer (window-buffer window)
        (when (bound-and-true-p valign-mode)
          (valign-reset-buffer)))))

  ;; --- org-indent workaround: strip line-prefix from table rows ---
  ;; org-indent-mode adds line-prefix/wrap-prefix to every line, which
  ;; breaks valign's pixel-width calculation.  We strip these on table
  ;; rows and schedule a single idle re-align to avoid re-entrancy
  ;; (advice → valign → jit-lock → advice → ...).

  (defvar my/valign--dirty-tables nil
    "List of (buffer . position) pairs marking tables needing re-alignment.")

  (defvar my/valign--idle-timer nil
    "Idle timer for deferred table re-alignment.")

  (defvar-local my/valign--stripping nil
    "Non-nil while `my/org-unindent-tables-for-valign' is running.
Prevents re-entrancy from jit-lock re-triggering org-indent-refresh.")

  (defun my/valign--flush-dirty-tables ()
    "Re-align all tables that had their line-prefix stripped.
Called from an idle timer to batch work outside the jit-lock cycle."
    (setq my/valign--idle-timer nil)
    (let ((work my/valign--dirty-tables))
      (setq my/valign--dirty-tables nil)
      (dolist (entry work)
        (let ((buf (car entry))
              (pos (cdr entry)))
          (when (buffer-live-p buf)
            (with-current-buffer buf
              (when (bound-and-true-p valign-mode)
                (save-excursion
                  (goto-char pos)
                  (when (org-at-table-p)
                    (condition-case nil
                        (valign-table)
                      (error nil)))))))))))

  (defun my/org-unindent-tables-for-valign (beg end &optional _)
    "Remove `line-prefix'/`wrap-prefix' from org table rows in BEG..END.
Only strips properties; actual re-alignment is deferred to an idle
timer via `my/valign--flush-dirty-tables' to avoid jit-lock loops."
    (when (and (derived-mode-p 'org-mode)
               (not my/valign--stripping))
      (let ((my/valign--stripping t))
        (save-excursion
          (goto-char beg)
          (beginning-of-line)
          (while (< (point) end)
            (if (org-at-table-p)
                (let ((tbeg (point)))
                  (while (and (not (eobp)) (org-at-table-p))
                    (with-silent-modifications
                      (remove-text-properties
                       (line-beginning-position)
                       (line-beginning-position 2)
                       '(line-prefix nil wrap-prefix nil)))
                    (forward-line 1))
                  ;; Record table start for deferred re-alignment
                  (push (cons (current-buffer) tbeg)
                        my/valign--dirty-tables))
              (forward-line 1)))))
      ;; Schedule a single idle callback for all dirty tables
      (when (and my/valign--dirty-tables
                 (not my/valign--idle-timer))
        (setq my/valign--idle-timer
              (run-with-idle-timer 0.2 nil
                                   #'my/valign--flush-dirty-tables)))))

  ;; After org-indent refreshes a region, strip table-row prefixes
  (advice-add 'org-indent-refresh-maybe :after
              #'my/org-unindent-tables-for-valign)

  ;; After initial full-buffer indentation, fix all tables
  (add-hook 'org-indent-post-buffer-init-functions
            (lambda (_buf)
              (when (derived-mode-p 'org-mode)
                (my/org-unindent-tables-for-valign (point-min) (point-max))))))

;; ---- Centered writing helpers ----
;; Shared infrastructure for prose buffers that flatten side areas and compute
;; adaptive widths from the current window.

(defvar-local my/centered-face-remaps nil
  "Face remap cookies for flattening side areas in prose buffers.")

(defun my/centered-compute-width (min-w max-w scale &optional window)
  "Compute adaptive body width for WINDOW given MIN-W, MAX-W, and SCALE."
  (let* ((window (or window (selected-window)))
         (ww (window-total-width window)))
    (max min-w (min max-w (floor (* ww scale))))))

(defun my/centered-apply-face-remaps ()
  "Flatten side-area faces to match the main text background."
  (unless my/centered-face-remaps
    (setq-local my/centered-face-remaps
                (list (face-remap-add-relative 'left-margin 'default)
                      (face-remap-add-relative 'right-margin 'default)
                      (face-remap-add-relative 'fringe 'default)))))

(defun my/centered-remove-face-remaps ()
  "Remove face remaps added by `my/centered-apply-face-remaps'."
  (when my/centered-face-remaps
    (dolist (cookie my/centered-face-remaps)
      (face-remap-remove-relative cookie))
    (setq-local my/centered-face-remaps nil)))

;; ---- Breathing room: line spacing ----
;; Daniel Mendler (org-modern author) recommends 0.1–0.4 for readability.
;; 0.2 adds subtle vertical space without feeling wasteful.
(setq-default line-spacing 0.2)

;; ---- General UI settings ----
(setq-default cursor-type 'bar)
(blink-cursor-mode -1)
(global-display-line-numbers-mode 1)
(column-number-mode 1)

;; Disable line numbers in prose/terminal modes
(defun my/disable-line-numbers ()
  "Disable `display-line-numbers-mode'."
  (display-line-numbers-mode 0))

(dolist (mode '(org-mode-hook
               dashboard-mode-hook
               dired-mode-hook
               dirvish-mode-hook
               dirvish-directory-view-mode-hook
               term-mode-hook
               shell-mode-hook
               eshell-mode-hook))
  (add-hook mode #'my/disable-line-numbers))

(provide 'init-ui)
;;; init-ui.el ends here
