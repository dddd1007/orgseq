;;; test-init-python.el --- Tests for Python environment paths -*- lexical-binding: t; -*-

(require 'ert)

(load-file
 (expand-file-name "../lisp/init-python.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/python-environment-root-keeps-windows-conda-root ()
  (let ((system-type 'windows-nt))
    (should
     (string-equal-ignore-case
      (my/python--environment-root
       "C:/Users/me/miniconda3/python.exe")
      "C:/Users/me/miniconda3/"))))

(ert-deftest my/python-environment-root-strips-posix-bin-directory ()
  (let ((system-type 'gnu/linux))
    (should
     (equal (my/python--environment-root
             "/home/me/miniconda3/bin/python")
            "/home/me/miniconda3/"))))

;;; test-init-python.el ends here
