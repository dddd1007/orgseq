;;; init-doctor.el --- org-seq diagnostics and startup report -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

(defvar my/--init-errors nil)
(defvar my/--init-results nil)
(defvar my/note-home)
(defvar my/terminal-popup-command)
(defvar my/codex-command)
(defvar my/opencode-command)
(defvar my/kimi-cli-command)

(declare-function my/init-results "init" ())
(declare-function my/vc-package-statuses "init-packages" ())

(defvar my/doctor-checks nil
  "Ordered doctor check specifications.
Each entry contains :id, :label, and :check keys.")

(defun my/doctor--payload (status detail &optional remedy)
  "Build a check payload with STATUS, DETAIL, and optional REMEDY."
  (list :status status :detail detail :remedy remedy))

(defun my/doctor--result (spec payload)
  "Combine check SPEC and PAYLOAD into one public result."
  (list :id (plist-get spec :id)
        :label (plist-get spec :label)
        :status (plist-get payload :status)
        :detail (plist-get payload :detail)
        :remedy (plist-get payload :remedy)))

(defun my/doctor--run-one (spec)
  "Run one doctor check SPEC without aborting the complete report."
  (condition-case err
      (let ((payload (funcall (plist-get spec :check))))
        (unless (memq (plist-get payload :status) '(pass warn fail))
          (error "Invalid doctor status: %S" (plist-get payload :status)))
        (my/doctor--result spec payload))
    (error
     (my/doctor--result
      spec
      (my/doctor--payload
       'fail
       (format "Check failed: %s" (error-message-string err))
       "Inspect the check implementation or run it with debug-on-error.")))))

(defun my/doctor-run ()
  "Run every configured org-seq doctor check and return result plists."
  (mapcar #'my/doctor--run-one my/doctor-checks))

(defun my/doctor--status-label (status)
  "Return an aligned ASCII label for STATUS."
  (pcase status
    ('pass "PASS")
    ('warn "WARN")
    ('fail "FAIL")
    (_ "UNKN")))

(defun my/doctor-render (results)
  "Render doctor RESULTS and return the report buffer."
  (let ((buffer (get-buffer-create "*org-seq doctor*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "org-seq doctor\n\n")
        (dolist (result results)
          (insert (format "%s  %s\n"
                          (my/doctor--status-label
                           (plist-get result :status))
                          (plist-get result :label)))
          (insert (format "      %s\n" (plist-get result :detail)))
          (when-let ((remedy (plist-get result :remedy)))
            (insert (format "      Remedy: %s\n" remedy)))
          (insert "\n"))
        (goto-char (point-min))
        (special-mode)))
    buffer))

(defun my/doctor ()
  "Run org-seq diagnostics and display the report."
  (interactive)
  (pop-to-buffer (my/doctor-render (my/doctor-run))))

(defun my/init-report-render (results)
  "Render module load RESULTS and return the report buffer."
  (let ((buffer (get-buffer-create "*org-seq init report*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "org-seq module load report\n\n")
        (dolist (result results)
          (insert
           (format "%-6s %7.3f s  %s\n"
                   (upcase (symbol-name (plist-get result :status)))
                   (plist-get result :elapsed)
                   (plist-get result :module)))
          (when-let ((err (plist-get result :error)))
            (insert (format "                    %s\n"
                            (error-message-string err)))))
        (goto-char (point-min))
        (special-mode)))
    buffer))

(defun my/init-report ()
  "Display org-seq module status and load timings."
  (interactive)
  (pop-to-buffer
   (my/init-report-render
    (if (fboundp 'my/init-results)
        (my/init-results)
      (reverse (copy-sequence my/--init-results))))))

(defun my/doctor--check-emacs-version ()
  "Check the supported Emacs version."
  (if (>= emacs-major-version 30)
      (my/doctor--payload 'pass (format "Emacs %s" emacs-version))
    (my/doctor--payload
     'fail
     (format "Emacs %s; org-seq requires 30+" emacs-version)
     "Install Emacs 30 or newer and rerun the doctor.")))

(defun my/doctor--check-sqlite ()
  "Check built-in SQLite support."
  (if (and (fboundp 'sqlite-available-p) (sqlite-available-p))
      (my/doctor--payload 'pass "SQLite support is available")
    (my/doctor--payload
     'fail
     "SQLite support is unavailable"
     "Use an Emacs 30+ build compiled with SQLite support.")))

(defun my/doctor--check-dynamic-modules ()
  "Check dynamic-module support required by Ghostel."
  (if module-file-suffix
      (my/doctor--payload
       'pass (format "Dynamic modules use %s" module-file-suffix))
    (my/doctor--payload
     'fail
     "Dynamic modules are unavailable"
     "Install an Emacs build with dynamic module support for Ghostel.")))

(defun my/doctor--check-note-home ()
  "Check the configured NoteHQ root without creating it."
  (cond
   ((not (and (stringp my/note-home)
              (not (string-empty-p my/note-home))))
    (my/doctor--payload
     'fail "my/note-home is not defined"
     "Inspect init-org with M-x my/init-errors."))
   ((file-directory-p my/note-home)
    (my/doctor--payload 'pass (format "Directory: %s" my/note-home)))
   (t
    (my/doctor--payload
     'warn (format "Directory does not exist: %s" my/note-home)
     "Run the NoteHQ bootstrap script or M-x my/ensure-notehq-structure."))))

(defun my/doctor--check-module-loads ()
  "Report module load failures recorded by the guarded loader."
  (if my/--init-errors
      (my/doctor--payload
       'fail
       (format "Failed modules: %s"
               (mapconcat (lambda (entry) (symbol-name (car entry)))
                          (reverse my/--init-errors) ", "))
       "Run M-x my/init-errors for the captured error messages.")
    (my/doctor--payload 'pass "All attempted modules loaded")))

(defun my/doctor--check-executable (candidates required remedy)
  "Check executable CANDIDATES.
REQUIRED makes a missing executable a failure instead of a warning."
  (let ((found
         (cl-loop for candidate in candidates
                  when (executable-find candidate)
                  return it)))
    (if found
        (my/doctor--payload 'pass (format "Found: %s" found))
      (my/doctor--payload
       (if required 'fail 'warn)
       (format "Not found: %s" (string-join candidates " or "))
       remedy))))

(defun my/doctor--check-git ()
  "Check Git for Magit and package-vc workflows."
  (my/doctor--check-executable
   '("git") nil "Install Git and make it visible to Emacs."))

(defun my/doctor--check-rg ()
  "Check ripgrep for Consult searches."
  (my/doctor--check-executable
   '("rg") nil "Install ripgrep and make it visible to Emacs."))

(defun my/doctor--check-fd ()
  "Check fd or its Debian executable name."
  (my/doctor--check-executable
   '("fd" "fdfind") nil "Install fd and make it visible to Emacs."))

(defun my/doctor--check-shell ()
  "Check the configured terminal shell command."
  (let ((command (if (boundp 'my/terminal-popup-command)
                     my/terminal-popup-command
                   (if (eq system-type 'windows-nt) "pwsh" shell-file-name))))
    (my/doctor--check-executable
     (list command) t
     "Customize my/terminal-popup-command to an installed shell.")))

(defun my/doctor--check-yazi ()
  "Check optional Yazi integration."
  (my/doctor--check-executable
   '("yazi") nil "Install Yazi to use SPC o y and SPC o Y."))

(defun my/doctor--check-ai-clis ()
  "Check configured optional AI command-line tools."
  (let* ((commands
          (delq nil
                (list (and (boundp 'my/codex-command) my/codex-command)
                      (and (boundp 'my/opencode-command) my/opencode-command)
                      (and (boundp 'my/kimi-cli-command) my/kimi-cli-command))))
         (missing
          (cl-remove-if (lambda (command) (executable-find command)) commands)))
    (if missing
        (my/doctor--payload
         'warn
         (format "Optional AI CLIs not found: %s" (string-join missing ", "))
         "Install only the AI CLIs you intend to use, or customize their commands.")
      (my/doctor--payload 'pass "Configured AI CLIs are available"))))

(defun my/doctor--check-ghostel ()
  "Check Ghostel Elisp availability without downloading its native module."
  (if (locate-library "ghostel")
      (my/doctor--payload 'pass "Ghostel Elisp library is available")
    (my/doctor--payload
     'fail
     "Ghostel Elisp library is unavailable"
     "Install Ghostel through package.el; first use handles the native module.")))

(defun my/doctor--check-vc-packages ()
  "Check registered Git package availability without installing anything."
  (if (not (fboundp 'my/vc-package-statuses))
      (my/doctor--payload
       'warn
       "Git package inventory is unavailable"
       "Inspect init-packages with M-x my/init-errors.")
    (let* ((statuses (my/vc-package-statuses))
           (problems
            (cl-remove-if
             (lambda (status)
               (eq (plist-get status :status) 'present))
             statuses)))
      (if problems
          (my/doctor--payload
           'warn
           (format "Unavailable Git packages: %s"
                   (mapconcat
                    (lambda (status)
                      (symbol-name (plist-get status :package)))
                    problems ", "))
           "Run M-x my/vc-package-audit for sources and ownership.")
        (my/doctor--payload 'pass "All registered Git packages are available")))))

(defun my/doctor--check-active-packages ()
  "Check representative packages required by active core workflows."
  (let* ((libraries '("general" "evil" "org-roam" "org-ql" "org-supertag"))
         (missing (cl-remove-if #'locate-library libraries)))
    (if missing
        (my/doctor--payload
         'warn
         (format "Libraries not found: %s" (string-join missing ", "))
         "Inspect module errors and install missing packages interactively.")
      (my/doctor--payload 'pass "Representative active packages are available"))))

(setq my/doctor-checks
      '((:id emacs-version :label "Emacs version"
         :check my/doctor--check-emacs-version)
        (:id sqlite :label "SQLite"
         :check my/doctor--check-sqlite)
        (:id dynamic-modules :label "Dynamic modules"
         :check my/doctor--check-dynamic-modules)
        (:id note-home :label "NoteHQ root"
         :check my/doctor--check-note-home)
        (:id module-loads :label "Module loading"
         :check my/doctor--check-module-loads)
        (:id ghostel :label "Ghostel"
         :check my/doctor--check-ghostel)
        (:id shell :label "Terminal shell"
         :check my/doctor--check-shell)
        (:id git :label "Git"
         :check my/doctor--check-git)
        (:id ripgrep :label "ripgrep"
         :check my/doctor--check-rg)
        (:id fd :label "fd"
         :check my/doctor--check-fd)
        (:id yazi :label "Yazi"
         :check my/doctor--check-yazi)
        (:id ai-clis :label "AI command-line tools"
         :check my/doctor--check-ai-clis)
        (:id vc-packages :label "Git package inventory"
         :check my/doctor--check-vc-packages)
        (:id packages :label "Active packages"
         :check my/doctor--check-active-packages)))

(provide 'init-doctor)
;;; init-doctor.el ends here
