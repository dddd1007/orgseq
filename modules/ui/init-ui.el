;;; init-ui.el --- Fonts, themes, modeline -*- lexical-binding: t; -*-

;; Requires: init-packages (Git package bootstrap and source metadata)

(require 'cl-lib)
(require 'subr-x)

(declare-function my/vc-package-ensure "init-packages" (package))
(declare-function my/vc-package-install-command "init-packages" (package))
(declare-function my/vc-package-install-error "init-packages" (package))

(defvar modus-operandi-palette-overrides)
(defvar modus-vivendi-palette-overrides)
(defvar modus-themes-to-toggle)
(defvar spacious-padding-subtle-frame-lines)
(defvar visual-fill-column-width)
(defvar visual-fill-column-center-text)
(defvar visual-fill-column-fringes-outside-margins)
(defvar tab-line-exclude-modes)
(defvar modusregel-buffer-modified-str)
(defvar modusregel-buffer-name-expr)
(defvar modusregel-buffer-position-expr)
(defvar modusregel-buffer-read-only-str)
(defvar modusregel-column-number-str)
(defvar modusregel-eglot-expr)
(defvar modusregel-flymake-expr)
(defvar modusregel-format)
(defvar modusregel-leading-str)
(defvar modusregel-line-number-str)
(defvar modusregel-major-mode-expr)
(defvar modusregel-remote-expr)
(defvar modusregel-spacer-str)
(defvar modusregel-vc-expr)

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
    (when-let* ((latin (my/first-available-font my/latin-font-candidates)))
      (set-face-attribute 'default nil
                          :family latin
                          :height 130)
      ;; `fixed-pitch' defaults to the generic "Monospace" family, which
      ;; Windows resolves to Courier New.  mixed-pitch renders Org code,
      ;; tables, and inline code with it, so keep it on the editor font.
      (set-face-attribute 'fixed-pitch nil
                          :family latin
                          :height 1.0))

    (when-let* ((cjk (my/first-available-font my/cjk-font-candidates)))
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
;; Inter comes first: it is the UI/prose face of both Tana and Fibery, and
;; its tall x-height keeps small labels (tags, badges, sidebar rows)
;; readable at 0.8-0.9 relative height.  Segoe UI is the Windows fallback.
(defvar my/latin-vp-font-candidates
  '("Inter" "Inter Variable" "Segoe UI" "Calibri" "Noto Sans"
    "Helvetica Neue" "SF Pro Text" "Cantarell" "DejaVu Sans" "Ubuntu"
    "Liberation Sans")
  "Latin variable-pitch font candidates in preference order.")

(defvar my/cjk-vp-font-candidates
  '("Sarasa Gothic SC" "Sarasa UI SC" "Noto Sans CJK SC"
    "PingFang SC" "Hiragino Sans GB" "Microsoft YaHei UI" "SimHei")
  "CJK variable-pitch font candidates in preference order.")

(defun my/setup-variable-pitch-fonts ()
  "Configure `variable-pitch' face for prose and CJK variable-pitch."
  (when (display-graphic-p)
    (when-let* ((vp (my/first-available-font my/latin-vp-font-candidates)))
      (set-face-attribute 'variable-pitch nil
                          :family vp
                          :height 1.0))
    ;; Map CJK charsets to a proportional CJK font for variable-pitch
    (when-let* ((cjk-vp (my/first-available-font my/cjk-vp-font-candidates)))
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

;; Only enable for the current frame if it's a TTY; skip in daemon mode
;; because `after-make-frame-functions' will handle new frames.
(when (and (not (daemonp)) (not (display-graphic-p)))
  (my/enable-terminal-mouse))

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

;; ═══════════════════════════════════════════════════════════════════════════
;; Design system: tokens, palette, theme
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Visual direction (after Tana and Fibery):
;;   - Neutral white/near-black canvas; navigation surfaces (sidebars,
;;     dashboards) sit on a slightly darker gray so content and chrome
;;     separate without borders.
;;   - One accent hue (indigo-violet) marks interaction: links, cursor,
;;     selection, today, the active row.  Other hues carry meaning only
;;     (task state, dates); headings use the body ink, not a rainbow.
;;   - Task states are pastel workflow badges; tags are pills.
;;   - Hairline structure: 1px dividers and a 1px mode-line rule instead of
;;     painted bands.
;;
;; Human-factors constraints applied to every value below:
;;   - Body and label text >= 4.5:1 contrast (WCAG 2.2 AA; body ink is
;;     > 15:1), non-text UI marks (fold chevrons, line numbers) >= 3:1.
;;   - Color is never the only cue: badges carry their keyword text, the
;;     Daily sidebar pairs color with a filled/hollow dot, GTD project
;;     health uses a glyph plus a legend.
;;   - Prose is set to a fixed measure (see "Prose column" below) instead
;;     of following the window width.
;;
;; The palette is applied as Modus palette overrides, so every package
;; Modus supports inherits it, and `SPC u t' can still load any other
;; theme.  org-seq's own faces carry light/dark specs and keep working
;; under other themes.

(defface my/ui-accent
  '((((background dark)) :foreground "#a99bff")
    (t :foreground "#5546d1"))
  "Accent color for interactive emphasis: today, current item, links."
  :group 'org-seq)

(defface my/ui-surface
  '((((background dark)) :background "#222227" :extend t)
    (t :background "#f6f6f7" :extend t))
  "Background of navigation surfaces such as sidebars and dashboards."
  :group 'org-seq)

(defface my/ui-section-title
  '((t :inherit shadow :weight semibold :height 0.85))
  "Small muted label above a group of rows (sidebar or dashboard)."
  :group 'org-seq)

(defface my/ui-hint
  '((t :inherit shadow :height 0.85))
  "Secondary text: key hints, counts, legends, dates."
  :group 'org-seq)

(defface my/ui-key
  '((t :inherit my/ui-hint :weight semibold))
  "Key name inside a hint line."
  :group 'org-seq)

(defface my/ui-line-active
  '((((background dark)) :foreground "#4a4a54")
    (t :foreground "#c9c9d1"))
  "Color of the 1px rule above the selected window's mode line."
  :group 'org-seq)

(defface my/ui-line-inactive
  '((((background dark)) :foreground "#303036")
    (t :foreground "#e6e6eb"))
  "Color of hairlines: window dividers and inactive mode-line rules."
  :group 'org-seq)

(defface my/ui-breadcrumb
  '((t :inherit shadow :height 0.9 :weight regular))
  "Outline breadcrumb shown in the Org header line."
  :group 'org-seq)

;; ---- Task-state badges (Fibery workflow style) ----
;; Each state has its own hue so states are told apart at a glance, but the
;; badge text stays readable on its own (all pairs >= 4.5:1).
(defface my/org-status-project
  '((((background dark)) :foreground "#c7bdff" :background "#2f2a55")
    (t :foreground "#4c3cc0" :background "#ece9fd"))
  "Badge for PROJECT headings."
  :group 'org-seq)

(defface my/org-status-todo
  '((((background dark)) :foreground "#cfcfd6" :background "#2c2c33")
    (t :foreground "#4b4b56" :background "#eeeef2"))
  "Badge for TODO headings."
  :group 'org-seq)

(defface my/org-status-next
  '((((background dark)) :foreground "#a9c6ff" :background "#1d3056")
    (t :foreground "#1c4fb0" :background "#e2ecff"))
  "Badge for NEXT headings."
  :group 'org-seq)

(defface my/org-status-in-progress
  '((((background dark)) :foreground "#ffcf7a" :background "#3d2e10")
    (t :foreground "#8a4b00" :background "#fff0d4"))
  "Badge for IN-PROGRESS headings."
  :group 'org-seq)

(defface my/org-status-waiting
  '((((background dark)) :foreground "#ffb08f" :background "#45261a")
    (t :foreground "#a33a14" :background "#ffe6da"))
  "Badge for WAITING headings."
  :group 'org-seq)

(defface my/org-status-someday
  '((((background dark)) :foreground "#c2b8dc" :background "#2e2a3b")
    (t :foreground "#66588a" :background "#f0edf7"))
  "Badge for SOMEDAY headings."
  :group 'org-seq)

(defface my/org-status-done
  '((((background dark)) :foreground "#9edcb1" :background "#1c3a27")
    (t :foreground "#23703c" :background "#e2f3e7"))
  "Badge for DONE headings."
  :group 'org-seq)

(defface my/org-status-cancelled
  '((((background dark)) :foreground "#9a9aa5" :background "#2a2a30"
     :strike-through t)
    (t :foreground "#64646f" :background "#f0f0f3" :strike-through t))
  "Badge for CANCELLED headings."
  :group 'org-seq)

;; ---- Tag pills (Tana tag style) ----
(defface my/org-tag
  '((((background dark)) :foreground "#c3baff" :background "#2c2850")
    (t :foreground "#5546d1" :background "#efedfd"))
  "Pill for ordinary Org tags."
  :group 'org-seq)

(defface my/org-tag-context
  '((((background dark)) :foreground "#a8cdee" :background "#1f2f3d")
    (t :foreground "#33618a" :background "#e8f0f7"))
  "Pill for GTD context tags such as @work."
  :group 'org-seq)

;; ---- Modus palette overrides ----
(defconst my/ui-palette-light
  '(;; Canvas and ink
    (bg-main "#ffffff") (bg-dim "#f6f6f7")
    (bg-active "#e4e4ea") (bg-inactive "#efeff2")
    (fg-main "#1d1d20") (fg-dim "#62626d")
    (border "#e2e2e7")
    ;; Interaction: one accent hue
    (cursor "#5546d1")
    (bg-hl-line "#eeebfd")
    (bg-region "#dcd7fb") (fg-region unspecified)
    (bg-completion "#e9e6fc")
    (bg-hover "#e9e6fc") (bg-hover-secondary "#f1f1f4")
    (bg-paren-match "#dcd7fb")
    (keybind "#5546d1") (fg-prompt "#5546d1")
    (fg-link "#5546d1") (underline-link "#c9c2f6")
    (fg-link-visited "#7446b8") (underline-link-visited "#d9c8f0")
    (fg-link-symbolic "#33618a") (underline-link-symbolic "#c5d6e6")
    ;; Chrome: flat, hairline-separated
    (fringe unspecified)
    (bg-mode-line-active bg-main) (fg-mode-line-active fg-main)
    (border-mode-line-active "#c9c9d1")
    (bg-mode-line-inactive bg-main) (fg-mode-line-inactive fg-dim)
    (border-mode-line-inactive "#e6e6eb")
    (bg-tab-bar bg-dim) (bg-tab-current bg-main) (bg-tab-other bg-dim)
    (fg-line-number-inactive "#8b8b96") (fg-line-number-active fg-main)
    (bg-line-number-inactive unspecified) (bg-line-number-active unspecified)
    ;; Headings share the body ink; size and weight carry the hierarchy
    (fg-heading-0 fg-main) (fg-heading-1 fg-main) (fg-heading-2 fg-main)
    (fg-heading-3 fg-main) (fg-heading-4 fg-main) (fg-heading-5 fg-main)
    (fg-heading-6 fg-main) (fg-heading-7 fg-main) (fg-heading-8 fg-main)
    ;; Prose
    (prose-metadata fg-dim) (prose-metadata-value fg-dim)
    (prose-table fg-main) (prose-tag "#5546d1")
    ;; Finished work recedes; only the DONE badge itself stays green.
    (prose-todo "#1c4fb0") (prose-done fg-dim)
    (bg-prose-block-contents "#f7f7f9") (bg-prose-block-delimiter "#f7f7f9")
    (fg-prose-block-delimiter "#8b8b96")
    (fg-prose-code "#b0294f") (bg-prose-code "#f2f2f5")
    (fg-prose-verbatim "#b0294f") (bg-prose-verbatim "#f2f2f5")
    (fg-prose-macro "#5546d1")
    ;; Dates: only deadlines and schedules get a hue
    (date-common fg-dim) (date-event fg-dim)
    (date-deadline "#b42318") (date-scheduled "#8a5a00")
    (date-weekday fg-dim) (date-weekend fg-dim) (date-now fg-main))
  "org-seq light palette, applied as `modus-operandi-palette-overrides'.")

(defconst my/ui-palette-dark
  '((bg-main "#1b1b1f") (bg-dim "#222227")
    (bg-active "#3a3a42") (bg-inactive "#2a2a30")
    (fg-main "#e6e6ea") (fg-dim "#a2a2ad")
    (border "#34343b")
    (cursor "#a99bff")
    (bg-hl-line "#2a2840")
    (bg-region "#3b3570") (fg-region unspecified)
    (bg-completion "#2f2b52")
    (bg-hover "#2f2b52") (bg-hover-secondary "#2a2a30")
    (bg-paren-match "#3b3570")
    (keybind "#a99bff") (fg-prompt "#a99bff")
    (fg-link "#a99bff") (underline-link "#4a4380")
    (fg-link-visited "#c9a6f2") (underline-link-visited "#584a7a")
    (fg-link-symbolic "#a8cdee") (underline-link-symbolic "#3b5266")
    (fringe unspecified)
    (bg-mode-line-active bg-main) (fg-mode-line-active fg-main)
    (border-mode-line-active "#4a4a54")
    (bg-mode-line-inactive bg-main) (fg-mode-line-inactive fg-dim)
    (border-mode-line-inactive "#303036")
    (bg-tab-bar bg-dim) (bg-tab-current bg-main) (bg-tab-other bg-dim)
    (fg-line-number-inactive "#77777f") (fg-line-number-active fg-main)
    (bg-line-number-inactive unspecified) (bg-line-number-active unspecified)
    (fg-heading-0 fg-main) (fg-heading-1 fg-main) (fg-heading-2 fg-main)
    (fg-heading-3 fg-main) (fg-heading-4 fg-main) (fg-heading-5 fg-main)
    (fg-heading-6 fg-main) (fg-heading-7 fg-main) (fg-heading-8 fg-main)
    (prose-metadata fg-dim) (prose-metadata-value fg-dim)
    (prose-table fg-main) (prose-tag "#a99bff")
    (prose-todo "#a9c6ff") (prose-done fg-dim)
    (bg-prose-block-contents "#222227") (bg-prose-block-delimiter "#222227")
    (fg-prose-block-delimiter "#77777f")
    (fg-prose-code "#ff8fab") (bg-prose-code "#27272c")
    (fg-prose-verbatim "#ff8fab") (bg-prose-verbatim "#27272c")
    (fg-prose-macro "#a99bff")
    (date-common fg-dim) (date-event fg-dim)
    (date-deadline "#ff8a80") (date-scheduled "#e8c06a")
    (date-weekday fg-dim) (date-weekend fg-dim) (date-now fg-main))
  "org-seq dark palette, applied as `modus-vivendi-palette-overrides'.")

(defcustom my/ui-use-org-seq-palette t
  "When non-nil, apply the org-seq palette to modus-operandi/vivendi.
Set to nil to get the stock Modus colors back."
  :type 'boolean
  :group 'org-seq)

(defcustom my/ui-theme-light 'modus-operandi
  "Light theme loaded at startup and by `my/ui-toggle-dark'."
  :type 'symbol
  :group 'org-seq)

(defcustom my/ui-theme-dark 'modus-vivendi
  "Dark theme loaded by `my/ui-toggle-dark'."
  :type 'symbol
  :group 'org-seq)

(defcustom my/ui-startup-variant 'light
  "Which of `my/ui-theme-light' and `my/ui-theme-dark' loads at startup."
  :type '(choice (const light) (const dark))
  :group 'org-seq)

(defun my/ui-load-theme (theme)
  "Disable enabled themes, then load THEME.
Packages that keep a private helper theme out of `custom-enabled-themes'
\(spacious-padding) are not affected."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t))

(defun my/ui-dark-p ()
  "Return non-nil when the selected frame uses a dark background."
  (eq (frame-parameter nil 'background-mode) 'dark))

(defun my/ui-toggle-dark ()
  "Switch between `my/ui-theme-light' and `my/ui-theme-dark'."
  (interactive)
  (my/ui-load-theme (if (my/ui-dark-p) my/ui-theme-light my/ui-theme-dark)))

(use-package modus-themes
  :demand t
  :config
  (when my/ui-use-org-seq-palette
    (setq modus-operandi-palette-overrides my/ui-palette-light
          modus-vivendi-palette-overrides my/ui-palette-dark))
  (setq modus-themes-mixed-fonts t
        modus-themes-italic-constructs t
        ;; Since modus-themes 5.3, prompts and completion matches are bold
        ;; whenever bold constructs are enabled.
        modus-themes-bold-constructs t
        modus-themes-to-toggle (list my/ui-theme-light my/ui-theme-dark)
        ;; Document-editor hierarchy: a large title, then modest steps.
        ;; Tana and Fibery keep section headings close to body size and
        ;; rely on weight; very large H1s push content below the fold.
        ;; Level 0 = #+title: (org-document-title face).
        modus-themes-headings '((0 . (variable-pitch bold 1.5))
                                (1 . (variable-pitch semibold 1.25))
                                (2 . (variable-pitch semibold 1.12))
                                (3 . (variable-pitch semibold 1.05))
                                (t . (variable-pitch semibold 1.0))))
  (my/ui-load-theme (if (eq my/ui-startup-variant 'dark)
                        my/ui-theme-dark
                      my/ui-theme-light)))

;; ---- spacious-padding: frame/window breathing room ----
;; By Protesilaos (modus-themes author): adds internal border and divider
;; width so content doesn't crowd the frame edges.  The divider widths
;; double as a wide mouse-drag target for resizing splits.
;; `spacious-padding-subtle-frame-lines' replaces the painted mode-line
;; band with a 1px rule; the active window's rule is darker so the
;; keyboard focus stays identifiable.
(use-package spacious-padding
  :demand t
  :config
  (setq spacious-padding-widths
        '( :internal-border-width 12
           :header-line-width 4
           :mode-line-width 4
           :tab-width 4
           :right-divider-width 8
           :bottom-divider-width 8
           :scroll-bar-width 0
           :left-fringe-width 8
           :right-fringe-width 8)
        spacious-padding-subtle-frame-lines
        '( :mode-line-active my/ui-line-active
           :mode-line-inactive my/ui-line-inactive))
  (spacious-padding-mode 1))

;; ---- Window dividers: 1px hairline on an 8px drag target ----
;; The divider strip stays as wide as `:right-divider-width' so it is easy
;; to grab with the mouse (Fitts's law), but only its first pixel is drawn;
;; the rest takes the canvas color.  Re-applied on every theme change,
;; after spacious-padding has set its own divider faces.
(defun my/ui-refresh-window-dividers (&rest _)
  "Draw window dividers as a 1px theme-adaptive hairline."
  (let ((line (face-foreground 'my/ui-line-inactive nil t))
        (bg (face-background 'default nil t)))
    (when (and (stringp line) (stringp bg))
      (set-face-attribute 'window-divider nil :foreground bg)
      (set-face-attribute 'window-divider-first-pixel nil :foreground line)
      (set-face-attribute 'window-divider-last-pixel nil :foreground bg))))

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

(add-hook 'enable-theme-functions #'my/ui-refresh-window-dividers 90)

;; ---- Face adjustments that themes do not cover ----
;; Each entry is (FEATURE FACE . ATTRIBUTES); ATTRIBUTES may contain the
;; keyword value `:default-bg', replaced by the current canvas color.  They
;; are re-applied after every theme load and after FEATURE loads, so they
;; survive `SPC u t'.
(defvar my/ui-face-adjustments
  '(;; The header line carries only the Org breadcrumb; let it blend into
    ;; the canvas instead of drawing an empty band at the top of a window.
    (nil header-line :background :default-bg :underline nil :overline nil
         :inherit nil)
    ;; Fold chevrons, checkboxes, progress glyphs: visible but quiet.
    (org-modern org-modern-symbol :inherit shadow)
    (org-modern org-modern-label :height 0.8 :width normal :weight medium)
    ;; Metadata recedes: property drawers and special keywords are for
    ;; machines first.
    (org org-drawer :height 0.85)
    (org org-special-keyword :height 0.85)
    (org org-property-value :height 0.85)
    (org org-document-info-keyword :height 0.85)
    ;; Startup dashboard: content first, decoration muted.
    (dashboard dashboard-text-banner :inherit shadow :weight regular)
    (dashboard dashboard-banner-logo-title :inherit shadow :weight regular)
    (dashboard dashboard-heading :inherit my/ui-section-title
               :foreground unspecified)
    (dashboard dashboard-navigator :inherit my/ui-accent :weight medium))
  "Face adjustments applied on top of the active theme.")

(defun my/ui-apply-face-adjustments (&rest _)
  "Apply `my/ui-face-adjustments' to the faces that exist now."
  (let ((bg (face-background 'default nil t)))
    (dolist (entry my/ui-face-adjustments)
      (let ((face (nth 1 entry))
            (attrs (copy-sequence (nthcdr 2 entry))))
        (when (facep face)
          (let ((tail attrs))
            (while tail
              (when (eq (cadr tail) :default-bg)
                (setcar (cdr tail) (if (stringp bg) bg 'unspecified)))
              (setq tail (cddr tail))))
          (condition-case err
              (apply #'set-face-attribute face nil attrs)
            (error
             (message "org-seq: face adjustment for %s failed: %s"
                      face (error-message-string err)))))))))

(add-hook 'enable-theme-functions #'my/ui-apply-face-adjustments 90)
(dolist (feature (delete-dups (delq nil (mapcar #'car my/ui-face-adjustments))))
  (with-eval-after-load feature (my/ui-apply-face-adjustments)))
(my/ui-apply-face-adjustments)

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
;; Any patched Nerd Font carries the same icon glyphs, so when the symbols-only
;; font is missing, icons fall back to the first installed Nerd Font instead
;; of rendering as empty boxes.
(defcustom my/nerd-icons-font-candidates
  '("Symbols Nerd Font Mono" "Symbols Nerd Font"
    "JetBrainsMono Nerd Font Mono" "FiraCode Nerd Font Mono"
    "Hack Nerd Font Mono" "CaskaydiaCove Nerd Font Mono")
  "Nerd Font families used for icons, in preference order."
  :type '(repeat string)
  :group 'org-seq)

(defvar nerd-icons-font-family)
(declare-function nerd-icons-set-font "nerd-icons" (&optional font-family frame))

(defun my/nerd-icons-pick-font ()
  "Point `nerd-icons-font-family' at the first installed Nerd Font.
Also map the icon code-point ranges in the fontset, so raw glyphs inserted
outside the nerd-icons functions render with the same font."
  (when (display-graphic-p)
    (when-let* ((family (my/first-available-font my/nerd-icons-font-candidates)))
      (setq nerd-icons-font-family family)
      (nerd-icons-set-font family))))

(use-package nerd-icons
  :demand t
  :config
  (if (daemonp)
      (add-hook 'server-after-make-frame-hook #'my/nerd-icons-pick-font)
    (my/nerd-icons-pick-font)))

;; ---- modusregel mode-line ----
;; Codeberg-only package; source metadata lives in init-packages.
(my/vc-package-ensure 'modusregel)

(use-package modusregel
  :if (locate-library "modusregel")
  :demand t
  :init
  ;; No constant brand label: text that is identical in every window
  ;; carries no information and competes with the buffer name.
  (setq modusregel-leading-str "  "
        modusregel-spacer-str " "
        modusregel-buffer-modified-str '(:eval (when (buffer-modified-p) " *"))
        modusregel-buffer-read-only-str '(:eval (when buffer-read-only " RO")))
  :config
  ;; Keep org-seq source ASCII-only while preserving the useful indicators.
  (setq modusregel-remote-expr
        '(:eval (when (file-remote-p default-directory)
                  (list modusregel-spacer-str "remote" modusregel-spacer-str)))
        modusregel-eglot-expr
        '(:eval (when (bound-and-true-p eglot--managed-mode)
                  (propertize " LSP" 'help-echo "Eglot LSP active")))
        modusregel-format
        (list
         modusregel-leading-str
         modusregel-remote-expr
         modusregel-buffer-name-expr
         modusregel-buffer-modified-str
         modusregel-buffer-read-only-str
         modusregel-spacer-str
         modusregel-line-number-str
         modusregel-column-number-str
         modusregel-spacer-str
         modusregel-buffer-position-expr
         modusregel-spacer-str
         modusregel-vc-expr
         modusregel-major-mode-expr
         modusregel-eglot-expr
         modusregel-spacer-str
         modusregel-flymake-expr
         modusregel-spacer-str
         'mode-line-process
         'mode-line-misc-info))
  (setq-default mode-line-format modusregel-format))

(unless (locate-library "modusregel")
  (run-with-idle-timer
   3 nil
   (lambda ()
     (message "WARNING org-seq: modusregel not found. %sRun %s"
              (if (my/vc-package-install-error 'modusregel)
                  (format "Last install error: %s. "
                          (my/vc-package-install-error 'modusregel))
                "")
              (my/vc-package-install-command 'modusregel)))))

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
(defun my/valign-refresh-window (&optional window)
  "Re-align valign tables after margin changes in WINDOW."
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (when (bound-and-true-p valign-mode)
        (valign-reset-buffer)))))

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

(declare-function valign-reset-buffer "valign" ())
(declare-function valign-table "valign" ())

(use-package valign
  :hook (org-mode . valign-mode)
  :config

  ;; --- org-indent workaround: strip line-prefix from table rows ---
  ;; org-indent-mode adds line-prefix/wrap-prefix to every line, which
  ;; breaks valign's pixel-width calculation.  We strip these on table
  ;; rows and schedule a single idle re-align to avoid re-entrancy
  ;; (advice → valign → jit-lock → advice → ...).


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
;; Daniel Mendler (org-modern author) recommends 0.1-0.4 for readability.
;; The fonts in use already carry generous built-in leading (JetBrains
;; Mono 1.32, Noto Sans CJK about 1.45), so the low end is enough.
(setq-default line-spacing 0.1)

;; ---- General UI settings ----
(setq-default cursor-type 'bar)
(blink-cursor-mode -1)
(global-display-line-numbers-mode 1)
(column-number-mode 1)

;; ---- diff-hl: VC change indicators in the fringe/margin (VS Code gutter) ----
;; Shows added/changed/deleted hunks beside each line.  flydiff-mode mirrors
;; unsaved edits in real time; magit refresh hooks keep the gutter in sync
;; after a commit.
;; NOTE(daemon): margin-vs-fringe is decided once at load time from the
;; current `display-graphic-p'.  A daemon started on a TTY then asked for a
;; GUI frame stays on the margin path; this is an acceptable simplification
;; and avoids per-frame fringe bookkeeping.
;; `:if' keeps the whole form (including the global-diff-hl-mode hook) a
;; no-op on a clean checkout without diff-hl installed, so batch validation
;; does not trip on a void `global-diff-hl-mode'.  The mode is enabled on
;; `my/first-file-hook' (init.el), just before the first file is visited.
;; diff-hl is optional; every call below is already guarded by
;; `:if (locate-library "diff-hl")'.
(declare-function diff-hl-flydiff-mode "diff-hl-flydiff" (&optional arg))
(declare-function diff-hl-magit-post-refresh "diff-hl" ())
(declare-function diff-hl-margin-mode "diff-hl-margin" (&optional arg))
(declare-function global-diff-hl-mode "diff-hl" (&optional arg))

(use-package diff-hl
  :if (locate-library "diff-hl")
  :hook (my/first-file . global-diff-hl-mode)
  :config
  (diff-hl-flydiff-mode 1)
  (unless (display-graphic-p)
    (diff-hl-margin-mode 1))
  ;; diff-hl 1.11 made the pre-refresh hook a no-op; only post-refresh remains.
  (with-eval-after-load 'magit
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))

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

;; ---- tab-line: clickable buffer tabs (built-in) ----
;; Mirror of Sublime/VS Code/Zed/Helix editor tabs.  Each tab is a buffer
;; in the current window's previous/next ring; the close button (x) kills
;; the buffer, the tab itself switches to it.  The new-tab button is off
;; because its semantics ("new buffer") are ambiguous in this workflow.
;;
;; Tool/side/utility buffers are excluded so the top of the Daily sidebar,
;; Treemacs, the outline, terminal popups, and ephemeral messages never
;; grow meaningless tabs.  This list mirrors
;; `my/workspace--utility-buffer-p' in init-workspace.el on purpose, but is
;; duplicated here (not required across modules) because init-ui loads
;; before init-workspace -- see the module load order in init.el.
(defvar my/ui-tab-line-excluded-names
  '("*Daily Notes*"
    "*Ilist*"
    "*GTD*"
    "*dashboard*"
    "*NoteHQ-terminal*"
    "*NoteHQ-codex*"
    "*NoteHQ-opencode*"
    "*NoteHQ-kimi*"
    "*org-seq-yazi*"
    "*Messages*"
    "*Warnings*")
  "Buffer names that never appear in the tab-line.
Kept in sync with `my/workspace--utility-buffer-p' and the special-mode
exclusion below; update both when a new tool buffer is introduced.")

(defun my/ui-tab-line--excluded-buffer-p (buffer)
  "Return non-nil when BUFFER should be hidden from the tab-line."
  (let ((name (buffer-name buffer)))
    (or (string-prefix-p "*Treemacs" name)
        (member name my/ui-tab-line-excluded-names)
        (with-current-buffer buffer
          (derived-mode-p 'special-mode 'dired-mode 'dashboard-mode)))))

;; `tab-line' is built in; requiring it makes its variables and the default
;; tab function visible to the byte compiler.
(require 'tab-line)

(defun my/ui-tab-line-filtered-tabs ()
  "Return this window's tab-line tabs with utility buffers removed.
Wraps `tab-line-tabs-fixed-window-buffers', the default value of
`tab-line-tabs-function', so the global tab set stays the buffer ring
Emacs already maintains and its stable ordering is preserved; we only
hide members."
  (seq-remove #'my/ui-tab-line--excluded-buffer-p
              (tab-line-tabs-fixed-window-buffers)))

(setq tab-line-new-button-show nil
      tab-line-tabs-function #'my/ui-tab-line-filtered-tabs)

(global-tab-line-mode 1)

;; ═══════════════════════════════════════════════════════════════════════════
;; Layout: prose column and navigation surfaces
;; ═══════════════════════════════════════════════════════════════════════════

;; ---- Prose column: fixed reading measure for Org ----
;; Reading speed and comprehension drop when lines get too long; the usual
;; guidance is 50-75 Latin characters and roughly 30-40 Chinese characters
;; per line.  Tana and Fibery both cap the content column regardless of
;; window width.  Width is in columns of the default (monospace) font:
;; 72 columns hold about 80 Latin characters of the proportional prose
;; font and about 40 Chinese characters.  Windows narrower than the
;; measure simply use their full width.
(defcustom my/prose-column-width 72
  "Width in columns of the centered text column in prose buffers."
  :type 'integer
  :group 'org-seq)

(defcustom my/prose-column-auto-modes '(org-mode)
  "Major modes that get `my/prose-column-mode' automatically.
Markdown has its own adaptive layout in init-markdown."
  :type '(repeat symbol)
  :group 'org-seq)

(defcustom my/prose-line-spacing 0.16
  "Extra line spacing in prose buffers, as a fraction of line height.
Code keeps the global `line-spacing'; running text needs more leading,
especially with CJK glyphs, which fill the whole em box."
  :type 'number
  :group 'org-seq)

(declare-function visual-fill-column-mode "visual-fill-column" (&optional arg))

(use-package visual-fill-column
  :commands (visual-fill-column-mode visual-fill-column-adjust))

(define-minor-mode my/prose-column-mode
  "Center the text of the current buffer in a fixed-width column."
  :lighter nil
  (if my/prose-column-mode
      (progn
        (setq-local visual-fill-column-width my/prose-column-width
                    visual-fill-column-center-text t
                    visual-fill-column-fringes-outside-margins nil)
        (my/centered-apply-face-remaps)
        (visual-fill-column-mode 1))
    (visual-fill-column-mode -1)
    (my/centered-remove-face-remaps))
  (my/valign-refresh-window))

(defun my/prose-buffer-setup ()
  "Apply the prose column and leading to buffers in prose modes."
  (setq-local line-spacing my/prose-line-spacing)
  (when (and (apply #'derived-mode-p my/prose-column-auto-modes)
             (locate-library "visual-fill-column"))
    (my/prose-column-mode 1)))

(add-hook 'org-mode-hook #'my/prose-buffer-setup)

;; ---- Navigation surfaces ----
;; Menu-like buffers (sidebars, dashboards) get a full-row highlight for the
;; current item, taller rows (larger click targets), and no line numbers or
;; tab-line: they are menus, not documents.  Side panels additionally get
;; the gray surface background so they read as chrome next to the white
;; page; org-seq's own menus use the proportional UI font.  The hooks are
;; registered here so the owning modules need no UI code.
(defcustom my/ui-surface-modes
  '(my/daily-sidebar-mode my/gtd-dashboard-mode my/node-view-mode
    treemacs-mode imenu-list-major-mode)
  "Major modes rendered as menus (row highlight, no line numbers)."
  :type '(repeat symbol)
  :group 'org-seq)

(defcustom my/ui-sidebar-modes
  '(my/daily-sidebar-mode treemacs-mode imenu-list-major-mode)
  "Subset of `my/ui-surface-modes' drawn on the sidebar background."
  :type '(repeat symbol)
  :group 'org-seq)

(defcustom my/ui-proportional-surface-modes
  '(my/daily-sidebar-mode my/gtd-dashboard-mode)
  "Subset of `my/ui-surface-modes' rendered in the proportional UI font.
Treemacs and imenu-list indent with spaces, so they stay monospace."
  :type '(repeat symbol)
  :group 'org-seq)

(defcustom my/ui-surface-line-spacing 0.22
  "Extra line spacing in navigation surfaces."
  :type 'number
  :group 'org-seq)

(defvar-local my/ui--surface-remaps nil
  "Face remap cookies installed by `my/ui-surface-setup'.")

(defun my/ui-surface-setup ()
  "Render the current buffer as a navigation surface."
  (unless my/ui--surface-remaps
    (setq my/ui--surface-remaps
          (append
           (when (memq major-mode my/ui-sidebar-modes)
             (list (face-remap-add-relative 'default 'my/ui-surface)
                   (face-remap-add-relative 'fringe 'my/ui-surface)))
           (when (memq major-mode my/ui-proportional-surface-modes)
             (list (face-remap-add-relative 'default 'variable-pitch))))))
  (setq-local line-spacing my/ui-surface-line-spacing)
  (display-line-numbers-mode 0)
  (when (bound-and-true-p tab-line-mode)
    (tab-line-mode -1))
  (hl-line-mode 1))

(dolist (mode my/ui-surface-modes)
  (add-to-list 'tab-line-exclude-modes mode)
  (add-hook (intern (format "%s-hook" mode)) #'my/ui-surface-setup))

;; List-like buffers that are not surfaces still benefit from a row cursor.
(add-hook 'org-agenda-mode-hook #'hl-line-mode)

;; ---- Theme commands ----
;; `SPC u d' toggles light/dark, `SPC u c' toggles the prose column; both
;; are bound in init-evil.

(provide 'init-ui)
;;; init-ui.el ends here
