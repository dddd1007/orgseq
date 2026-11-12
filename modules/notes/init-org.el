;;; init-org.el --- Org-mode base configuration -*- lexical-binding: t; -*-

;; Requires: init-packages (Git package bootstrap and source metadata)
;; Requires: init-ui (status badge, tag pill, and breadcrumb faces)
(declare-function my/vc-package-ensure "init-packages" (package))

(defvar org-indent-indentation-per-level)
(declare-function org-set-emph-re "org" (var val))
(defvar org-agenda-prefix-format)
(defvar org-agenda-window-setup)
(defvar org-refile-targets)
(defvar org-refile-use-outline-path)
(defvar org-outline-path-complete-in-steps)
(defvar org-refile-allow-creating-parent-nodes)
(defvar org-modern-star)
(defvar org-modern-table)
(defvar org-modern-block-fringe)
(defvar org-modern-keyword)
(defvar org-modern-tag)
(defvar org-modern-label-border)
(defvar org-modern-priority)
(defvar org-modern-todo)
(defvar org-modern-block-name)
(defvar org-modern-list)
(defvar org-modern-horizontal-rule)
(defvar org-modern-progress)
(defvar org-modern-timestamp)
(defvar org-modern-checkbox)
(defvar org-modern-fold-stars)
(defvar org-modern-todo-faces)
(defvar org-modern-tag-faces)
(defvar pangu-spacing-real-insert-separator)
(declare-function evil-org-set-key-theme "evil-org")
(declare-function evil-org-agenda-set-keys "evil-org-agenda")
(declare-function general-define-key "general")

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Library paths
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; The `org-seq' group and every library path (`my/note-home', the PARA
;; layers, `my/orgseq-dir', `my/snapshot-dir', ...) are defined in the
;; kernel so the index and the command line can use them without this
;; module.
(require 'orgseq-paths)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Org base configuration
;; ═══════════════════════════════════════════════════════════════════════════

(use-package org
  :demand t
  :config
  (setq org-startup-indented t
        org-indent-indentation-per-level 2)

  ;; Visual line wrapping keeps prose buffers readable without hard-wrapping.
  ;; Without this, CJK paragraphs get hard-clipped at the window edge.
  (add-hook 'org-mode-hook #'visual-line-mode)
  ;; Wrapping only at spaces leaves a ragged right edge in Chinese text:
  ;; a run of CJK characters after a Latin word counts as one unbreakable
  ;; word.  Category-based wrapping breaks between CJK characters and
  ;; keeps closing punctuation off the start of a line (kinsoku).
  (setq word-wrap-by-category t)

  (setq org-startup-folded 'content)
  (setq org-hide-leading-stars t)
  ;; Ellipsis: "…" is the community mainstream choice — compact and unobtrusive.
  (setq org-ellipsis " …")

  (setq org-return-follows-link t
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-fold-catch-invisible-edits 'show-and-error
        org-pretty-entities t
        org-hide-emphasis-markers t)

  ;; Emphasis next to CJK text.  Org starts and ends *bold*, /italic/ and
  ;; =code= only at whitespace or ASCII punctuation, so markup written
  ;; directly against Chinese characters or CJK punctuation stayed
  ;; literal.  Allow any non-ASCII character on either side.
  (setcar org-emphasis-regexp-components
          "-[:space:]('\"{[:nonascii:]")
  (setcar (cdr org-emphasis-regexp-components)
          "-[:space:].,:!?;'\")}\\[[:nonascii:]")
  (org-set-emph-re 'org-emphasis-regexp-components
                   org-emphasis-regexp-components)

  ;; Highlight LaTeX fragments with native fontification.
  ;; NOTE: `script' renders sub/superscripts as raised/lowered glyphs,
  ;; which breaks valign's pixel-width alignment in tables.  Omitted
  ;; here; once a LaTeX distribution is installed, org-fragtog renders
  ;; full formulae as images (which valign handles correctly).
  (setq org-highlight-latex-and-related '(native entities))

  (setq org-log-done 'time
        org-log-into-drawer t)

  (setq org-todo-keywords
        '((sequence "PROJECT(P)" "TODO(t)" "NEXT(n)" "IN-PROGRESS(i)"
                    "WAITING(w@/!)" "SOMEDAY(s)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))

  (setq org-enforce-todo-dependencies t)

  (setq org-agenda-prefix-format
        '((agenda . " %i %?-12t% s")
          (todo   . " ")
          (tags   . " ")
          (search . " %i %-12:c")))
  (setq org-agenda-window-setup 'current-window)

  ;; Refile
  (setq org-refile-targets '((nil :maxlevel . 3)
                              (org-agenda-files :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

  ;; Tags
  (setq org-auto-align-tags nil
        org-tags-column 0)

  ;; Only inherit @context tags — avoids tag noise in agenda
  (setq org-use-tag-inheritance "^@")

  ;; ---- Babel: enable code execution in org blocks ----
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)
     (python . t)))
  (setq org-confirm-babel-evaluate nil))

;; ---- org-tempo: quick block insertion (<el TAB → src emacs-lisp) ----
(use-package org-tempo
  :ensure nil
  :after org
  :config
  (dolist (item '(("sh"  . "src sh")
                  ("el"  . "src emacs-lisp")
                  ("py"  . "src python")
                  ("yml" . "src yaml")
                  ("js"  . "src javascript")))
    (add-to-list 'org-structure-template-alist item)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Visual enhancement
;; ═══════════════════════════════════════════════════════════════════════════

;; Badge and pill faces (`my/org-status-*', `my/org-tag*') are design
;; tokens defined in init-ui next to the palette.
(defvar my/gtd-context-tags)

(defconst my/org-status-faces
  '(("PROJECT"     . my/org-status-project)
    ("TODO"        . my/org-status-todo)
    ("NEXT"        . my/org-status-next)
    ("IN-PROGRESS" . my/org-status-in-progress)
    ("WAITING"     . my/org-status-waiting)
    ("SOMEDAY"     . my/org-status-someday)
    ("DONE"        . my/org-status-done)
    ("CANCELLED"   . my/org-status-cancelled))
  "Workflow badge face for each org-seq TODO keyword.
Open states use distinct hues; DONE is green and CANCELLED is struck
through, so state is readable from the badge text as well as its color.")

(defun my/org-tag-faces ()
  "Return `org-modern-tag-faces': context tags blue-gray, others violet."
  (append (mapcar (lambda (tag) (cons tag 'my/org-tag-context))
                  (and (boundp 'my/gtd-context-tags) my/gtd-context-tags))
          '((t . my/org-tag))))

(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  ;; Fold chevrons instead of decorative bullets: the glyph shows whether
  ;; a heading is collapsed (Tana/Fibery outline affordance).
  (setq org-modern-star 'fold
        org-modern-fold-stars '(("▸" . "▾") ("▸" . "▾") ("▸" . "▾")
                                ("▸" . "▾") ("▸" . "▾"))
        org-modern-table nil             ; valign handles table alignment
        org-modern-block-fringe 2        ; subtle fringe marker for src blocks
        ;; Hide "#+title:" and "#+filetags:" so the title reads as a page
        ;; title with its tag pills underneath (Tana node header); other
        ;; keywords keep their name without the "#+" prefix.
        org-modern-keyword '(("title" . "") ("filetags" . "") (t . t))
        org-modern-tag t                 ; badge-style inline tags
        org-modern-label-border 0.15     ; pill padding, relative to line height
        org-modern-priority t            ; styled priority cookies
        org-modern-todo t                ; styled TODO keywords
        org-modern-todo-faces my/org-status-faces
        org-modern-tag-faces (my/org-tag-faces)
        org-modern-block-name t          ; prettify #+BEGIN_/#+END_ labels
        org-modern-list '((?- . "•")     ; dash → bullet
                          (?+ . "◦")     ; plus → open bullet
                          (?* . "‣"))    ; asterisk → triangle
        org-modern-horizontal-rule t     ; styled -----  separators
        org-modern-progress 10           ; [2/5] cookies drawn as a 10-col bar
        org-modern-timestamp t)          ; prettify <2025-04-13 Sun> stamps

  ;; Doom fix: default ☑ renders too large on many fonts — use a consistent glyph
  (setf (alist-get ?X org-modern-checkbox) #("□x" 0 2 (composition ((2)))))

  ;; Doom fix: when org-indent-mode is active, org-modern's hidden stars
  ;; make sub-headings look too sunken.  org-hide-leading-stars already
  ;; handles this, so disable org-modern's duplicate hiding.
  (add-hook 'org-modern-mode-hook
            (lambda ()
              (when (bound-and-true-p org-indent-mode)
                (setq-local org-modern-hide-stars nil)))))

;; Context tags are defined in init-gtd, which loads after this module.
(with-eval-after-load 'init-gtd
  (setq org-modern-tag-faces (my/org-tag-faces)))

;; org-modern-indent: better block/heading indentation under org-indent-mode
;; Enhances how src blocks, drawers, and other multi-line elements render
;; when org-indent-mode adds virtual indentation.
;; NOTE: requires org-indent-mode to be enabled (which we do via org-startup-indented).
(my/vc-package-ensure 'org-modern-indent)

(use-package org-modern-indent
  :if (locate-library "org-modern-indent")
  :hook (org-indent-mode . org-modern-indent-mode))

;; org-appear: reveal hidden markup (emphasis, links, entities) at cursor
;; Complements org-modern — pretty when reading, transparent when editing.
(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autolinks t)
  (org-appear-autoentities t)
  (org-appear-autosubmarkers t))

;; org-sticky-header: keep the heading breadcrumb visible at the top
;; (VS Code Sticky Scroll).  Only hooks into org-mode, so the Daily
;; sidebar (my/daily-sidebar-mode) and other non-org buffers are unaffected.
;; `:if' keeps this a no-op on a checkout without org-sticky-header installed.
;;
;; Rendered as a quiet breadcrumb (Fibery-style): one small muted line that
;; starts at the text column, instead of a copy of the heading at full
;; heading size.  The package renders the whole line in one function
;; (`org-sticky-header--fetch-stickyline'; older releases used
;; `org-sticky-header--fetch-stringified-heading'); the filter only
;; restyles its result and passes anything unexpected through unchanged.
(defvar org-sticky-header-heading-star)

(defun my/org-sticky-header-breadcrumb (header)
  "Restyle org-sticky-header output HEADER as a muted breadcrumb."
  (if (and (stringp header) (not (string-empty-p (string-trim header))))
      (concat (propertize " " 'display '(space :align-to 0))
              (propertize (string-trim (substring-no-properties header))
                          'face 'my/ui-breadcrumb))
    header))

(use-package org-sticky-header
  :if (locate-library "org-sticky-header")
  :hook (org-mode . org-sticky-header-mode)
  :custom
  (org-sticky-header-full-path 'full)
  (org-sticky-header-heading-star "")
  (org-sticky-header-prefix nil)
  (org-sticky-header-show-keyword nil)
  (org-sticky-header-show-priority nil)
  (org-sticky-header-outline-path-separator "  /  ")
  :config
  (dolist (fn '(org-sticky-header--fetch-stickyline
                org-sticky-header--fetch-stringified-heading))
    (when (fboundp fn)
      (advice-add fn :filter-return #'my/org-sticky-header-breadcrumb))))

;; org-fragtog: auto-toggle LaTeX fragment preview at cursor
;; Requires a LaTeX distribution (MiKTeX or TeX Live) with dvisvgm on PATH.
;; NOTE: table cells don't support image overlays well — fragments inside
;; tables are skipped via `org-fragtog-ignore-predicates'.
(use-package org-fragtog
  :hook (org-mode . org-fragtog-mode)
  :custom
  (org-fragtog-preview-delay 0.2)
  (org-fragtog-ignore-predicates '(org-at-table-p))
  :config
  ;; NOTE(win): MiKTeX bin may not be in PATH when Emacs inherits a stale
  ;; environment (daemon, pinned shortcut).  Ensure exec-path includes it.
  (when (eq system-type 'windows-nt)
    (let ((miktex-bin (expand-file-name
                       "AppData/Local/Programs/MiKTeX/miktex/bin/x64"
                       (getenv "USERPROFILE"))))
      (when (and (file-directory-p miktex-bin)
                 (not (member miktex-bin exec-path)))
        (add-to-list 'exec-path miktex-bin)
        (setenv "PATH" (concat miktex-bin ";" (getenv "PATH"))))))
  (setq org-preview-latex-default-process 'dvisvgm)
  ;; Scale 1.0 matches ~13pt body text; adjust if you change :height in init-ui.
  ;; Foreground 'default inherits the active theme's text color.
  ;; Background "Transparent" tells org NOT to emit \pagecolor in the LaTeX
  ;; preamble, so dvisvgm produces genuinely transparent SVGs — no background
  ;; rectangle at all.  However, Emacs' librsvg renderer still paints a solid
  ;; background behind transparent SVGs (a known limitation on Windows with
  ;; the bundled librsvg).  Org 9.8 adds asynchronous link previews, but the
  ;; standard LaTeX preview functions used here remain supported.  Therefore,
  ;; "Transparent" is still the least-bad portable option: it
  ;; avoids baking a fixed color into the SVG (which would break on theme
  ;; switch) and produces barely-visible artifacts on light themes.
  (plist-put org-format-latex-options :scale 1.0)
  (plist-put org-format-latex-options :foreground 'default)
  (plist-put org-format-latex-options :background "Transparent"))

;; org-cliplink: paste a URL from clipboard and auto-fetch its page title
;; as the link description.  Saves manual [[][title]] typing.
(use-package org-cliplink
  :after org
  :commands org-cliplink)

;; org-download: drag-and-drop (or paste) images into org buffers.
;; Images are stored as org-attach attachments alongside the note.
;; NOTE(win): drag-and-drop from Explorer works; clipboard paste
;; requires ImageMagick convert.exe or PowerShell fallback.
(use-package org-download
  :after org
  :hook (org-mode . org-download-enable)
  :custom
  (org-download-method 'attach)
  (org-download-heading-lvl nil)
  (org-download-timestamp "%Y%m%d%H%M%S-"))

;; pangu-spacing: auto-insert thin space between CJK and Latin characters.
;; Virtual mode (default) — spaces are *displayed* but not saved to file,
;; keeping the source clean.  Essential for CJK mixed-language writing.
;; NOTE: real-insert mode (pangu-spacing-real-insert-separtor t) would
;; break org tables and babel blocks — keep it nil.
(use-package pangu-spacing
  :hook (org-mode . pangu-spacing-mode)
  :config
  (setq pangu-spacing-real-insert-separator nil))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 4: Evil integration for org-mode
;; ═══════════════════════════════════════════════════════════════════════════

(use-package evil-org
  :after (org evil)
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar))
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 5: Local leader keys for Org buffers
;; ═══════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'org-mode-map
   :prefix ","
   :global-prefix "M-,"

   ""   '(nil :wk "org")

   ","  '(my/node-action :wk "Node actions")
   "r"  '(org-refile :wk "Refile")
   "a"  '(org-archive-subtree :wk "Archive")
   "t"  '(org-set-tags-command :wk "Set tags")
   "p"  '(org-set-property :wk "Set property")
   "e"  '(org-set-effort :wk "Set effort")
   "x"  '(org-export-dispatch :wk "Export")
   "l"  '(org-insert-link :wk "Insert link")
   "L"  '(org-store-link :wk "Store link")
   "s"  '(org-schedule :wk "Schedule")
   "d"  '(org-deadline :wk "Deadline")
   "i"  '(org-time-stamp :wk "Timestamp")
   "I"  '(org-time-stamp-inactive :wk "Timestamp (inactive)")
   "n"  '(org-narrow-to-subtree :wk "Narrow to subtree")
   "w"  '(widen :wk "Widen")
   "c"  '(org-toggle-checkbox :wk "Toggle checkbox")
   "q"  '(my/gtd-set-state :wk "State picker")
   "h"  '(my/gtd-toggle-hide-done :wk "Hide/show done")

   ;; , # -- node types and fields (init-nodes); mirrors SPC #.
   "#"  '(:ignore t :wk "types & fields")
   "##" '(my/node-action :wk "Node actions")
   "#t" '(my/node-set-type :wk "Add type")
   "#x" '(my/node-remove-type :wk "Remove type")
   "#f" '(my/node-set-field :wk "Set field")
   "#e" '(org-set-property :wk "Edit Org property")
   "#p" '(my/node-promote :wk "Promote to node")
   "#v" '(my/node-view :wk "Type view")
   "#j" '(org-open-at-point :wk "Open link")

   ;; , k — Clock
   "k"  '(:ignore t :wk "clock")
   "ki" '(org-clock-in :wk "Clock in")
   "ko" '(org-clock-out :wk "Clock out")
   "kg" '(org-clock-goto :wk "Goto clock")
   "kr" '(org-clock-report :wk "Report")
   "kc" '(org-clock-cancel :wk "Cancel")

   ;; , b — Babel
   "b"  '(:ignore t :wk "babel")
   "be" '(org-babel-execute-src-block :wk "Execute block")
   "bb" '(org-babel-execute-buffer :wk "Execute buffer")
   "bt" '(org-babel-tangle :wk "Tangle")))

(provide 'init-org)
;;; init-org.el ends here
