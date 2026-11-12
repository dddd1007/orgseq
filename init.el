;;; init.el --- Main configuration entry point -*- lexical-binding: t; -*-

(require 'cl-lib)

(defvar server-use-tcp)

;; ---- Restore reasonable GC after startup ----
;; gcmh (configured below) keeps the threshold high while typing and
;; collects during idle time (Doom-style).  Without gcmh installed, fall
;; back to a fixed 16MB threshold.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-percentage 0.1)
            (if (fboundp 'gcmh-mode)
                (gcmh-mode 1)
              (setq gc-cons-threshold (* 16 1024 1024)))  ; 16MB
            (message "Emacs loaded in %s with %d garbage collections."
                     (emacs-init-time) gcs-done)))

;; ---- Runtime performance (Doom-style) ----
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)
(setq-default cursor-in-non-selected-windows nil)
(setq highlight-nonselected-windows nil)
(setq redisplay-skip-fontification-on-input t)

;; Large process output buffer — benefits LSP, ripgrep, etc. (Doom/Purcell/Centaur)
(setq read-process-output-max (* 4 1024 1024))  ; 4MB

;; ---- Source layout ----
;; core/      distribution core: platform, packages, doctor, update, CLI
;; kernel/    note kernel: no UI, usable from a batch Emacs
;; modules/   feature modules grouped by area
;; user/      the user's own files; a deployment never writes there
(defconst my/init-source-directories
  '("core" "kernel"
    "modules/ui" "modules/editor" "modules/notes" "modules/tools" "modules/lang")
  "Directories under `user-emacs-directory' holding org-seq Elisp.")

(dolist (dir my/init-source-directories)
  (add-to-list 'load-path (expand-file-name dir user-emacs-directory)))

(defconst my/user-directory
  (expand-file-name "user/" user-emacs-directory)
  "Directory for the user's own configuration.
modules.el there runs before the modules load (set
`my/init-disabled-modules' and `my/init-enabled-optional-modules'),
config.el after them, and custom.el holds
Customize settings.  Deployment never writes this directory.")

(defun my/init-add-user-load-path ()
  "Append `my/user-directory' and its modules/ subdirectory to `load-path'.
Only directories that exist are added, and they go last so a user file
cannot shadow a library by accident.  User modules (see
`my/init-user-modules') are found through this."
  (dolist (dir (list my/user-directory
                     (expand-file-name "modules/" my/user-directory)))
    (when (file-directory-p dir)
      (add-to-list 'load-path (directory-file-name dir) t))))

(my/init-add-user-load-path)

;; ---- Platform tuning ----
;; Bootstrap-phase module: repairs `exec-path' and owns the ELPA signature
;; probe, both of which must run before the first package is installed.  It is
;; deliberately outside `my/init-modules-default'; that list is the guarded
;; post-package load order.
(require 'init-platform)

;; ---- Package management ----
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
;; Allow package.el to upgrade built-in packages (Transient, Org, etc.)
;; Set BEFORE any potential package-install / use-package activation.
(setq package-install-upgrade-built-in t)

;; Windows needs a working gpg before any package is fetched; see
;; `my/platform-resolve-package-signature' in core/init-platform.el.
(my/platform-resolve-package-signature)

(package-initialize)
(defconst my/noninteractive-init noninteractive
  "Non-nil when org-seq is running in a batch/noninteractive session.")

(defun my/package-refresh-contents-maybe ()
  "Refresh package archives only when startup can afford network I/O."
  (if my/noninteractive-init
      (message "org-seq: skipping package archive refresh in noninteractive session")
    (condition-case err
        (package-refresh-contents)
      (error
       (message "WARNING org-seq: package archive refresh failed (%s).
  Restart with network connectivity to install missing packages." err)))))

(unless package-archive-contents
  (my/package-refresh-contents-maybe))

;; ---- use-package (built in for the supported Emacs 30+ baseline) ----
(require 'use-package)
(defun my/use-package-ensure-or-warn (name ensure state)
  "Install NAME for `use-package' or warn when ENSURE is skipped.

During noninteractive validation runs, package installation is suppressed
so byte-compilation and load tests never block on network traffic."
  (if my/noninteractive-init
      (progn
        (dolist (entry ensure)
          (let ((package (or (and (eq entry t) (if (symbolp name) name (intern name)))
                             (and (consp entry) (car entry))
                             entry)))
            (when (and package
                       (not (package-installed-p package)))
              (display-warning
               'org-seq
               (format "Skipping package install for %s in noninteractive session"
                       package)
               :warning))))
        t)
    (use-package-ensure-elpa name ensure state)))

(setq use-package-ensure-function #'my/use-package-ensure-or-warn
      use-package-always-ensure (not my/noninteractive-init)
      use-package-expand-minimally t
      use-package-verbose nil)

;; ---- Garbage collection: collect on idle instead of mid-typing ----
;; Enabled from the emacs-startup-hook above, after startup GC suppression.
(use-package gcmh
  :defer t
  :custom
  (gcmh-idle-delay 'auto)                 ; idle delay scales with GC cost
  (gcmh-auto-idle-delay-factor 10)
  (gcmh-high-cons-threshold (* 64 1024 1024)))

;; ---- First-event hooks: defer non-critical packages past startup ----
;; Doom-style incremental loading, implemented independently.  Modules attach
;; packages that are not needed to paint the first frame:
;;
;;   :hook (my/first-input . which-key-mode)   ; first command or short idle
;;   :hook (my/first-file  . global-diff-hl-mode) ; first visited file
;;
;; Each hook runs once and is then cleared.  Batch and daemon sessions have
;; no interactive "first" event, so both hooks run right after the modules
;; load (see the end of the module loader), keeping validation deterministic.
;; A failing function is reported through `M-x my/init-errors' and does not
;; stop the rest of the hook.
(defvar my/first-input-hook nil
  "Hook run once on the first command, or after `my/first-input-idle-delay'.")

(defvar my/first-file-hook nil
  "Hook run once, just before the first file is visited.")

(defcustom my/first-input-idle-delay 1.5
  "Idle seconds after startup before `my/first-input-hook' runs anyway.
Loading on idle means deferred UI (which-key, completion) is usually ready
before the first key press; nil waits for the first command."
  :type '(choice (number :tag "Seconds") (const :tag "First command only" nil))
  :group 'org-seq)

(defvar my/--init-errors)

(defun my/--first-event-absent-autoload-p (fn)
  "Return non-nil when FN is an autoload whose package is not installed.
Absent optional packages are skipped silently, matching module loading."
  (and (symbolp fn)
       (autoloadp (symbol-function fn))
       (not (locate-library (cadr (symbol-function fn))))))

(defun my/run-first-event-hook (hook)
  "Run each function on HOOK once, recording errors, then clear HOOK."
  (let ((functions (default-value hook)))
    (set-default hook nil)
    (dolist (fn functions)
      (unless (or (eq fn t) (my/--first-event-absent-autoload-p fn))
        (condition-case err
            (funcall fn)
          (error
           (push (cons (intern (format "%s/%s" hook fn)) err) my/--init-errors)
           (message "WARNING org-seq: %s failed in %s: %s (inspect with M-x my/init-errors)"
                    fn hook (error-message-string err))))))))

(defun my/first-event-trigger (hook)
  "Return a one-shot trigger that runs HOOK and detaches itself."
  (let (trigger)
    (setq trigger
          (lambda (&rest _)
            (remove-hook 'pre-command-hook trigger)
            (advice-remove 'after-find-file trigger)
            (my/run-first-event-hook hook)))
    trigger))

(defun my/first-event-install ()
  "Arm the interactive triggers for the first-event hooks."
  (let ((input (my/first-event-trigger 'my/first-input-hook))
        (file (my/first-event-trigger 'my/first-file-hook)))
    (add-hook 'pre-command-hook input -90)
    (when my/first-input-idle-delay
      (add-hook 'emacs-startup-hook
                (lambda ()
                  (run-with-idle-timer my/first-input-idle-delay nil input))))
    ;; Advise `after-find-file' rather than using `find-file-hook' so modes
    ;; enabled here (save-place, diff-hl) already see the first file.
    (advice-add 'after-find-file :before file)))

(defun my/first-event-run-all ()
  "Run both first-event hooks immediately (batch and daemon sessions)."
  (my/run-first-event-hook 'my/first-input-hook)
  (my/run-first-event-hook 'my/first-file-hook))

;; ---- Pre-module variable setup ----
;; Declare a few early-set variables so byte-compilation catches real issues
;; instead of reporting expected cross-module/built-in customization points.
(defvar evil-want-keybinding)
(defvar ffap-machine-p-known)
(defvar reb-re-syntax)

;; evil-want-keybinding must be nil BEFORE evil or evil-collection loads.
;; init-evil.el loads last, but byte-compilation of earlier modules can
;; trigger the evil-collection runtime warning.  Setting it here (before
;; any module loads) suppresses the warning unconditionally.
(setq evil-want-keybinding nil)

;; ---- Separate custom file ----
;; Customize settings live in user/custom.el.  A custom.el left at the top
;; of the Emacs directory by an earlier version keeps working until the
;; deploy script moves it.
(setq custom-file
      (let ((current (expand-file-name "custom.el" my/user-directory))
            (legacy (expand-file-name "custom.el" user-emacs-directory)))
        (if (and (not (file-exists-p current)) (file-exists-p legacy))
            legacy
          current)))

(defun my/load-custom-file ()
  "Load `custom-file' as explicit user overrides, reporting failures clearly."
  (interactive)
  (if (file-exists-p custom-file)
      (condition-case err
          (progn
            ;; Loaded before modules by design: values saved through Customize
            ;; can affect subsequent `defcustom' defaults and use-package setup.
            (load custom-file nil 'nomessage)
            (message "org-seq: loaded user overrides from %s" custom-file)
            t)
        (error
         (display-warning
          'org-seq
          (format "Failed to load custom-file %s: %s" custom-file err)
          :error)
         nil))
    (message "org-seq: custom-file does not exist yet: %s" custom-file)
    nil))

(defun my/open-custom-file ()
  "Open `custom-file' for inspecting user-level overrides."
  (interactive)
  (find-file custom-file))

(my/load-custom-file)

;; ---- Clipboard sanity (Purcell/Prot/Centaur) ----
(setq save-interprogram-paste-before-kill t   ; preserve external clipboard before kill
      kill-do-not-save-duplicates t)          ; no consecutive dupes in kill ring

;; ---- History persistence ----
(use-package savehist
  :ensure nil
  :custom
  (savehist-additional-variables '(search-ring regexp-search-ring kill-ring))
  :config
  ;; Strip text properties before saving to prevent savehist file bloat (Doom)
  (add-hook 'savehist-save-hook
            (lambda ()
              (setq kill-ring
                    (mapcar #'substring-no-properties
                            (cl-remove-if-not #'stringp kill-ring)))))
  :init (savehist-mode))

;; ---- Save place: reopen files at last position ----
(use-package saveplace
  :ensure nil
  :init (save-place-mode)
  :config
  ;; Recenter after restoring saved position (Doom) — avoids cursor at window edge
   (advice-add 'save-place-find-file-hook :after
               (lambda (&rest _)
                 (when buffer-file-name (ignore-errors (recenter))))))

;; ---- Centralized backups: keep NoteHQ clean ----
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory)))
  (make-directory backup-dir t)
  (unless backup-directory-alist
    (setq backup-directory-alist `(("." . ,backup-dir)))))

;; ---- Parenthesis matching ----
(use-package paren
  :ensure nil
  :init
  (show-paren-mode 1))

;; ---- Editing polish ----
(setq set-mark-command-repeat-pop t)           ; C-SPC C-SPC ... pops mark ring (Purcell/Prot)
(setq help-window-select t)                    ; auto-focus *Help* buffer (Prot)
(setq window-combination-resize t)             ; proportional window resize on split (Purcell/Prot)
(setq ffap-machine-p-known 'reject)            ; no network pings in find-file-at-point (Centaur)
(setq reb-re-syntax 'string)                   ; sane regex builder syntax — no double-escaping

;; Winner mode: undo/redo window layouts
(winner-mode +1)

;; so-long: degrade gracefully on minified / single-line huge files (Doom)
(global-so-long-mode 1)

;; ws-butler: trim trailing whitespace only on lines you edited, so saving
;; (including auto-save-visited below) never rewrites untouched lines (Doom).
;; Markdown is exempt because two trailing spaces are a hard line break.
(use-package ws-butler
  :hook (my/first-file . ws-butler-global-mode)
  :custom
  (ws-butler-keep-whitespace-before-point nil)
  (ws-butler-global-exempt-modes
   '(special-mode comint-mode term-mode eshell-mode diff-mode
     markdown-mode gfm-mode)))

;; dtrt-indent: adopt the indentation style of the file being edited (Doom).
;; Lisp indentation is structural, so Lisp modes keep their own rules.
(declare-function dtrt-indent-mode "dtrt-indent" (&optional arg))
(use-package dtrt-indent
  :hook (prog-mode . my/dtrt-indent-maybe)
  :custom
  (dtrt-indent-verbosity 0)
  :preface
  (defun my/dtrt-indent-maybe ()
    "Enable `dtrt-indent-mode' outside Lisp modes."
    (unless (derived-mode-p 'lisp-data-mode)
      (dtrt-indent-mode 1))))

;; Auto-chmod scripts on save (cross-platform; no-op on Windows)
(add-hook 'after-save-hook
          #'executable-make-buffer-file-executable-if-script-p)

;; ---- Auto-save visited files (VS Code-style afterDelay) ----
;; Saves the on-disk file behind every visiting buffer every N seconds of
;; idle time, like VS Code's "Auto Save: afterDelay".  No #autosave# files
;; are produced; the visited file itself is written.
;;
;; Side effect 1 (acceptable): each save of a note changes its file time,
;; and the kernel index (kernel/orgseq-index.el) re-reads only that file
;; on its next query, so the 2s interval does not rescan NoteHQ.
;;
;; Side effect 2 (acceptable): saving an emacs-lisp buffer runs
;; compile-angel's on-save byte-compilation (init-update.el), so editing
;; this config fires background compiles.  This is the intended compile
;; behavior, just more frequent.
(setq auto-save-visited-interval 2)
(auto-save-visited-mode 1)

;; ---- External dependency checks (deferred to avoid process spawns during init) ----
(run-with-idle-timer 2 nil
  (lambda ()
    (dolist (tool '(("rg" . "ripgrep") ("fd" . "fd-find")))
      (unless (executable-find (car tool))
        (message "WARNING org-seq: %s (%s) not found. Install via your package manager%s."
                 (car tool) (cdr tool)
                 (if (eq system-type 'windows-nt) " (winget/scoop)" ""))))))

;; ---- Load modules ----
;; Canonical order (the tie-break; the load order is computed from
;; `my/init-module-requires'): doctor -> packages -> popup -> keymap -> UI -> completion -> pyim -> python
;; -> markdown -> languages -> org -> capture -> roam (optional, off by default)
;; -> gtd -> gtd-dashboard -> focus -> pkm -> nodes -> views -> palette -> sync
;; -> daily -> terminal
;; -> ai -> ai-cli -> dashboard -> dired
;; -> mouse -> frame -> workspace -> update -> tty -> evil (last)
;; Each require is guarded so a single broken module does not kill the
;; entire config -- the user gets an actionable warning and can inspect
;; details with `M-x my/init-errors'.
(defvar my/--init-errors nil
  "List of (MODULE . ERROR) pairs for modules that failed to load.")

(defvar my/--init-results nil
  "Reverse-ordered module load result plists for the current startup.")

(defconst my/init-modules-default
  '(init-doctor
    init-packages
    init-popup
    init-keymap
    init-ui
    init-completion
    init-pyim
    init-python
    init-markdown
    init-languages
    init-org
    init-capture
    init-roam
    init-gtd
    init-gtd-dashboard
    init-focus
    init-pkm
    init-nodes
    init-views
    init-palette
    init-sync
    init-daily
    init-terminal
    init-ai
    init-ai-cli
    init-dashboard
    init-dired
    init-mouse
    init-frame
    init-workspace
    init-update
    init-tty
    init-evil)
  "Canonical org-seq module list.
This is the set of built-in modules and the tie-break order: the load order
is computed from `my/init-module-requires' by `my/init-sort-modules', and
modules without an ordering constraint between them keep their order here.
Kept separate from `my/init-modules' so tests can inspect the canonical
order while overriding the effective load list.")

(defvar my/init-modules my/init-modules-default
  "Modules loaded by org-seq.
At startup this becomes the computed load order of the enabled modules,
built-in and user.")

(defconst my/init-module-pins
  '((init-doctor . first)
    (init-evil . last))
  "Alist of (MODULE . first|last) for modules pinned by position.
These are not dependencies.  init-doctor loads first so the diagnostic
commands survive a failure in any later module; init-evil loads last
because its leader map references commands from nearly every other module,
whether or not those modules declare it.  Pinned modules are placed before
or after everything the sort orders; a module that requires a `last' module
is reported as a violation by `my/init-check-module-order'.")

(defvar my/init-user-modules nil
  "User modules to load, as a list of (FEATURE . REQUIRES).
Set it in user/modules.el, for example
\='((my-research . (init-org init-nodes))).  FEATURE is loaded with
`require' from user/FEATURE.el or user/modules/FEATURE.el, which must
`provide' it.  REQUIRES names modules that must load first; a user module
whose requirement is unknown or disabled is skipped with a warning.")

(defvar my/init-disabled-modules nil
  "Modules from `my/init-modules' that are not loaded.
Set it in user/modules.el, for example (setq my/init-disabled-modules
\='(init-pyim init-python)).  Startup warns when an enabled module
depends on a disabled one.")

(defconst my/init-optional-modules '(init-roam)
  "Modules in `my/init-modules-default' that load only when enabled.
They keep their place in the canonical order; see
`my/init-enabled-optional-modules'.  No module of the default set may
depend on one of them.")

(defvar my/init-enabled-optional-modules nil
  "Optional modules (from `my/init-optional-modules') to load.
Set it in user/modules.el, for example (setq
my/init-enabled-optional-modules \='(init-roam)) to add org-roam, its
graph view and consult-org-roam.")

(defun my/init-module-skip-reason (module)
  "Return why MODULE is not loaded by configuration, or nil."
  (cond ((memq module my/init-disabled-modules)
         "disabled in my/init-disabled-modules")
        ((and (memq module my/init-optional-modules)
              (not (memq module my/init-enabled-optional-modules)))
         "optional, not in my/init-enabled-optional-modules")))

(defun my/init-effective-modules (&optional modules)
  "Return MODULES (default `my/init-modules') as they are actually loaded.
Modules in `my/init-disabled-modules' are dropped, and so are optional
modules that are not in `my/init-enabled-optional-modules'."
  (cl-remove-if #'my/init-module-skip-reason (or modules my/init-modules)))

(defun my/init-module-source (module)
  "Return where MODULE comes from: `built-in', `optional' or `user'."
  (cond ((memq module my/init-optional-modules) 'optional)
        ((memq module my/init-modules-default) 'built-in)
        (t 'user)))

(defun my/load-user-file (name)
  "Load NAME from `my/user-directory' when it exists; report failures.
Return non-nil when the file was loaded."
  (let ((file (expand-file-name name my/user-directory)))
    (when (file-exists-p file)
      (condition-case err
          (progn (load file nil 'nomessage) t)
        (error
         (push (cons (intern (concat "user/" name)) err) my/--init-errors)
         (display-warning
          'org-seq
          (format "Failed to load %s: %s (inspect with M-x my/init-errors)"
                  file (error-message-string err))
          :error)
         nil)))))

(defconst my/init-module-requires
  '(;; BEGIN generated by scripts/gen-module-requires.el
    (init-ui            . (init-packages))
    (init-markdown      . (init-ui))
    (init-languages     . (init-completion init-python))
    (init-org           . (init-packages init-ui))
    (init-capture       . (init-org))
    (init-roam          . (init-org init-capture))
    (init-gtd           . (init-org))
    (init-gtd-dashboard . (init-gtd init-ui))
    (init-focus         . (init-org))
    (init-nodes         . (init-org init-capture))
    (init-views         . (init-org init-nodes))
    (init-palette       . (init-org init-nodes init-views))
    (init-sync          . (init-org))
    (init-daily         . (init-capture init-ui))
    (init-terminal      . (init-popup init-org))
    (init-ai            . (init-org init-packages init-popup))
    (init-ai-cli        . (init-org init-packages init-terminal))
    (init-dashboard     . (init-daily init-capture))
    (init-dired         . (init-org init-ui init-terminal))
    (init-mouse         . (init-org init-gtd init-gtd-dashboard init-daily))
    (init-workspace     . (init-org init-daily init-terminal init-dired init-frame))
    (init-tty           . (init-completion init-ui))
    (init-evil          . (init-keymap))
    ;; END generated
    )
  "Alist of (MODULE . DEPENDENCIES) mirroring the module \"Requires:\" headers.
The load order is computed from it by `my/init-sort-modules'.  The block
between the BEGIN and END markers is generated from the headers: edit the
module's \"Requires:\" comment, then run
  emacs --batch -Q -l scripts/gen-module-requires.el \\
        --eval \"(my/gen-module-requires-main t)\"
to rewrite it; scripts/test-init-loader.el fails when it is stale.")

(defun my/init-check-module-order (&optional modules requires)
  "Return module dependency violations as a list of (MODULE . PROBLEM) pairs.
MODULES defaults to `my/init-modules'; REQUIRES defaults to
`my/init-module-requires'.  A violation is a declared dependency that is
missing from MODULES or ordered after the module that requires it."
  (let ((modules (or modules my/init-modules))
        (requires (or requires my/init-module-requires))
        violations)
    (dolist (entry requires)
      (let* ((module (car entry))
             (pos (cl-position module modules)))
        (when pos
          (dolist (dep (cdr entry))
            (let ((dep-pos (cl-position dep modules)))
              (cond
               ((null dep-pos)
                (push (cons module
                            (format "dependency %s is not in my/init-modules" dep))
                      violations))
               ((> dep-pos pos)
                (push (cons module
                            (format "dependency %s loads after it" dep))
                      violations))))))))
    (nreverse violations)))

(defun my/init-find-cycle (remaining requires)
  "Return a dependency cycle among REMAINING as a list ending where it began.
Every module of REMAINING has a dependency inside REMAINING, so following
the first such dependency from the first module must repeat."
  (let ((node (car remaining))
        (path nil))
    (while (not (memq node path))
      (push node path)
      (setq node (cl-find-if (lambda (dep) (memq dep remaining))
                             (cdr (assq node requires)))))
    (append (memq node (reverse path)) (list node))))

(defun my/init-sort-modules (modules requires &optional pins)
  "Return (ORDER . CYCLE) for MODULES under REQUIRES and PINS.
ORDER is a stable topological sort: a module comes after every module it
requires, and among modules with no constraint between them the order of
MODULES is kept.  REQUIRES is an alist of (MODULE . DEPENDENCIES); a
dependency that is not in MODULES is ignored here (see
`my/init-check-module-order').  PINS is an alist of (MODULE . first|last):
pinned modules go before or after everything else, in MODULES order.
When the requirements contain a cycle, CYCLE lists it (ending with the
module it started from) and ORDER is MODULES unchanged."
  (let* ((pinned (lambda (side)
                   (cl-remove-if-not (lambda (m) (eq (cdr (assq m pins)) side))
                                     modules)))
         (firsts (funcall pinned 'first))
         (lasts (funcall pinned 'last))
         (remaining (cl-remove-if (lambda (m) (assq m pins)) modules))
         (placed nil)
         (cycle nil))
    (while (and remaining (not cycle))
      (let ((next (cl-find-if
                   (lambda (m)
                     (cl-every (lambda (dep)
                                 (not (memq dep remaining)))
                               (cdr (assq m requires))))
                   remaining)))
        (if next
            (progn (push next placed)
                   (setq remaining (remq next remaining)))
          (setq cycle (my/init-find-cycle remaining requires)))))
    (if cycle
        (cons modules cycle)
      (cons (append firsts (nreverse placed) lasts) nil))))

(defun my/init-plan-modules (enabled &optional user-modules requires pins)
  "Plan the load order for the ENABLED built-in modules plus USER-MODULES.
USER-MODULES is a list of (FEATURE . REQUIRES) like `my/init-user-modules'.
REQUIRES defaults to `my/init-module-requires' and PINS to
`my/init-module-pins'.  Return a plist:
  :order    modules in load order (ENABLED first, then accepted user
            modules, sorted by `my/init-sort-modules')
  :requires REQUIRES extended with the accepted user modules
  :skipped  alist of (USER-MODULE . REASON) for rejected user modules
  :cycle    a dependency cycle, or nil
A user module is rejected when it is malformed, repeats a name, clashes
with a built-in module, or needs a module that is not loaded (directly or
because that module was itself rejected)."
  (let ((requires (or requires my/init-module-requires))
        (pins (or pins my/init-module-pins))
        (accepted nil) (skipped nil))
    (dolist (entry user-modules)
      (let ((name (car-safe entry)))
        (cond
         ((not (and (symbolp name) name (listp (cdr entry))
                    (cl-every #'symbolp (cdr entry))))
          (push (cons (if (symbolp name) name 'invalid)
                      "malformed entry in my/init-user-modules")
                skipped))
         ((or (memq name my/init-modules-default) (memq name enabled))
          (push (cons name "name clashes with a built-in module") skipped))
         ((assq name accepted)
          (push (cons name "declared more than once") skipped))
         (t (push entry accepted)))))
    (setq accepted (nreverse accepted))
    (let ((changed t))
      (while changed
        (setq changed nil)
        (dolist (entry accepted)
          (let ((missing
                 (cl-find-if (lambda (dep)
                               (not (or (memq dep enabled) (assq dep accepted))))
                             (cdr entry))))
            (when missing
              (push (cons (car entry)
                          (format "requires %s, which is unknown or not loaded"
                                  missing))
                    skipped)
              (setq accepted (remq entry accepted)
                    changed t))))))
    (let* ((requires (append requires
                             (mapcar (lambda (e) (cons (car e) (cdr e)))
                                     accepted)))
           (sorted (my/init-sort-modules
                    (append enabled (mapcar #'car accepted)) requires pins)))
      (list :order (car sorted) :requires requires
            :skipped (nreverse skipped) :cycle (cdr sorted)))))

(defun my/init-results ()
  "Return module load results in attempted load order."
  (reverse (copy-sequence my/--init-results)))

(defun my/init-failed-modules ()
  "Return failed module symbols in attempted load order."
  (let (failed)
    (dolist (result (my/init-results))
      (when (eq (plist-get result :status) 'failed)
        (push (plist-get result :module) failed)))
    (nreverse failed)))

(defun my/init-errors ()
  "Display modules that failed during org-seq startup."
  (interactive)
  (let ((buf (get-buffer-create "*org-seq init errors*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if my/--init-errors
            (progn
              (insert (format "%d org-seq module(s) failed to load.\n\n"
                              (length my/--init-errors)))
              (dolist (pair (reverse my/--init-errors))
                (insert (format "* %s\n" (car pair)))
                (insert (format "  %s\n\n" (error-message-string (cdr pair))))))
          (insert "No org-seq module load errors recorded.\n"))
        (special-mode)))
    (pop-to-buffer buf)))

(defun my/--require-module (module)
  "Load MODULE and record its status, elapsed time, and error.
Return non-nil when MODULE loads successfully."
  (let ((started (float-time)))
    (condition-case err
        (progn
          (require module)
          (push (list :module module
                      :status 'loaded
                      :elapsed (- (float-time) started)
                      :error nil)
                my/--init-results)
          t)
      (error
       (push (cons module err) my/--init-errors)
       (push (list :module module
                   :status 'failed
                   :elapsed (- (float-time) started)
                   :error err)
             my/--init-results)
       (message "WARNING org-seq: failed to load %s: %s (inspect with M-x my/init-errors)"
                module (error-message-string err))
       nil))))

(setq my/--init-errors nil
      my/--init-results nil)

;; The user's module selection, read before anything is checked or loaded.
(my/load-user-file "modules.el")

(defvar my/--init-skipped nil
  "Alist of (MODULE . REASON) for modules not loaded this startup.")

(defvar my/--init-requires nil
  "`my/init-module-requires' extended with the loaded user modules.")

;; Compute the load order from the declared dependencies.  Disabled and
;; optional modules drop out first; accepted user modules join the sort.
(let* ((enabled (my/init-effective-modules my/init-modules))
       (plan (my/init-plan-modules enabled my/init-user-modules))
       (cycle (plist-get plan :cycle)))
  (setq my/--init-requires (plist-get plan :requires)
        my/--init-skipped
        (append
         (delq nil (mapcar (lambda (m)
                             (when-let* ((why (my/init-module-skip-reason m)))
                               (cons m why)))
                           my/init-modules))
         (plist-get plan :skipped))
        my/init-modules (plist-get plan :order))
  (dolist (skip (plist-get plan :skipped))
    (display-warning
     'org-seq
     (format "user module %s skipped: %s" (car skip) (cdr skip))
     :warning))
  (when cycle
    (display-warning
     'org-seq
     (format "module order: dependency cycle %s; using the canonical order"
             (mapconcat #'symbol-name cycle " -> "))
     :error)))

;; Dependency assertion: fail loudly (but non-fatally) when the module list
;; violates the declared load-order contract, before any module loads.
(dolist (violation (my/init-check-module-order my/init-modules
                                               my/--init-requires))
  (display-warning
   'org-seq
   (format "module order: %s: %s" (car violation) (cdr violation))
   :error))

(dolist (module my/init-modules)
  (my/--require-module module))

;; The user's own configuration, after every module is in place.
(my/load-user-file "config.el")

;; Deferred packages: interactive sessions wait for the first event; batch
;; and daemon sessions have none, so load everything now.
(if (or my/noninteractive-init (daemonp))
    (my/first-event-run-all)
  (my/first-event-install))

(when my/--init-errors
  (run-with-idle-timer
   1 nil
   (lambda ()
     (message "org-seq: %d module(s) failed to load: %s"
              (length my/--init-errors)
              (mapconcat (lambda (pair) (symbol-name (car pair)))
                         my/--init-errors ", ")))))

;; ---- Emacs server ----
;; Start server so emacsclient can connect instantly.
;; Windows: `server-use-tcp' is set above, so clients must point at the
;; TCP auth file (for the named org-seq daemon this is ~/.emacs.d/server/org-seq).
;; Linux/macOS use the normal local socket and can connect with
;; `emacsclient -s org-seq`.
(require 'server)
(setq server-name "org-seq")
(unless my/noninteractive-init
  (unless (server-running-p server-name)
    (server-start)))

(provide 'init)
;;; init.el ends here
