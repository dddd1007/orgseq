;;; test-init-doctor.el --- Tests for org-seq doctor -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(load-file
 (expand-file-name "../lisp/init-doctor.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/doctor-forward-declaration-does-not-prebind-note-home ()
  (should-not (boundp 'my/note-home)))

(ert-deftest my/doctor-run-preserves-check-order-and-fields ()
  (let ((my/doctor-checks
         '((:id first :label "First" :check my/test-doctor-pass)
           (:id second :label "Second" :check my/test-doctor-warn))))
    (cl-letf (((symbol-function 'my/test-doctor-pass)
               (lambda () '(:status pass :detail "ready" :remedy nil)))
              ((symbol-function 'my/test-doctor-warn)
               (lambda () '(:status warn :detail "missing" :remedy "Install it"))))
      (should
       (equal (my/doctor-run)
              '((:id first :label "First" :status pass
                 :detail "ready" :remedy nil)
                (:id second :label "Second" :status warn
                 :detail "missing" :remedy "Install it")))))))

(ert-deftest my/doctor-run-isolates-a-broken-check ()
  (let ((my/doctor-checks
         '((:id broken :label "Broken" :check my/test-doctor-broken)
           (:id healthy :label "Healthy" :check my/test-doctor-pass))))
    (cl-letf (((symbol-function 'my/test-doctor-broken)
               (lambda () (error "inspection failed")))
              ((symbol-function 'my/test-doctor-pass)
               (lambda () '(:status pass :detail "ready" :remedy nil))))
      (let ((results (my/doctor-run)))
        (should (eq (plist-get (nth 0 results) :status) 'fail))
        (should (string-match-p "inspection failed"
                                (plist-get (nth 0 results) :detail)))
        (should (eq (plist-get (nth 1 results) :status) 'pass))))))

(ert-deftest my/doctor-render-creates-read-only-summary ()
  (let ((buffer
         (my/doctor-render
          '((:id sample :label "Sample" :status warn
             :detail "Not found" :remedy "Install sample")))))
    (unwind-protect
        (with-current-buffer buffer
          (should (derived-mode-p 'special-mode))
          (should buffer-read-only)
          (should (string-match-p "WARN  Sample" (buffer-string)))
          (should (string-match-p "Install sample" (buffer-string))))
      (kill-buffer buffer))))

(ert-deftest my/doctor-executable-check-accepts-alternatives ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (name) (and (equal name "fdfind") "/usr/bin/fdfind"))))
    (should
     (equal (my/doctor--check-executable
             '("fd" "fdfind") nil "Install fd")
            '(:status pass :detail "Found: /usr/bin/fdfind" :remedy nil)))))

(ert-deftest my/doctor-executable-check-classifies-optional-missing-as-warning ()
  (cl-letf (((symbol-function 'executable-find) #'ignore))
    (should
     (equal (my/doctor--check-executable
             '("yazi") nil "Install yazi")
            '(:status warn :detail "Not found: yazi" :remedy "Install yazi")))))

(ert-deftest my/doctor-module-check-reports-recorded-failures ()
  (let ((my/--init-errors '((init-broken error "boom"))))
    (let ((payload (my/doctor--check-module-loads)))
      (should (eq (plist-get payload :status) 'fail))
      (should (string-match-p "init-broken" (plist-get payload :detail))))))

(ert-deftest my/doctor-note-home-check-does-not-create-directories ()
  (let* ((path (expand-file-name "org-seq-doctor-missing"
                                 temporary-file-directory))
         (was-bound (boundp 'my/note-home))
         (previous (and was-bound (symbol-value 'my/note-home))))
    (when (file-exists-p path)
      (delete-directory path t))
    (unwind-protect
        (progn
          (set 'my/note-home path)
          (let ((payload (my/doctor--check-note-home)))
            (should (eq (plist-get payload :status) 'warn))
            (should-not (file-exists-p path))))
      (if was-bound
          (set 'my/note-home previous)
        (makunbound 'my/note-home)))))

(ert-deftest my/doctor-vc-package-check-reports-missing-inventory ()
  (cl-letf (((symbol-function 'my/vc-package-statuses)
             (lambda ()
               '((:package installed :status present)
                 (:package missing-one :status missing)
                 (:package broken-one :status failed)))))
    (let ((payload (my/doctor--check-vc-packages)))
      (should (eq (plist-get payload :status) 'warn))
      (should (string-match-p "missing-one" (plist-get payload :detail)))
      (should (string-match-p "broken-one" (plist-get payload :detail))))))

;;; test-init-doctor.el ends here
