;;; init-python.el --- Shared Python runtime selection -*- lexical-binding: t; -*-

;; Prefer a local Anaconda/Miniconda Python for scientific computing.  When no
;; conda-style Python is found, optionally use a uv-managed virtualenv under
;; `user-emacs-directory'.  Other modules consume `my/python-command' instead
;; of rediscovering Python independently.

(defcustom my/python-prefer-conda t
  "When non-nil, prefer Anaconda/Miniconda Python over PATH Python."
  :type 'boolean
  :group 'org-seq)

(defcustom my/python-auto-create-uv-env t
  "When non-nil, create `my/python-uv-env-dir' with uv if no conda Python exists.

The creation is skipped in noninteractive batch sessions."
  :type 'boolean
  :group 'org-seq)

(defcustom my/python-uv-env-dir
  (expand-file-name ".venv/" user-emacs-directory)
  "Fallback uv-managed Python virtualenv directory for org-seq integrations."
  :type 'directory
  :group 'org-seq)

(defcustom my/python-extra-conda-roots nil
  "Additional Anaconda/Miniconda roots to check before built-in defaults."
  :type '(repeat directory)
  :group 'org-seq)

(defvar my/python-command nil
  "Selected Python executable for org-seq integrations.")

(defvar my/python-source nil
  "Source of `my/python-command', one of `conda', `uv', `path', or nil.")

(defun my/python--windows-executable (root)
  "Return Python executable below conda/venv ROOT on Windows."
  (expand-file-name "python.exe" root))

(defun my/python--posix-executable (root)
  "Return Python executable below conda/venv ROOT on POSIX systems."
  (expand-file-name "bin/python" root))

(defun my/python--venv-executable (root)
  "Return Python executable for environment ROOT."
  (if (eq system-type 'windows-nt)
      (my/python--windows-executable root)
    (my/python--posix-executable root)))

(defun my/python--candidate-conda-roots ()
  "Return possible Anaconda/Miniconda roots in preference order."
  (let ((home-roots (list
                     (expand-file-name "miniconda3" "~")
                     (expand-file-name "anaconda3" "~")
                     (expand-file-name "mambaforge" "~")
                     (expand-file-name "miniforge3" "~")))
        (windows-roots (when (eq system-type 'windows-nt)
                         (list
                          (expand-file-name "AppData/Local/miniconda3" "~")
                          (expand-file-name "AppData/Local/anaconda3" "~")
                          (expand-file-name "AppData/Local/mambaforge" "~")
                          (expand-file-name "AppData/Local/miniforge3" "~")
                          "C:/ProgramData/miniconda3"
                          "C:/ProgramData/anaconda3"))))
    (delq nil
          (append my/python-extra-conda-roots
                  (when-let ((prefix (getenv "CONDA_PREFIX")))
                    (list prefix))
                  home-roots
                  windows-roots))))

(defun my/python--find-conda-python ()
  "Return the first local conda-style Python executable, or nil."
  (when my/python-prefer-conda
    (catch 'found
      (dolist (root (my/python--candidate-conda-roots))
        (let ((python (my/python--venv-executable root)))
          (when (file-executable-p python)
            (throw 'found python)))))))

(defun my/python--uv-python ()
  "Return uv-managed fallback Python executable when it exists."
  (let ((python (my/python--venv-executable my/python-uv-env-dir)))
    (and (file-executable-p python) python)))

(defun my/python--create-uv-env ()
  "Create `my/python-uv-env-dir' with uv and return its Python, or nil."
  (when (and my/python-auto-create-uv-env
             (not noninteractive)
             (executable-find "uv"))
    (make-directory (file-name-directory
                     (directory-file-name my/python-uv-env-dir))
                    t)
    (let ((exit-code (call-process "uv" nil nil nil
                                   "venv" my/python-uv-env-dir)))
      (when (zerop exit-code)
        (my/python--uv-python)))))

(defun my/python--path-python ()
  "Return a PATH Python executable as final fallback."
  (or (executable-find "python")
      (executable-find "python3")))

(defun my/python--prepend-env-paths (python source)
  "Prepend environment paths for PYTHON from SOURCE to PATH and `exec-path'."
  (when (and python (fboundp 'my/prepend-to-exec-path))
    (let ((root (file-name-directory
                 (directory-file-name
                  (file-name-directory python)))))
      (pcase source
        ('conda
         (dolist (dir (reverse
                       (if (eq system-type 'windows-nt)
                           (list root
                                 (expand-file-name "Scripts" root)
                                 (expand-file-name "Library/bin" root)
                                 (expand-file-name "Library/usr/bin" root))
                         (list (expand-file-name "bin" root) root))))
           (my/prepend-to-exec-path dir)))
        ('uv
         (my/prepend-to-exec-path
          (file-name-directory (directory-file-name python))))))))

(defun my/python-detect (&optional force)
  "Select Python for org-seq integrations.

With FORCE, recompute even when `my/python-command' is already set."
  (interactive "P")
  (when (or force (not my/python-command))
    (setq my/python-command nil
          my/python-source nil)
    (let ((conda-python (my/python--find-conda-python)))
      (cond
       (conda-python
        (setq my/python-command conda-python
              my/python-source 'conda))
       ((or (my/python--uv-python)
            (my/python--create-uv-env))
        (setq my/python-command (my/python--uv-python)
              my/python-source 'uv))
       ((my/python--path-python)
        (setq my/python-command (my/python--path-python)
              my/python-source 'path))))
    (when my/python-command
      (setq my/python-command (file-truename my/python-command))
      (my/python--prepend-env-paths my/python-command my/python-source)))
  (when (called-interactively-p 'interactive)
    (message "org-seq Python: %s (%s)"
             (or my/python-command "not found")
             (or my/python-source "none")))
  my/python-command)

(defun my/python-info ()
  "Display selected Python runtime information."
  (interactive)
  (my/python-detect)
  (let ((buf (get-buffer-create "*org-seq Python*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Python command: %s\n" (or my/python-command "not found")))
        (insert (format "Source: %s\n" (or my/python-source "none")))
        (insert (format "uv env: %s\n" (file-truename my/python-uv-env-dir)))
        (when my/python-command
          (insert "\nRuntime:\n")
          (let ((output (with-output-to-string
                          (call-process my/python-command nil standard-output nil
                                        "-c" "import sys, site; print(sys.version); print(sys.executable); print(site.getusersitepackages())"))))
            (insert output)))
        (special-mode)))
    (pop-to-buffer buf)))

(my/python-detect)

(provide 'init-python)
;;; init-python.el ends here
