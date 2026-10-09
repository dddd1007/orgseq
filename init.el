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

;; ---- Module load path ----
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

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
;; `my/platform-resolve-package-signature' in lisp/init-platform.el.
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
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

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
;; Side effect 1 (verified): a Daily note save triggers
;; `my/daily--schedule-supertag-sync' (init-daily.el) -> the debounced
;; `my/supertag-schedule-sync' (init-pkm.el, 0.5s idle) ->
;; `supertag-sync-check-now'.  That check is incremental: it compares each
;; tracked file's mtime against the stored last-sync time
;; (`supertag-sync-check-state') and re-parses only the changed files, so
;; the 2s interval does not rescan NoteHQ.  The interval stays at 2s.
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
;; Order: doctor -> packages -> popup -> keymap -> UI -> completion -> pyim -> python
;; -> markdown -> languages -> org -> roam
;; -> gtd -> gtd-dashboard -> focus -> pkm -> supertag -> daily -> terminal
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
    init-roam
    init-gtd
    init-gtd-dashboard
    init-focus
    init-pkm
    init-supertag
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
  "Canonical org-seq module list in dependency order.
Kept separate from `my/init-modules' so tests can inspect the canonical
order while overriding the effective load list.")

(defvar my/init-modules my/init-modules-default
  "Modules loaded by org-seq in dependency order.")

(defconst my/init-module-requires
  '((init-ui            . (init-packages))
    (init-markdown      . (init-ui))
    (init-languages     . (init-completion init-python))
    (init-org           . (init-packages))
    (init-roam          . (init-org))
    (init-gtd           . (init-org))
    (init-gtd-dashboard . (init-gtd))
    (init-focus         . (init-org))
    (init-pkm           . (init-org init-packages))
    (init-supertag      . (init-org init-pkm init-roam))
    (init-daily         . (init-roam init-pkm))
    (init-terminal      . (init-popup init-org))
    (init-ai            . (init-org init-packages init-popup))
    (init-ai-cli        . (init-org init-packages init-terminal))
    (init-dashboard     . (init-daily init-roam))
    (init-dired         . (init-org init-ui init-terminal))
    (init-mouse         . (init-org init-gtd init-gtd-dashboard init-daily))
    (init-workspace     . (init-org init-daily init-terminal init-dired init-frame))
    (init-tty           . (init-completion init-ui))
    (init-evil          . (init-keymap)))
  "Alist of (MODULE . DEPENDENCIES) mirroring the module \"Requires:\" headers.
Every dependency must appear before MODULE in `my/init-modules'.  This is
the machine-checkable form of the load-order contract: startup warns on
violations, and scripts/test-init-loader.el fails on them.  When adding a
module, add its record here and keep the module file's \"Requires:\"
comment in sync.")

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

;; Dependency assertion: fail loudly (but non-fatally) when the module list
;; violates the declared load-order contract, before any module loads.
(dolist (violation (my/init-check-module-order))
  (display-warning
   'org-seq
   (format "module order: %s: %s" (car violation) (cdr violation))
   :error))

(dolist (module my/init-modules)
  (my/--require-module module))

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
