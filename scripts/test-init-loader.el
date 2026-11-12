;;; test-init-loader.el --- Tests for org-seq module loading -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defvar my/init-modules)
(defvar my/init-modules-default)
(defvar my/init-module-requires)
(defvar my/init-module-pins)
(defvar my/init-user-modules)
(defvar my/user-directory)

(defvar my/test-loader--root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory load-file-name)))
  "Repository root for locating module sources.")

(let* ((root my/test-loader--root)
       (user-emacs-directory root)
       (my/init-modules nil))
  (load-file (expand-file-name "init.el" root)))

(ert-deftest my/init-loader-records-success-and-elapsed-time ()
  (let ((my/--init-errors nil)
        (my/--init-results nil)
        (times '(10.0 10.25)))
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time) (pop times)))
              ((symbol-function 'require)
               (lambda (_module &optional _filename _noerror) t)))
      (should (my/--require-module 'init-test-success)))
    (should-not my/--init-errors)
    (should
     (equal (my/init-results)
            '((:module init-test-success
               :status loaded
               :elapsed 0.25
               :error nil))))))

(ert-deftest my/init-loader-records-failure-with-original-error ()
  (let ((my/--init-errors nil)
        (my/--init-results nil)
        (times '(20.0 20.5)))
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time) (pop times)))
              ((symbol-function 'require)
               (lambda (&rest _arguments) (error "loader boom"))))
      (should-not (my/--require-module 'init-test-failure)))
    (let ((result (car (my/init-results))))
      (should (eq (plist-get result :module) 'init-test-failure))
      (should (eq (plist-get result :status) 'failed))
      (should (= (plist-get result :elapsed) 0.5))
      (should (equal (error-message-string (plist-get result :error))
                     "loader boom")))
    (should (eq (caar my/--init-errors) 'init-test-failure))))

(ert-deftest my/init-results-preserves-module-attempt-order ()
  (let ((my/--init-errors nil)
        (my/--init-results nil))
    (cl-letf (((symbol-function 'require)
               (lambda (_module &optional _filename _noerror) t)))
      (my/--require-module 'init-first)
      (my/--require-module 'init-second))
    (should (equal (mapcar (lambda (result) (plist-get result :module))
                           (my/init-results))
                   '(init-first init-second)))))

(ert-deftest my/init-failed-modules-returns-attempt-order ()
  (let ((my/--init-results
         '((:module init-third :status failed :elapsed 0.3 :error third)
           (:module init-second :status loaded :elapsed 0.2 :error nil)
           (:module init-first :status failed :elapsed 0.1 :error first))))
    (should (equal (my/init-failed-modules)
                   '(init-first init-third)))))

(ert-deftest my/init-module-order-satisfies-declared-dependencies ()
  "The canonical module list must satisfy `my/init-module-requires'."
  (should (null (my/init-check-module-order my/init-modules-default))))

(ert-deftest my/init-module-requires-covers-only-known-modules ()
  "Every module and dependency in the contract must be a real module."
  (dolist (entry my/init-module-requires)
    (should (memq (car entry) my/init-modules-default))
    (dolist (dep (cdr entry))
      (should (memq dep my/init-modules-default)))))

(ert-deftest my/init-check-module-order-detects-inverted-order ()
  (should (equal (my/init-check-module-order
                  '(init-b init-a)
                  '((init-b . (init-a))))
                 '((init-b . "dependency init-a loads after it")))))

(ert-deftest my/init-check-module-order-detects-missing-dependency ()
  (should (equal (my/init-check-module-order
                  '(init-b)
                  '((init-b . (init-a))))
                 '((init-b . "dependency init-a is not in my/init-modules")))))

(ert-deftest my/init-check-module-order-ignores-disabled-modules ()
  "A module removed from the load list is not checked for its own deps."
  (should (null (my/init-check-module-order
                 '(init-a)
                 '((init-b . (init-a)))))))

(defun my/test-loader--declared-requires (module)
  "Return modules named on \"Requires:\" comment lines of MODULE's source."
  (let ((file (car (mapcan
                    (lambda (dir)
                      (directory-files-recursively
                       (expand-file-name dir my/test-loader--root)
                       (format "\\`%s\\.el\\'" module)))
                    '("core" "modules"))))
        (found nil))
    (when file
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^;; Requires: \\(.*\\)$" nil t)
          (let ((line (match-string 1))
                (start 0))
            (while (string-match "\\binit-[a-z-]+\\b" line start)
              (push (intern (match-string 0 line)) found)
              (setq start (match-end 0)))))))
    (cl-remove-duplicates (nreverse found))))

(ert-deftest my/init-module-requires-matches-source-headers ()
  "`my/init-module-requires' must mirror the module \"Requires:\" headers."
  (dolist (module my/init-modules-default)
    (let ((declared (my/test-loader--declared-requires module))
          (contract (cdr (assq module my/init-module-requires))))
      (should (equal (sort (copy-sequence declared) #'string<)
                     (sort (copy-sequence contract) #'string<))))))

;; ---- Computed order ----

(defun my/test-loader--plan (enabled &optional users requires pins)
  "Plan ENABLED plus USERS with empty default REQUIRES and PINS."
  (my/init-plan-modules enabled users requires pins))

(ert-deftest my/init-computed-order-equals-canonical-order ()
  "With the shipped data the sort changes nothing."
  (let ((sorted (my/init-sort-modules my/init-modules-default
                                      my/init-module-requires
                                      my/init-module-pins)))
    (should (equal (car sorted) my/init-modules-default))
    (should-not (cdr sorted))))

(ert-deftest my/init-sort-fixes-backwards-dependency ()
  (let ((sorted (my/init-sort-modules '(a b c d) '((b . (d))))))
    (should (equal (car sorted) '(a c d b)))
    (should-not (cdr sorted))
    (should-not (my/init-check-module-order (car sorted) '((b . (d)))))))

(ert-deftest my/init-sort-is-stable-without-constraints ()
  (should (equal (car (my/init-sort-modules '(d c b a) nil)) '(d c b a)))
  (should (equal (car (my/init-sort-modules '(d c b a) '((a . (d)))))
                 '(d c b a)))
  ;; A deferred module follows its dependency immediately.
  (should (equal (car (my/init-sort-modules '(a b c d e) '((a . (c)))))
                 '(b c a d e))))

(ert-deftest my/init-sort-ignores-dependencies-outside-the-set ()
  (should (equal (car (my/init-sort-modules '(a b) '((a . (zzz)))))
                 '(a b))))

(ert-deftest my/init-sort-detects-cycle-and-keeps-canonical-order ()
  (let ((sorted (my/init-sort-modules '(a b c d) '((a . (c)) (c . (b)) (b . (a))))))
    (should (equal (car sorted) '(a b c d)))
    (should (equal (cdr sorted) '(a c b a))))
  (should (equal (cdr (my/init-sort-modules '(a) '((a . (a))))) '(a a))))

(ert-deftest my/init-sort-honours-pins ()
  (let ((sorted (my/init-sort-modules
                 '(z a first-m b last-m c)
                 '((a . (c)))
                 '((first-m . first) (last-m . last)))))
    (should (equal (car sorted) '(first-m z b c a last-m)))))

(ert-deftest my/init-sort-pins-hold-on-shipped-data ()
  (let ((order (car (my/init-sort-modules my/init-modules-default
                                          my/init-module-requires
                                          my/init-module-pins))))
    (should (eq (car order) 'init-doctor))
    (should (eq (car (last order)) 'init-evil))))

(ert-deftest my/init-effective-modules-drops-disabled ()
  (let ((my/init-disabled-modules '(init-pyim)))
    (let ((effective (my/init-effective-modules my/init-modules-default)))
      (should-not (memq 'init-pyim effective))
      (should (memq 'init-org effective))
      (should (equal (my/init-module-skip-reason 'init-pyim)
                     "disabled in my/init-disabled-modules"))
      (should-not (my/init-module-skip-reason 'init-org))))
  (let ((my/init-disabled-modules nil))
    (should (equal (my/init-effective-modules my/init-modules-default)
                   my/init-modules-default))))

(ert-deftest my/init-module-source-classifies-modules ()
  (should (eq (my/init-module-source 'init-org) 'built-in))
  (should (eq (my/init-module-source 'my-research) 'user)))

;; ---- User modules ----

(ert-deftest my/init-user-modules-sorted-after-dependencies ()
  (let* ((plan (my/init-plan-modules
                '(init-doctor init-org init-nodes init-evil)
                '((my-b . (my-a)) (my-a . (init-nodes)))
                '((init-nodes . (init-org)))
                '((init-doctor . first) (init-evil . last)))))
    (should (equal (plist-get plan :order)
                   '(init-doctor init-org init-nodes my-a my-b init-evil)))
    (should-not (plist-get plan :skipped))
    (should-not (plist-get plan :cycle))))

(ert-deftest my/init-user-modules-skipped-for-missing-dependency ()
  (let* ((plan (my/init-plan-modules
                '(init-org)
                '((my-a . (init-gone)) (my-b . (my-a)) (my-c . (init-org)))
                nil nil))
         (skipped (plist-get plan :skipped)))
    (should (equal (plist-get plan :order) '(init-org my-c)))
    (should (assq 'my-a skipped))
    (should (assq 'my-b skipped))
    (should (string-match-p "init-gone" (cdr (assq 'my-a skipped))))))

(ert-deftest my/init-user-modules-skipped-for-disabled-dependency ()
  "A built-in module that is not enabled is not a usable dependency."
  (let* ((my/init-modules-default '(init-org init-pyim))
         (plan (my/init-plan-modules '(init-org)
                                     '((my-a . (init-pyim))) nil nil)))
    (should (equal (plist-get plan :order) '(init-org)))
    (should (assq 'my-a (plist-get plan :skipped)))))

(ert-deftest my/init-user-modules-reject-clashes-and-malformed-entries ()
  (let* ((plan (my/init-plan-modules
                '(init-org)
                '((init-org . nil) (my-a) (my-a) "junk" (my-b . (1)))
                nil nil))
         (skipped (plist-get plan :skipped)))
    (should (equal (plist-get plan :order) '(init-org my-a)))
    (should (= (length skipped) 4))))

(ert-deftest my/init-user-module-cycle-falls-back ()
  (let ((plan (my/init-plan-modules '(init-org)
                                    '((my-a . (my-b)) (my-b . (my-a)))
                                    nil nil)))
    (should (equal (plist-get plan :cycle) '(my-a my-b my-a)))
    (should (equal (plist-get plan :order) '(init-org my-a my-b)))))

(ert-deftest my/init-add-user-load-path-uses-existing-directories ()
  (let* ((root (make-temp-file "orgseq-user" t))
         (my/user-directory (file-name-as-directory root))
         (load-path nil))
    (unwind-protect
        (progn
          (my/init-add-user-load-path)
          (should (equal load-path (list (directory-file-name root))))
          (make-directory (expand-file-name "modules" root))
          (my/init-add-user-load-path)
          (should (member (expand-file-name "modules" root) load-path)))
      (delete-directory root t))))

(ert-deftest my/init-add-user-load-path-skips-missing-directory ()
  (let ((my/user-directory "/nonexistent-orgseq-user/")
        (load-path nil))
    (my/init-add-user-load-path)
    (should-not load-path)))

(ert-deftest my/init-user-modules-load-through-guarded-loader ()
  "User modules in user/ and user/modules/ load; a failure does not stop the rest."
  (let* ((root (make-temp-file "orgseq-user" t))
         (my/user-directory (file-name-as-directory root))
         (load-path load-path)
         (my/--init-errors nil)
         (my/--init-results nil)
         (inhibit-message t))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "modules" root))
          (with-temp-file (expand-file-name "my-test-top.el" root)
            (insert "(setq my-test-top-loaded t)\n(provide 'my-test-top)\n"))
          (with-temp-file (expand-file-name "modules/my-test-broken.el" root)
            (insert "(error \"user boom\")\n"))
          (with-temp-file (expand-file-name "modules/my-test-last.el" root)
            (insert "(setq my-test-last-loaded t)\n(provide 'my-test-last)\n"))
          (my/init-add-user-load-path)
          (let ((plan (my/init-plan-modules
                       nil
                       '((my-test-top) (my-test-broken . (my-test-top))
                         (my-test-last . (my-test-broken)))
                       nil nil)))
            (should (equal (plist-get plan :order)
                           '(my-test-top my-test-broken my-test-last)))
            (dolist (module (plist-get plan :order))
              (my/--require-module module)))
          (should (bound-and-true-p my-test-top-loaded))
          (should (bound-and-true-p my-test-last-loaded))
          (should (equal (my/init-failed-modules) '(my-test-broken)))
          (should (eq (caar my/--init-errors) 'my-test-broken)))
      (delete-directory root t)
      (dolist (f '(my-test-top my-test-last))
        (setq features (delq f features))))))

(ert-deftest my/init-report-shows-source-position-and-skips ()
  (require 'init-doctor)
  (let ((my/init-modules '(init-org my-a))
        (my/--init-skipped '((init-pyim . "disabled in my/init-disabled-modules")))
        (results '((:module init-org :status loaded :elapsed 0.1 :error nil)
                   (:module my-a :status failed :elapsed 0.2
                            :error (error "boom")))))
    (let ((buffer (my/init-report-render results)))
      (unwind-protect
          (with-current-buffer buffer
            (let ((text (buffer-string)))
              (should (string-match-p "LOADED.*init-org +built-in +#1" text))
              (should (string-match-p "FAILED.*my-a +user +#2" text))
              (should (string-match-p "SKIP +init-pyim +built-in +disabled in" text))))
        (kill-buffer buffer)))))

;; ---- Generated dependency block ----

(ert-deftest my/init-module-requires-block-matches-generator ()
  "The generated block equals what is in init.el."
  (load (expand-file-name "scripts/gen-module-requires.el" my/test-loader--root)
        nil t)
  (should (string= (my/gen-requires-block my/test-loader--root)
                   (my/gen-requires-current my/test-loader--root))))

;; ---- First-event hooks ----

(defvar my/test-loader--first-hook nil
  "Scratch hook for first-event tests.")

(ert-deftest my/first-event-hook-runs-once-and-isolates-errors ()
  "A failing function is recorded; the rest of the hook still runs once."
  (let ((my/--init-errors nil)
        (calls nil))
    (setq my/test-loader--first-hook
          (list (lambda () (push 'first calls))
                (lambda () (error "deferred boom"))
                (lambda () (push 'last calls))))
    (let ((inhibit-message t))
      (my/run-first-event-hook 'my/test-loader--first-hook)
      (my/run-first-event-hook 'my/test-loader--first-hook))
    (should (equal calls '(last first)))
    (should-not my/test-loader--first-hook)
    (should (= (length my/--init-errors) 1))
    (should (equal (error-message-string (cdar my/--init-errors))
                   "deferred boom"))))

(ert-deftest my/first-event-hook-skips-absent-autoloads ()
  "Autoloads into uninstalled packages are skipped, not reported."
  (let ((my/--init-errors nil)
        (fn (make-symbol "my-test-absent-mode")))
    (fset fn '(autoload "org-seq-test-no-such-library" nil t))
    (setq my/test-loader--first-hook (list fn))
    (my/run-first-event-hook 'my/test-loader--first-hook)
    (should-not my/--init-errors)
    (should-not my/test-loader--first-hook)))

(ert-deftest my/first-event-trigger-detaches-itself ()
  "The trigger runs its hook and removes itself from `pre-command-hook'."
  (let ((pre-command-hook nil)
        (ran 0))
    (setq my/test-loader--first-hook (list (lambda () (cl-incf ran))))
    (let ((trigger (my/first-event-trigger 'my/test-loader--first-hook)))
      (add-hook 'pre-command-hook trigger)
      (run-hooks 'pre-command-hook)
      (should-not (memq trigger pre-command-hook))
      (funcall trigger))
    (should (= ran 1))))

;;; test-init-loader.el ends here
