# Daily Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a capture-ready org-roam Daily Note and a dedicated 14-day navigation sidebar the default org-seq workspace, with every captured heading ready for org-supertag organization.

**Architecture:** Add one focused `init-daily` module between `init-supertag` and `init-terminal`. It consumes existing org-roam path/navigation and supertag sync boundaries, while `init-workspace`, `init-dashboard`, and `init-evil` remain the owners of startup layout, Dashboard presentation, and global keys.

**Tech Stack:** Emacs 30.2, lexical-binding Elisp, Org, org-roam dailies, org-supertag, `special-mode`, side windows, dashboard.el, Evil/general.el, ERT, PowerShell 7.

## Global Constraints

- Treat Emacs 30+ as the active requirement.
- Keep `package.el`, `package-vc-install`, and built-in `use-package`; add no dependency.
- Keep all note paths derived from `my/roam-dir` and `org-roam-dailies-directory`.
- Do not rewrite existing Daily files, create historical files while rendering, or mutate user schema.
- Keep Elisp identifiers under `my/`; use `my/daily--` for private helpers.
- Use lexical binding, ASCII source text, forward slashes in Elisp paths, and explicit cross-module declarations.
- Preserve Dashboard, Treemacs, existing dailies commands, `custom.el`, and strict validation.
- Follow red-green-refactor and commit each independently testable task.
- Run commands from `D:\CodeProject\org-seq` with `C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe`.

---

## File Map

- Create `lisp/init-daily.el`: date records, Daily node preparation, sidebar, and public Daily Workspace commands.
- Create `scripts/test-init-daily.el`: date/path, node, sidebar, sync, and workspace unit tests.
- Modify `init.el`: register `init-daily` after `init-supertag` and before `init-terminal`.
- Modify `lisp/init-workspace.el`: select the Daily initial buffer, delegate Daily startup, and transition between managed sidebars.
- Modify `lisp/init-dashboard.el`: add the Daily section before recents and route Today through the workspace API.
- Modify `lisp/init-keymap.el`: add Daily workspace and append commands to the critical binding contract.
- Modify `lisp/init-evil.el`: bind `SPC n d d` and `SPC n d a` without disturbing other dailies keys.
- Modify `scripts/test-init-keymap.el`: assert the new critical bindings.
- Modify `scripts/test-provenance.el`: assert module order and Dashboard source contract.
- Modify user and contributor documentation listed in Task 6.

---

### Task 1: Pure Daily Date And File Model

**Files:**
- Create: `lisp/init-daily.el`
- Create: `scripts/test-init-daily.el`

**Interfaces:**
- Consumes: `my/roam-dir`, `org-roam-dailies-directory`, and `my/org-roam-dailies--file-for-date`.
- Produces: `(my/daily-date-records &optional time count)`, `(my/daily-buffer-p &optional buffer)`, `my/daily-sidebar-days`, `my/daily-sidebar-width`, and `my/daily-auto-prepare-today`.

- [ ] **Step 1: Write failing date and mutation-boundary tests**

Create `scripts/test-init-daily.el`:

```elisp
;;; test-init-daily.el --- Tests for Daily Workspace -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(load-file
 (expand-file-name "../lisp/init-daily.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/daily-date-records-use-fourteen-calendar-days ()
  (let* ((root (make-temp-file "org-seq-daily-dates-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (now (encode-time 0 30 12 10 3 2026))
         (records (my/daily-date-records now 14)))
    (unwind-protect
        (progn
          (should (= (length records) 14))
          (should (equal (plist-get (car records) :date) "2026-03-10"))
          (should (equal (plist-get (car (last records)) :date)
                         "2026-02-25"))
          (should (plist-get (car records) :today))
          (should-not (seq-some (lambda (record)
                                  (plist-get record :exists))
                                records))
          (should-not (file-exists-p (expand-file-name "daily" root))))
      (delete-directory root t))))

(ert-deftest my/daily-date-records-classify-existing-files-read-only ()
  (let* ((root (make-temp-file "org-seq-daily-existing-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (now (encode-time 0 0 12 14 7 2026))
         (today (expand-file-name "daily/2026-07-14.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory today) t)
          (write-region "#+title: 2026-07-14\n" nil today nil 'silent)
          (let ((records (my/daily-date-records now 2)))
            (should (plist-get (nth 0 records) :exists))
            (should-not (plist-get (nth 1 records) :exists))))
      (delete-directory root t))))

(ert-deftest my/daily-buffer-p-stays-inside-configured-directory ()
  (let* ((root (make-temp-file "org-seq-daily-buffer-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/"))
    (unwind-protect
        (with-temp-buffer
          (setq buffer-file-name
                (expand-file-name "daily/2026-07-14.org" root))
          (should (my/daily-buffer-p))
          (setq buffer-file-name (expand-file-name "capture/note.org" root))
          (should-not (my/daily-buffer-p)))
      (delete-directory root t))))

;;; test-init-daily.el ends here
```

- [ ] **Step 2: Run the focused suite and confirm red state**

```powershell
& "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" --batch -Q `
  -L . -L lisp `
  -l scripts/test-init-daily.el `
  -f ert-run-tests-batch-and-exit
```

Expected: non-zero exit because `lisp/init-daily.el` or the tested functions do not exist.

- [ ] **Step 3: Implement the pure model**

Create `lisp/init-daily.el` with the following core. Generate local-noon times from Gregorian absolute dates so DST cannot duplicate or skip a displayed date.

```elisp
;;; init-daily.el --- Daily-first workspace and navigation -*- lexical-binding: t; -*-

;; Requires: init-roam (my/roam-dir, dailies path helpers)
;; Requires: init-supertag (my/supertag-schedule-sync)

(require 'calendar)
(require 'cl-lib)
(require 'org)
(require 'subr-x)

(defvar my/roam-dir)
(defvar org-roam-dailies-directory)

(declare-function my/org-roam-dailies--file-for-date "init-roam" (time))
(declare-function my/supertag-schedule-sync "init-pkm" ())

(defcustom my/daily-sidebar-days 14
  "Number of consecutive calendar days shown in the Daily sidebar."
  :type 'integer
  :group 'org-seq)

(defcustom my/daily-sidebar-width 25
  "Width in columns of the Daily sidebar."
  :type 'integer
  :group 'org-seq)

(defcustom my/daily-auto-prepare-today t
  "When non-nil, opening Today's workspace prepares one capture node."
  :type 'boolean
  :group 'org-seq)

(defun my/daily--directory ()
  "Return the configured org-roam dailies directory."
  (file-name-as-directory
   (expand-file-name (or (and (boundp 'org-roam-dailies-directory)
                              org-roam-dailies-directory)
                         "daily/")
                     my/roam-dir)))

(defun my/daily--file-for-time (time)
  "Return the Daily file path for TIME without creating it."
  (if (fboundp 'my/org-roam-dailies--file-for-date)
      (my/org-roam-dailies--file-for-date time)
    (expand-file-name (format-time-string "%Y-%m-%d.org" time)
                      (my/daily--directory))))

(defun my/daily--gregorian-for-time (time)
  "Return Gregorian (MONTH DAY YEAR) for TIME."
  (let ((decoded (decode-time time)))
    (list (decoded-time-month decoded)
          (decoded-time-day decoded)
          (decoded-time-year decoded))))

(defun my/daily--time-for-absolute-date (absolute)
  "Return local noon for Gregorian ABSOLUTE date."
  (pcase-let ((`(,month ,day ,year)
               (calendar-gregorian-from-absolute absolute)))
    (encode-time 0 0 12 day month year)))

(defun my/daily-date-records (&optional time count)
  "Return COUNT Daily date records ending at TIME, newest first."
  (let* ((time (or time (current-time)))
         (count (or count my/daily-sidebar-days))
         (today (calendar-absolute-from-gregorian
                 (my/daily--gregorian-for-time time))))
    (cl-loop for offset below count
             for item-time = (my/daily--time-for-absolute-date
                              (- today offset))
             for file = (my/daily--file-for-time item-time)
             collect (list :time item-time
                           :date (format-time-string "%Y-%m-%d" item-time)
                           :label (if (zerop offset)
                                      "Today"
                                    (format-time-string "%a %b %d" item-time))
                           :file file
                           :exists (file-exists-p file)
                           :today (zerop offset)))))

(defun my/daily-buffer-p (&optional buffer)
  "Return non-nil when BUFFER visits a file in the dailies directory."
  (with-current-buffer (or buffer (current-buffer))
    (when buffer-file-name
      (file-in-directory-p (expand-file-name buffer-file-name)
                           (my/daily--directory)))))

(provide 'init-daily)
;;; init-daily.el ends here
```

- [ ] **Step 4: Run tests and byte compilation**

Run the focused ERT command, then:

```powershell
& "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" --batch -Q `
  -L . -L lisp `
  -f batch-byte-compile lisp/init-daily.el
Remove-Item -LiteralPath lisp/init-daily.elc -ErrorAction SilentlyContinue
```

Expected: three ERT tests pass; compilation exits zero; no `.elc` remains.

- [ ] **Step 5: Commit the pure model**

```powershell
git add lisp/init-daily.el scripts/test-init-daily.el
git diff --cached --check
git commit -m "feat: add Daily date model"
```

---

### Task 2: Capture-Ready Nodes And Supertag Save Hook

**Files:**
- Modify: `lisp/init-daily.el`
- Modify: `scripts/test-init-daily.el`

**Interfaces:**
- Consumes: `my/daily-buffer-p`, `org-id-get-create`, `my/supertag-schedule-sync`.
- Produces: `(my/daily--prepare-node) -> marker` and `my/daily-note-mode`.

- [ ] **Step 1: Add failing node and sync tests**

Append:

```elisp
(ert-deftest my/daily-prepare-node-creates-id-and-reuses-blank-tail ()
  (let* ((root (make-temp-file "org-seq-daily-node-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (file (expand-file-name "daily/2026-07-14.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory file) t)
          (with-current-buffer (find-file-noselect file)
            (erase-buffer)
            (insert "#+title: 2026-07-14\n#+filetags: :daily:\n\n")
            (org-mode)
            (my/daily-note-mode 1)
            (my/daily--prepare-node)
            (let ((first-id (org-entry-get nil "ID")))
              (should first-id)
              (my/daily--prepare-node)
              (should (equal (org-entry-get nil "ID") first-id))
              (should (= (how-many "^\\* " (point-min) (point-max)) 1)))
            (kill-buffer (current-buffer))))
      (delete-directory root t))))

(ert-deftest my/daily-prepare-node-appends-after-content ()
  (let* ((root (make-temp-file "org-seq-daily-content-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (file (expand-file-name "daily/2026-07-14.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory file) t)
          (with-current-buffer (find-file-noselect file)
            (erase-buffer)
            (insert "#+title: 2026-07-14\n\n* 09:00 Existing note\n")
            (org-mode)
            (my/daily--prepare-node)
            (should (= (how-many "^\\* " (point-min) (point-max)) 2))
            (should (org-entry-get nil "ID"))
            (kill-buffer (current-buffer))))
      (delete-directory root t))))

(ert-deftest my/daily-save-schedules-supertag-sync ()
  (let (scheduled)
    (cl-letf (((symbol-function 'my/supertag-schedule-sync)
               (lambda () (setq scheduled t))))
      (with-temp-buffer
        (my/daily-note-mode 1)
        (run-hooks 'after-save-hook)
        (should scheduled)))))
```

- [ ] **Step 2: Run the Daily suite and verify red state**

Expected: failures for undefined node preparation and minor mode.

- [ ] **Step 3: Implement node preparation and buffer-local sync**

Add to `init-daily.el`:

```elisp
(require 'org-id)

(defun my/daily--allowed-blank-property-p (property)
  "Return non-nil when PROPERTY is metadata allowed on a blank node."
  (member (car property) '("ID" "CATEGORY")))

(defun my/daily--blank-node-at-point-p ()
  "Return non-nil when point is on a reusable Daily capture node."
  (and (= (org-outline-level) 1)
       (string-match-p "\\`[0-9][0-9]:[0-9][0-9]\\'"
                       (string-trim (org-get-heading t t t t)))
       (null (org-get-tags nil t))
       (cl-every #'my/daily--allowed-blank-property-p
                 (org-entry-properties nil 'standard))
       (save-excursion
         (org-end-of-meta-data t)
         (let ((begin (point))
               (end (save-excursion (org-end-of-subtree t t))))
           (string-empty-p
            (string-trim (buffer-substring-no-properties begin end)))))))

(defun my/daily--final-blank-node-marker ()
  "Return a marker for the final reusable Daily node, or nil."
  (org-with-wide-buffer
   (goto-char (point-max))
   (when (re-search-backward org-heading-regexp nil t)
     (when (my/daily--blank-node-at-point-p)
       (copy-marker (line-beginning-position))))))

(defun my/daily--insert-node ()
  "Append a top-level timestamp node and return its marker."
  (goto-char (point-max))
  (unless (bolp) (insert "\n"))
  (unless (or (= (point) (point-min))
              (save-excursion (forward-line -1) (looking-at-p "^$")))
    (insert "\n"))
  (insert "* " (format-time-string "%H:%M"))
  (let ((marker (copy-marker (line-beginning-position))))
    (org-id-get-create)
    marker))

(defun my/daily--prepare-node ()
  "Reuse or create one capture-ready node and return its marker."
  (unless (my/daily-buffer-p)
    (user-error "Current buffer is not a Daily Note"))
  (unless (file-writable-p (or buffer-file-name default-directory))
    (user-error "Daily Note is not writable: %s" buffer-file-name))
  (let ((marker (or (my/daily--final-blank-node-marker)
                    (save-excursion (my/daily--insert-node)))))
    (goto-char marker)
    (org-back-to-heading t)
    (end-of-line)
    (unless (eq (char-before) ?\s) (insert " "))
    (save-buffer)
    marker))

(defun my/daily--schedule-supertag-sync ()
  "Request existing debounced supertag sync without breaking save."
  (when (fboundp 'my/supertag-schedule-sync)
    (condition-case err
        (my/supertag-schedule-sync)
      (error
       (message "WARNING org-seq: Daily supertag sync failed: %s" err)))))

(define-minor-mode my/daily-note-mode
  "Minor mode for org-seq Daily Notes."
  :lighter " Daily"
  (if my/daily-note-mode
      (add-hook 'after-save-hook #'my/daily--schedule-supertag-sync nil t)
    (remove-hook 'after-save-hook #'my/daily--schedule-supertag-sync t)))

(defun my/daily--maybe-enable-note-mode ()
  "Enable `my/daily-note-mode' for files in the dailies directory."
  (when (my/daily-buffer-p)
    (my/daily-note-mode 1)))

(add-hook 'org-mode-hook #'my/daily--maybe-enable-note-mode)
```

- [ ] **Step 4: Run tests and byte compilation**

Run Task 1's focused ERT and byte-compilation commands.

Expected: all Daily tests pass; no new compiler warning or `.elc` remains.

- [ ] **Step 5: Commit capture-node behavior**

```powershell
git add lisp/init-daily.el scripts/test-init-daily.el
git diff --cached --check
git commit -m "feat: add Daily capture nodes"
```

---

### Task 3: Dedicated Daily Sidebar

**Files:**
- Modify: `lisp/init-daily.el`
- Modify: `scripts/test-init-daily.el`

**Interfaces:**
- Consumes: `my/daily-date-records`, sidebar customizations.
- Produces: `my/daily-sidebar-mode`, `my/daily-sidebar-open`, `my/daily-sidebar-close`, `my/daily-sidebar-window`, and `my/daily-sidebar-refresh`.

- [ ] **Step 1: Add failing rendering and idempotency tests**

Append:

```elisp
(ert-deftest my/daily-sidebar-render-is-read-only-and-actionable ()
  (let* ((root (make-temp-file "org-seq-daily-sidebar-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (my/daily--clock (lambda () (encode-time 0 0 12 14 7 2026))))
    (unwind-protect
        (with-current-buffer (get-buffer-create my/daily-sidebar-buffer-name)
          (my/daily-sidebar-mode)
          (my/daily-sidebar-refresh)
          (goto-char (point-min))
          (search-forward "Today")
          (should (get-text-property (1- (point)) 'my/daily-time))
          (should-not (file-exists-p (expand-file-name "daily" root))))
      (when-let ((buffer (get-buffer my/daily-sidebar-buffer-name)))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest my/daily-sidebar-open-is-idempotent ()
  (save-window-excursion
    (let ((first (my/daily-sidebar-open))
          (second (my/daily-sidebar-open)))
      (should (window-live-p first))
      (should (eq first second))
      (should (window-parameter first 'my/daily-sidebar)))))
```

- [ ] **Step 2: Run the focused test and confirm red state**

Expected: missing sidebar variables, mode, refresh, and open functions.

- [ ] **Step 3: Implement the managed side window**

Add:

```elisp
(require 'button)

(defconst my/daily-sidebar-buffer-name "*Daily Notes*"
  "Buffer name for the org-seq Daily sidebar.")

(defvar my/daily--clock #'current-time
  "Function returning the current time; rebound by tests.")

(defvar-local my/daily-sidebar-records nil)

(defvar-keymap my/daily-sidebar-mode-map
  :parent special-mode-map
  "RET" #'my/daily-sidebar-open-at-point
  "t" #'my/daily-workspace-open
  "g" #'my/daily-sidebar-refresh
  "c" #'my/daily-workspace-choose-date
  "q" #'my/daily-sidebar-close)

(define-derived-mode my/daily-sidebar-mode special-mode "Daily-Notes"
  "Major mode for recent Daily Note navigation."
  (setq-local truncate-lines t))

(defun my/daily-sidebar--insert-record (record)
  "Insert one actionable sidebar row for RECORD."
  (insert-text-button
   (format "%s %-10s %s"
           (if (plist-get record :exists) "*" ".")
           (plist-get record :label)
           (plist-get record :date))
   'follow-link t
   'my/daily-time (plist-get record :time)
   'action (lambda (button)
             (my/daily-workspace-open-date
              (button-get button 'my/daily-time))))
  (insert "\n"))

(defun my/daily-sidebar-refresh ()
  "Refresh the Daily sidebar without creating note files."
  (interactive)
  (let ((buffer (get-buffer-create my/daily-sidebar-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'my/daily-sidebar-mode)
        (my/daily-sidebar-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Daily Notes\n\n")
        (setq my/daily-sidebar-records
              (my/daily-date-records (funcall my/daily--clock)))
        (dolist (record my/daily-sidebar-records)
          (my/daily-sidebar--insert-record record))
        (insert "\nRET open   t today   c calendar   g refresh\n")
        (goto-char (point-min))))
    buffer))

(defun my/daily-sidebar-window ()
  "Return the live Daily sidebar window in the selected frame."
  (cl-find-if (lambda (window)
                (window-parameter window 'my/daily-sidebar))
              (window-list nil 'no-minibuffer)))

(defun my/daily-sidebar-open ()
  "Open or reuse the persistent Daily sidebar and return its window."
  (interactive)
  (my/daily-sidebar-refresh)
  (or (my/daily-sidebar-window)
      (let ((window
             (display-buffer-in-side-window
              (get-buffer my/daily-sidebar-buffer-name)
              `((side . left) (slot . -2)
                (window-width . ,my/daily-sidebar-width)))))
        (set-window-parameter window 'my/daily-sidebar t)
        (set-window-dedicated-p window t)
        window)))

(defun my/daily-sidebar-close ()
  "Close only the org-seq Daily sidebar in the selected frame."
  (interactive)
  (when-let ((window (my/daily-sidebar-window)))
    (delete-window window)))

(defun my/daily-sidebar-open-at-point ()
  "Open the Daily date represented at point."
  (interactive)
  (if-let ((time (get-text-property (point) 'my/daily-time)))
      (my/daily-workspace-open-date time)
    (user-error "No Daily date at point")))
```

Declare the Task 4 workspace commands before the keymap so byte compilation is explicit.

- [ ] **Step 4: Run sidebar tests and compilation**

Expected: sidebar tests pass, repeated open returns one window, and rendering leaves the temporary dailies directory absent.

- [ ] **Step 5: Commit the sidebar**

```powershell
git add lisp/init-daily.el scripts/test-init-daily.el
git diff --cached --check
git commit -m "feat: add Daily navigation sidebar"
```

---

### Task 4: Daily Workspace And Startup Integration

**Files:**
- Modify: `lisp/init-daily.el`
- Modify: `scripts/test-init-daily.el`
- Modify: `init.el`
- Modify: `lisp/init-workspace.el`
- Modify: `lisp/init-dashboard.el`
- Modify: `scripts/test-provenance.el`

**Interfaces:**
- Consumes: `my/org-roam-dailies-open-date`, sidebar functions, node preparation, and workspace sidebar APIs.
- Produces: `my/daily-workspace-open`, `my/daily-workspace-open-date`, `my/daily-workspace-choose-date`, `my/daily-new-node`, `my/daily-initial-buffer`, and Daily-aware startup transitions.

- [ ] **Step 1: Add failing workspace tests**

Append:

```elisp
(defun my/test-daily-open-date (time)
  "Create and visit a temporary Daily file for TIME."
  (let ((file (my/daily--file-for-time time)))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (write-region
       (format "#+title: %s\n#+filetags: :daily:\n\n"
               (format-time-string "%Y-%m-%d" time))
       nil file nil 'silent))
    (find-file file)))

(ert-deftest my/daily-workspace-existing-history-is-browse-only ()
  (let* ((root (make-temp-file "org-seq-daily-history-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (time (encode-time 0 0 12 13 7 2026))
         (file (expand-file-name "daily/2026-07-13.org" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory file) t)
          (write-region "#+title: 2026-07-13\n\n* 09:00 Existing\n"
                        nil file nil 'silent)
          (cl-letf (((symbol-function 'my/org-roam-dailies-open-date)
                     #'my/test-daily-open-date)
                    ((symbol-function 'my/daily-sidebar-open) #'ignore))
            (my/daily-workspace-open-date time))
          (with-current-buffer (find-buffer-visiting file)
            (should (= (how-many "^\\* " (point-min) (point-max)) 1))))
      (when-let ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest my/daily-workspace-missing-date-creates-first-node ()
  (let* ((root (make-temp-file "org-seq-daily-create-" t))
         (my/roam-dir (file-name-as-directory root))
         (org-roam-dailies-directory "daily/")
         (time (encode-time 0 0 12 12 7 2026))
         (file (expand-file-name "daily/2026-07-12.org" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'my/org-roam-dailies-open-date)
                   #'my/test-daily-open-date)
                  ((symbol-function 'my/daily-sidebar-open) #'ignore))
          (my/daily-workspace-open-date time)
          (should (file-exists-p file))
          (with-current-buffer (find-buffer-visiting file)
            (should (= (how-many "^\\* " (point-min) (point-max)) 1))
            (should (org-entry-get nil "ID"))))
      (when-let ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory root t))))
```

Extend `scripts/test-provenance.el` so the expected sequence contains `init-supertag`, `init-daily`, `init-terminal`.

- [ ] **Step 2: Run Daily and provenance suites and verify red state**

Expected: workspace commands are undefined and `init-daily` is absent from `init.el`.

- [ ] **Step 3: Implement workspace commands with an editor-window boundary**

Add:

```elisp
(declare-function my/org-roam-dailies-open-date "init-roam" (time))
(declare-function my/workspace-close-treemacs "init-workspace" ())

(defun my/daily--editor-window ()
  "Return a non-side editor window in the selected frame."
  (or (cl-find-if (lambda (window)
                    (not (window-parameter window 'window-side)))
                  (window-list nil 'no-minibuffer))
      (selected-window)))

(defun my/daily--visit-date (time)
  "Visit TIME through the existing org-roam dailies boundary."
  (let ((file (my/daily--file-for-time time)))
    (when (and (not (file-exists-p file))
               (file-exists-p my/roam-dir)
               (not (file-writable-p my/roam-dir)))
      (user-error "Roam directory is not writable: %s" my/roam-dir))
    (my/org-roam-dailies-open-date time)
    (my/daily-note-mode 1)
    (current-buffer)))

(defun my/daily-workspace-open-date (time &optional capture-ready)
  "Open TIME in the Daily Workspace.
Existing history is browse-only unless CAPTURE-READY is non-nil."
  (interactive (list (current-time) current-prefix-arg))
  (let* ((file (my/daily--file-for-time time))
         (missing (not (file-exists-p file))))
    (when (fboundp 'my/workspace-close-treemacs)
      (my/workspace-close-treemacs))
    (select-window (my/daily--editor-window))
    (let ((buffer (my/daily--visit-date time)))
      (switch-to-buffer buffer)
      (when (or capture-ready missing)
        (my/daily--prepare-node))
      (my/daily-sidebar-open)
      (my/daily-sidebar-refresh)
      buffer)))

(defun my/daily-workspace-open ()
  "Open Today's capture-ready Daily Workspace."
  (interactive)
  (my/daily-workspace-open-date
   (current-time) my/daily-auto-prepare-today))

(defun my/daily-workspace-choose-date ()
  "Choose a date and open its Daily Workspace."
  (interactive)
  (my/daily-workspace-open-date (org-read-date nil t)))

(defun my/daily-new-node ()
  "Prepare a node in the current Daily Note, opening Today if needed."
  (interactive)
  (unless (my/daily-buffer-p)
    (my/daily-workspace-open))
  (my/daily--prepare-node))

(defun my/daily-initial-buffer ()
  "Return Today's capture-ready buffer without opening a sidebar."
  (let ((buffer (save-window-excursion
                  (my/daily--visit-date (current-time)))))
    (with-current-buffer buffer
      (when my/daily-auto-prepare-today
        (my/daily--prepare-node)))
    buffer))
```

- [ ] **Step 4: Register the module and integrate startup/sidebar transitions**

Insert `init-daily` after `init-supertag` in `init.el` module data and comment.

In `init-workspace.el`, add:

```elisp
(declare-function my/daily-buffer-p "init-daily" (&optional buffer))
(declare-function my/daily-initial-buffer "init-daily" ())
(declare-function my/daily-sidebar-close "init-daily" ())
(declare-function my/daily-workspace-open "init-daily" ())

(defun my/workspace-close-treemacs ()
  "Close only the current frame's Treemacs window."
  (when-let ((window (my/workspace-sidebar-visible-p)))
    (delete-window window)))
```

Call `my/daily-sidebar-close` at the beginning of `my/workspace-open-sidebar` and `my/workspace-setup`. Set:

```elisp
(setq initial-buffer-choice #'my/daily-initial-buffer)
```

In `my/workspace-startup`, branch before existing Treemacs mutations: if `target-buffer` satisfies `my/daily-buffer-p`, switch to it and call `my/daily-workspace-open`; otherwise execute the existing body unchanged.

Remove only the old Dashboard-owned `initial-buffer-choice` assignment from `init-dashboard.el`; keep `dashboard-setup-startup-hook`.

- [ ] **Step 5: Run focused and startup checks**

```powershell
& "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" --batch -Q `
  -L . -L lisp -l scripts/test-init-daily.el `
  -f ert-run-tests-batch-and-exit

& "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" --batch -Q `
  -L . -L lisp -l scripts/test-provenance.el `
  -f ert-run-tests-batch-and-exit

pwsh -NoLogo -NoProfile -File scripts/check.ps1 `
  -EmacsPath "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" `
  -SkipErt
```

Expected: focused suites, full compile, and batch startup pass; no `.elc` remains.

- [ ] **Step 6: Commit workspace integration**

```powershell
git add init.el lisp/init-daily.el lisp/init-workspace.el `
  lisp/init-dashboard.el scripts/test-init-daily.el scripts/test-provenance.el
git diff --cached --check
git commit -m "feat: make Daily Notes the default workspace"
```

---

### Task 5: Dashboard And Leader-Key Contracts

**Files:**
- Modify: `lisp/init-dashboard.el`
- Modify: `lisp/init-keymap.el`
- Modify: `lisp/init-evil.el`
- Modify: `scripts/test-init-keymap.el`
- Modify: `scripts/test-provenance.el`

**Interfaces:**
- Consumes: Daily date and workspace APIs.
- Produces: Dashboard `daily` generator; effective `SPC n d d` and `SPC n d a`; keymap audit coverage.

- [ ] **Step 1: Add failing keymap and Dashboard contract tests**

Extend `scripts/test-init-keymap.el` expected critical pairs with:

```elisp
("ndd" . my/daily-workspace-open)
("nda" . my/daily-new-node)
```

Add provenance assertions that `init-dashboard.el` orders `(daily . 5)` before `(recents . 5)` and calls `my/daily-workspace-open` from Today.

- [ ] **Step 2: Run focused suites and verify failure**

Expected: the new critical metadata and Dashboard generator are absent.

- [ ] **Step 3: Implement the Daily Dashboard section**

Declare the Daily APIs at the top of `init-dashboard.el`, then register this generator inside dashboard configuration:

```elisp
(defun my/dashboard-insert-dailies (list-size)
  "Insert LIST-SIZE recent calendar dates into Dashboard."
  (let ((items
         (mapcar
          (lambda (record)
            (propertize
             (format "%s  %s"
                     (plist-get record :label)
                     (plist-get record :date))
             'my/daily-time (plist-get record :time)))
          (my/daily-date-records nil list-size))))
    (dashboard-insert-section
     "Daily Notes:" items list-size 'daily
     (dashboard-get-shortcut 'daily)
     `(lambda (&rest _)
        (my/daily-workspace-open-date
         (get-text-property 0 'my/daily-time ,el)))
     el)))

(setf (alist-get 'daily dashboard-item-generators)
      #'my/dashboard-insert-dailies)
(setq dashboard-items '((daily . 5) (recents . 5))
      dashboard-item-shortcuts '((daily . "d") (recents . "r")))
```

Change only the navigator Today callback to `my/daily-workspace-open`.

- [ ] **Step 4: Add metadata and actual Evil bindings**

In `init-keymap.el` add:

```elisp
(:key "ndd" :command my/daily-workspace-open
 :description "Daily workspace")
(:key "nda" :command my/daily-new-node
 :description "Append Daily node")
```

In the existing `SPC n d` block of `init-evil.el` use:

```elisp
"ndd" '(my/daily-workspace-open :wk "Daily workspace")
"nda" '(my/daily-new-node :wk "Append node")
```

Keep `ndy`, `ndT`, `ndf`, `ndc`, `ndC`, `ndp`, and `ndn` unchanged.

- [ ] **Step 5: Run focused and strict keymap checks**

```powershell
pwsh -NoLogo -NoProfile -File scripts/check.ps1 `
  -EmacsPath "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" `
  -PackageUserDir "C:\Users\exrld\.emacs.d\elpa" `
  -RequireAllModules -RequireDependencies `
  -SkipCompile
```

Expected: no module or keymap failure; only optional tool warnings may remain.

- [ ] **Step 6: Commit Dashboard and keymaps**

```powershell
git add lisp/init-dashboard.el lisp/init-keymap.el lisp/init-evil.el `
  scripts/test-init-keymap.el scripts/test-provenance.el
git diff --cached --check
git commit -m "feat: expose Daily-first navigation"
```

---

### Task 6: Documentation And Full Completion Gate

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `AGENTS.md`
- Modify: `doc/CORE_ARCHITECTURE.md`
- Modify: `doc/WORKFLOW.md`
- Modify: `doc/GUIDE.md`
- Modify: `doc/TUTORIAL.md`
- Modify: `doc/specs/2026-07-14-daily-workspace-design.md`

**Interfaces:**
- Consumes: verified runtime behavior and final commands.
- Produces: synchronized user workflow, load order, architecture boundary, and completion evidence.

- [ ] **Step 1: Update user-facing workflow documentation**

Apply these exact content changes:

- README Quick Start says startup opens Today's Daily Workspace.
- README module table includes `init-daily.el` after `init-supertag.el`.
- README documents `SPC n d d`, `SPC n d a`, sidebar `RET/t/g/c/q`, `SPC l d`, and `SPC l l`.
- WORKFLOW defines the rhythm: capture in Today, add supertags later, use the Daily sidebar for recent dates, and switch to Treemacs for library navigation.
- GUIDE explains the Daily file container and top-level ID node model.
- TUTORIAL starts with a Daily capture and then adds a supertag field.
- CORE_ARCHITECTURE distinguishes the persistent Daily sidebar from popup rules and Treemacs.

- [ ] **Step 2: Update contributor contracts and design status**

Add `init-daily` to load-order strings in `AGENTS.md` and `CONTRIBUTING.md`. Document that sidebar rendering is read-only and tests use temporary NoteHQ roots.

After both validation modes pass, change design status to:

```markdown
## Status

Implemented and verified on 2026-07-14 with Emacs 30.2 in both isolated and
strict deployed validation modes.
```

- [ ] **Step 3: Run complete isolated validation**

```powershell
pwsh -NoLogo -NoProfile -File scripts/check.ps1 `
  -EmacsPath "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe"
```

Expected: exit zero; ERT, full byte compilation, and batch startup pass. Missing deployed packages remain isolated-mode warnings.

- [ ] **Step 4: Run complete strict deployed validation**

```powershell
pwsh -NoLogo -NoProfile -File scripts/check.ps1 `
  -EmacsPath "C:\Program Files\Emacs\emacs-30.2\bin\emacs.exe" `
  -PackageUserDir "C:\Users\exrld\.emacs.d\elpa" `
  -RequireAllModules -RequireDependencies
```

Expected: exit zero; no failed module, required doctor check, or critical key. Only explicitly optional tool warnings may remain.

- [ ] **Step 5: Audit artifacts and diff**

```powershell
git diff --check
git status --short
rg --files -g "*.elc"
rg -n "init-supertag.*init-daily.*init-terminal" init.el AGENTS.md CONTRIBUTING.md
rg -n "Daily Workspace|SPC n d a|SPC n d d" `
  README.md doc/WORKFLOW.md doc/GUIDE.md doc/TUTORIAL.md
```

Expected: no diff error or `.elc`; only intended files are modified. Review the full diff for secrets, user-note paths, generated files, unrelated formatting, and package-source edits.

- [ ] **Step 6: Commit documentation**

```powershell
git add README.md CONTRIBUTING.md AGENTS.md doc/CORE_ARCHITECTURE.md `
  doc/WORKFLOW.md doc/GUIDE.md doc/TUTORIAL.md `
  doc/specs/2026-07-14-daily-workspace-design.md
git diff --cached --check
git commit -m "docs: document Daily-first workflow"
```

- [ ] **Step 7: Confirm clean final state**

```powershell
git status --short
git log --oneline --decorate -8
```

Expected: empty status and focused Daily Workspace commits. Do not push or deploy unless the user separately requests it.
