;;; test-init-gtd.el --- Tests for the GTD state machine and agenda cache -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'org)

(defvar my/roam-dir)
(defvar my/outputs-dir)
(defvar my/practice-dir)
(defvar org-agenda-files)

(load-file
 (expand-file-name "../lisp/init-gtd.el"
                   (file-name-directory load-file-name)))

(defconst my/gtd-test--keywords
  (quote ((sequence "PROJECT(P)" "TODO(t)" "NEXT(n)" "IN-PROGRESS(i)"
                    "WAITING(w@/!)" "SOMEDAY(s)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))
  "The org-seq TODO sequence, mirrored from `org-todo-keywords'.")

(defun my/gtd-test--in-org (content fn)
  "Call FN with point at the start of a temporary Org buffer holding CONTENT."
  (with-temp-buffer
    (let ((org-todo-keywords my/gtd-test--keywords)
          (org-startup-folded nil))
      (delay-mode-hooks (org-mode))
      (insert content)
      (goto-char (point-min))
      (funcall fn))))

(defun my/gtd-test--make-note (directory name)
  "Create an Org file NAME inside DIRECTORY and return its path."
  (make-directory directory t)
  (let ((file (expand-file-name name directory)))
    (write-region "* TODO Task" nil file nil (quote silent))
    file))

;; ---- Section 2: GTD state constants ----

(ert-deftest my/gtd-state-sets-are-disjoint ()
  (should-not (cl-intersection my/gtd-closed-states my/gtd-active-states
                               :test (function equal))))

(ert-deftest my/gtd-state-predicates-follow-their-constants ()
  (dolist (state my/gtd-closed-states)
    (should (my/gtd--closed-state-p state))
    (should-not (my/gtd--active-state-p state)))
  (dolist (state my/gtd-active-states)
    (should (my/gtd--active-state-p state))
    (should-not (my/gtd--closed-state-p state)))
  (should-not (my/gtd--closed-state-p nil))
  (should-not (my/gtd--active-state-p nil)))

(ert-deftest my/gtd-state-constants-agree-with-the-org-keyword-sequence ()
  (my/gtd-test--in-org
   "* TODO Placeholder"
   (lambda ()
     (dolist (state my/gtd-closed-states)
       (should (member state org-done-keywords)))
     (dolist (state my/gtd-active-states)
       (should (member state org-not-done-keywords))))))

;; ---- Section 3: project detection ----

(ert-deftest my/gtd-project-requires-an-open-child-task ()
  (my/gtd-test--in-org
   "* PROJECT Ship release
** NEXT Draft notes
"
   (lambda () (should (my/org-project-p))))
  (my/gtd-test--in-org
   "* PROJECT Ship release
"
   (lambda () (should-not (my/org-project-p))))
  (my/gtd-test--in-org
   "* PROJECT Ship release
** DONE Draft notes
"
   (lambda () (should-not (my/org-project-p)))))

(ert-deftest my/gtd-project-detection-ignores-closed-parents ()
  (my/gtd-test--in-org
   "* DONE Ship release
** NEXT Draft notes
"
   (lambda () (should-not (my/org-project-p)))))

(ert-deftest my/gtd-stuck-project-has-no-next-child ()
  (my/gtd-test--in-org
   "* PROJECT Ship release
** TODO Draft notes
"
   (lambda ()
     (should (my/org-project-p))
     (should (my/org-stuck-project-p))))
  (my/gtd-test--in-org
   "* PROJECT Ship release
** NEXT Draft notes
"
   (lambda () (should-not (my/org-stuck-project-p)))))

(ert-deftest my/gtd-subtree-state-search-excludes-the-heading-itself ()
  (my/gtd-test--in-org
   "* NEXT Parent
** TODO Child
"
   (lambda ()
     (should-not (my/org--subtree-has-todo-state-p "NEXT"))
     (should (my/org--subtree-has-todo-state-p "TODO"))))
  (my/gtd-test--in-org
   "* PROJECT Parent
** TODO Child
*** NEXT Grandchild
"
   (lambda () (should (my/org--subtree-has-todo-state-p "NEXT")))))

(ert-deftest my/gtd-skip-functions-advance-past-non-matching-entries ()
  (my/gtd-test--in-org
   "* TODO Lone task
* PROJECT Real project
** NEXT Step
"
   (lambda () (should (my/org-skip-non-projects))))
  (my/gtd-test--in-org
   "* PROJECT Real project
** NEXT Step
"
   (lambda ()
     (should-not (my/org-skip-non-projects))
     (should (my/org-skip-non-stuck-projects)))))

;; ---- Section 5: child collection before complete/cancel ----

(ert-deftest my/gtd-collect-active-children-skips-parent-and-closed-children ()
  (my/gtd-test--in-org
   "* NEXT Parent
** NEXT Open child
** DONE Closed child
** WAITING Blocked child
"
   (lambda ()
     (let ((markers (my/gtd--collect-active-children)))
       (unwind-protect
           (progn
             (should (= (length markers) 2))
             (should (equal (sort (mapcar
                                   (lambda (m)
                                     (save-excursion
                                       (goto-char m)
                                       (org-get-todo-state)))
                                   markers)
                                  (function string<))
                            (quote ("NEXT" "WAITING")))))
         (dolist (m markers) (set-marker m nil)))))))

(ert-deftest my/gtd-collect-active-children-returns-nil-for-a-leaf ()
  (my/gtd-test--in-org
   "* NEXT Lone task
"
   (lambda () (should-not (my/gtd--collect-active-children)))))

;; ---- Section 5: complete and cancel ----

(defun my/gtd-test--in-org-file (content fn)
  "Call FN at the first heading of a real Org file holding CONTENT."
  (let ((file (make-temp-file "org-seq-gtd-cmd-" nil ".org")))
    (unwind-protect
        (progn
          (write-region content nil file nil (quote silent))
          (with-current-buffer (find-file-noselect file)
            (let ((org-todo-keywords my/gtd-test--keywords))
              (org-mode)
              (goto-char (point-min))
              (cl-letf (((symbol-function (quote y-or-n-p)) (lambda (&rest _) t)))
                (funcall fn))
              (prog1 (buffer-substring-no-properties (point-min) (point-max))
                (set-buffer-modified-p nil)
                (kill-buffer)))))
      (delete-file file))))

(ert-deftest my/gtd-complete-closes-a-leaf-task-that-has-a-next-sibling ()
  "A childless task must not error out on the sibling that follows it."
  (let ((result (my/gtd-test--in-org-file
                 "* NEXT First task\n* NEXT Second task\n"
                 (function my/gtd-complete))))
    (should (string-match-p "DONE First task" result))
    (should (string-match-p "NEXT Second task" result))))

(ert-deftest my/gtd-complete-closes-a-lone-task ()
  (let ((result (my/gtd-test--in-org-file
                 "* NEXT Lone task\n"
                 (function my/gtd-complete))))
    (should (string-match-p "DONE Lone task" result))))

(ert-deftest my/gtd-complete-closes-the-parent-as-well-as-its-children ()
  "Closing children must not leave the parent open."
  (let ((result (my/gtd-test--in-org-file
                 "* NEXT Parent\n** NEXT Child\n* NEXT Other\n"
                 (function my/gtd-complete))))
    (should (string-match-p "DONE Parent" result))
    (should (string-match-p "DONE Child" result))
    (should (string-match-p "NEXT Other" result))))

(ert-deftest my/gtd-cancel-closes-the-parent-as-well-as-its-children ()
  (let ((result (my/gtd-test--in-org-file
                 "* NEXT Parent\n** NEXT Child\n"
                 (function my/gtd-cancel))))
    (should (string-match-p "CANCELLED Parent" result))
    (should (string-match-p "CANCELLED Child" result))))

(ert-deftest my/gtd-cancel-closes-a-leaf-task-that-has-a-next-sibling ()
  (let ((result (my/gtd-test--in-org-file
                 "* NEXT First task\n* NEXT Second task\n"
                 (function my/gtd-cancel))))
    (should (string-match-p "CANCELLED First task" result))
    (should (string-match-p "NEXT Second task" result))))

;; ---- Section 1: agenda file cache ----

(ert-deftest my/gtd-agenda-cache-scans-actionable-para-layers-only ()
  (let* ((root (make-temp-file "org-seq-gtd-agenda-" t))
         (my/roam-dir (expand-file-name "00_Roam/" root))
         (my/outputs-dir (expand-file-name "10_Outputs/" root))
         (my/practice-dir (expand-file-name "20_Practice/" root))
         (library (expand-file-name "30_Library/" root))
         (archives (expand-file-name "40_Archives/" root)))
    (unwind-protect
        (let ((roam (my/gtd-test--make-note my/roam-dir "note.org"))
              (outputs (my/gtd-test--make-note my/outputs-dir "draft.org"))
              (practice (my/gtd-test--make-note my/practice-dir "drill.org"))
              (in-library (my/gtd-test--make-note library "ref.org"))
              (in-archives (my/gtd-test--make-note archives "old.org")))
          (my/org-invalidate-agenda-cache)
          (let ((files (mapcar (function file-truename)
                               (my/org-roam-agenda-files t))))
            (should (member (file-truename roam) files))
            (should (member (file-truename outputs) files))
            (should (member (file-truename practice) files))
            (should-not (member (file-truename in-library) files))
            (should-not (member (file-truename in-archives) files))))
      (my/org-invalidate-agenda-cache)
      (delete-directory root t))))

(ert-deftest my/gtd-agenda-cache-is-reused-until-invalidated ()
  (let* ((root (make-temp-file "org-seq-gtd-cache-" t))
         (my/roam-dir (expand-file-name "00_Roam/" root))
         (my/outputs-dir (expand-file-name "10_Outputs/" root))
         (my/practice-dir (expand-file-name "20_Practice/" root))
         (my/agenda-cache-ttl 300))
    (unwind-protect
        (progn
          (my/gtd-test--make-note my/roam-dir "first.org")
          (my/org-invalidate-agenda-cache)
          (should (= (length (my/org-roam-agenda-files t)) 1))
          (my/gtd-test--make-note my/roam-dir "second.org")
          (should (= (length (my/org-roam-agenda-files)) 1))
          (my/org-invalidate-agenda-cache)
          (should (= (length (my/org-roam-agenda-files)) 2)))
      (my/org-invalidate-agenda-cache)
      (delete-directory root t))))

(ert-deftest my/gtd-agenda-cache-expires-after-its-ttl ()
  (let* ((root (make-temp-file "org-seq-gtd-ttl-" t))
         (my/roam-dir (expand-file-name "00_Roam/" root))
         (my/outputs-dir (expand-file-name "10_Outputs/" root))
         (my/practice-dir (expand-file-name "20_Practice/" root))
         (my/agenda-cache-ttl 0))
    (unwind-protect
        (progn
          (my/gtd-test--make-note my/roam-dir "first.org")
          (my/org-invalidate-agenda-cache)
          (should (= (length (my/org-roam-agenda-files)) 1))
          (my/gtd-test--make-note my/roam-dir "second.org")
          (should (= (length (my/org-roam-agenda-files)) 2)))
      (my/org-invalidate-agenda-cache)
      (delete-directory root t))))

(ert-deftest my/gtd-refresh-agenda-files-populates-org-agenda-files ()
  (let* ((root (make-temp-file "org-seq-gtd-refresh-" t))
         (my/roam-dir (expand-file-name "00_Roam/" root))
         (my/outputs-dir (expand-file-name "10_Outputs/" root))
         (my/practice-dir (expand-file-name "20_Practice/" root))
         (org-agenda-files nil))
    (unwind-protect
        (progn
          (my/gtd-test--make-note my/roam-dir "note.org")
          (my/org-invalidate-agenda-cache)
          (my/org-refresh-agenda-files)
          (should (= (length org-agenda-files) 1)))
      (my/org-invalidate-agenda-cache)
      (delete-directory root t))))

;;; test-init-gtd.el ends here
