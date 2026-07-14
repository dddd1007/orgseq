;;; init-packages.el --- Git package inventory and bootstrap -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

(declare-function package-installed-p "package" (package &optional min-version))
(declare-function package-vc-install "package-vc" (spec &optional rev backend))

(defcustom my/vc-package-specs
  '((:package modusregel
     :library "modusregel"
     :url "https://codeberg.org/jjba23/modusregel.git"
     :owner init-ui
     :purpose "Mode-line implementation")
    (:package org-modern-indent
     :library "org-modern-indent"
     :url "https://github.com/jdtsmith/org-modern-indent"
     :owner init-org
     :purpose "Org indentation rendering")
    (:package org-supertag
     :library "org-supertag"
     :url "https://github.com/yibie/org-supertag"
     :owner init-pkm
     :purpose "Structured note metadata")
    (:package ob-gptel
     :library "ob-gptel"
     :url "https://github.com/jwiegley/ob-gptel"
     :owner init-ai
     :purpose "Org Babel gptel blocks")
    (:package claude-code
     :library "claude-code"
     :url "https://github.com/stevemolitor/claude-code.el"
     :owner init-ai-cli
     :purpose "Claude Code integration"))
  "Git-hosted package inventory owned by org-seq.

Each record declares a package symbol, loadable library, source URL, owning
configuration module, and purpose. Package configuration remains in the owner
module; this inventory owns only source metadata, bootstrap, and audit state."
  :type '(repeat sexp)
  :group 'org-seq)

(defvar my/vc-package-install-errors nil
  "Alist of package symbols and errors from the current Emacs session.")

(defun my/vc-package-spec (package)
  "Return the registered specification for PACKAGE, or nil."
  (cl-find package my/vc-package-specs
           :key (lambda (spec) (plist-get spec :package))))

(defun my/vc-package--available-p (spec)
  "Return non-nil when package SPEC is installed or loadable."
  (or (package-installed-p (plist-get spec :package))
      (locate-library (plist-get spec :library))))

(defun my/vc-package-install-error (package)
  "Return the last installation error recorded for PACKAGE."
  (cdr (assq package my/vc-package-install-errors)))

(defun my/vc-package-install-command (package)
  "Return an interactive package-vc command hint for PACKAGE."
  (let ((spec (or (my/vc-package-spec package)
                  (user-error "Unregistered VC package: %s" package))))
    (format "M-x package-vc-install RET %s RET"
            (plist-get spec :url))))

(defun my/vc-package-ensure (package)
  "Ensure registered PACKAGE is available without batch network access.

Return `present', `skipped', `installed', or `failed'. Installation errors are
recorded in `my/vc-package-install-errors' instead of aborting startup."
  (let ((spec (or (my/vc-package-spec package)
                  (user-error "Unregistered VC package: %s" package))))
    (cond
     ((my/vc-package--available-p spec) 'present)
     (noninteractive
      (message "org-seq: skipping %s bootstrap in noninteractive session"
               package)
      'skipped)
     (t
      (condition-case err
          (progn
            (package-vc-install (plist-get spec :url))
            (setq my/vc-package-install-errors
                  (assq-delete-all package my/vc-package-install-errors))
            'installed)
        (error
         (setf (alist-get package my/vc-package-install-errors) err)
         (message "WARNING org-seq: failed to install %s: %s" package err)
         'failed))))))

(defun my/vc-package-statuses ()
  "Return read-only status plists for every registered Git package."
  (mapcar
   (lambda (spec)
     (let* ((package (plist-get spec :package))
            (error-value (my/vc-package-install-error package)))
       (append
        (list :package package
              :status (cond
                       ((my/vc-package--available-p spec) 'present)
                       (error-value 'failed)
                       (t 'missing))
              :error error-value)
        spec)))
   my/vc-package-specs))

(defun my/vc-package-audit ()
  "Display registered Git package sources, ownership, and local status."
  (interactive)
  (let ((buffer (get-buffer-create "*org-seq package audit*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "org-seq Git package inventory\n\n")
        (dolist (status (my/vc-package-statuses))
          (insert
           (format "%-7s %-20s owner=%-12s %s\n"
                   (upcase (symbol-name (plist-get status :status)))
                   (plist-get status :package)
                   (plist-get status :owner)
                   (plist-get status :url))))
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer buffer)))

(provide 'init-packages)
;;; init-packages.el ends here
