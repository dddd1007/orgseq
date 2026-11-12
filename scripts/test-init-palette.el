;;; test-init-palette.el --- Tests for the palette, slash menu and field panel -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar my/types-file)
(defvar my/views-file)
(defvar my/node-types)
(defvar evil-local-mode)

(let ((dir (file-name-directory load-file-name)))
  (load-file (expand-file-name "../modules/notes/init-nodes.el" dir))
  (load-file (expand-file-name "../modules/notes/init-views.el" dir))
  (load-file (expand-file-name "../modules/notes/init-palette.el" dir)))

(defconst my/test-palette--types
  "* Work
:PROPERTIES:
:TYPE_FIELDS: STATUS AREA:node
:END:

* Reading
:PROPERTIES:
:TYPE_FIELDS: YEAR:number
:END:
")

(defun my/test-palette--types ()
  "Return the parsed test type registry."
  (with-temp-buffer
    (insert my/test-palette--types)
    (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
    (my/node-types-parse-buffer)))

(defun my/test-palette--records ()
  "Return a small fixed library with a duplicated title."
  (list (list :id "a1" :title "Stats" :tags '("work") :file "/lib/a.org" :level 0)
        (list :id "a2" :title "Stats" :tags nil :file "/lib/b.org" :level 0)
        (list :id "h1" :title "Heading node" :tags nil :file "/lib/c.org"
              :level 1)))

(defun my/test-palette--command ()
  "Command used as a palette entry."
  (interactive)
  (setq my/test-palette--ran t))

(defvar my/test-palette--ran nil)

(defun my/test-palette--candidates ()
  "Return candidates built from the test data."
  (my/palette--candidates
   (my/test-palette--records)
   (my/test-palette--types)
   (list (list :name "Board" :layout 'board))
   '(("Test it" . my/test-palette--command))))

;;; Palette

(ert-deftest my/palette-candidates-cover-every-kind ()
  (let ((labels (mapcar #'car (my/test-palette--candidates))))
    (should (member "Heading node" labels))
    (should (member "#Work" labels))
    (should (member "#Reading" labels))
    (should (member "@Board" labels))
    (should (member ">Test it" labels))
    (should (equal (mapcar (lambda (c) (nth 1 c)) (my/test-palette--candidates))
                   '(node node node type type view command)))))

(ert-deftest my/palette-candidates-disambiguate-duplicate-titles ()
  (let ((labels (mapcar #'car (my/test-palette--candidates))))
    (should (member "Stats  (a)" labels))
    (should (member "Stats  (b)" labels))
    (should-not (member "Stats" labels))
    (should (= (length labels) (length (delete-dups (copy-sequence labels)))))))

(ert-deftest my/palette-available-commands-skip-unbound ()
  (should (equal (my/palette--available-commands
                  '(("Yes" . my/test-palette--command)
                    ("No" . my/test-palette--nonexistent-command)))
                 '(("Yes" . my/test-palette--command)))))

(ert-deftest my/palette-table-metadata ()
  (let* ((candidates (my/test-palette--candidates))
         (table (my/palette--table candidates))
         (metadata (cdr (completion-metadata "" table nil)))
         (group (completion-metadata-get (completion-metadata "" table nil)
                                         'group-function))
         (annotate (completion-metadata-get (completion-metadata "" table nil)
                                            'annotation-function)))
    (ignore metadata)
    (should (equal (funcall group "#Work" nil) "New note"))
    (should (equal (funcall group "@Board" nil) "Views"))
    (should (equal (funcall group ">Test it" nil) "Commands"))
    (should (equal (funcall group "Heading node" nil) "Nodes"))
    (should (equal (funcall group "Heading node" t) "Heading node"))
    (should (string-match-p "board view" (funcall annotate "@Board")))
    (should (equal (all-completions "#" table) '("#Work" "#Reading")))))

(ert-deftest my/palette-dispatch-each-kind ()
  (let (log)
    (cl-letf (((symbol-function 'my/palette--visit)
               (lambda (record) (push (list 'visit (plist-get record :id)) log)))
              ((symbol-function 'my/palette--capture)
               (lambda (type title)
                 (push (list 'capture (my/node-type-name type) title) log)))
              ((symbol-function 'my/view-open)
               (lambda (name) (push (list 'view name) log)))
              ((symbol-function 'read-string) (lambda (&rest _) "Fresh")))
      (setq my/test-palette--ran nil)
      (let ((alist (my/test-palette--candidates)))
        (dolist (label '("Heading node" "#Reading" "@Board" ">Test it"))
          (my/palette--dispatch (cdr (assoc label alist))))))
    (should (equal (nreverse log)
                   '((visit "h1") (capture "Reading" "Fresh") (view "Board"))))
    (should my/test-palette--ran)))

(ert-deftest my/palette-command-flow-and-fallback-create ()
  (let (log (my/node-types (my/test-palette--types)))
    (cl-letf (((symbol-function 'my/index-records)
               (lambda () (my/test-palette--records)))
              ((symbol-function 'my/views-load) (lambda () nil))
              ((symbol-function 'my/palette--visit)
               (lambda (record) (push (list 'visit (plist-get record :id)) log)))
              ((symbol-function 'my/palette--capture)
               (lambda (type title)
                 (push (list 'capture (and type (my/node-type-name type)) title)
                       log)))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "Heading node")))
        (my/palette))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt &rest _)
                   (if (equal prompt "Palette: ") "Brand new" "Reading"))))
        (my/palette))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt &rest _)
                   (if (equal prompt "Palette: ") "Plain" "(no type)"))))
        (my/palette))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
        (my/palette)))
    (should (equal (nreverse log)
                   '((visit "h1") (capture "Reading" "Brand new")
                     (capture nil "Plain"))))))

(ert-deftest my/palette-capture-wrapper-picks-first-bound ()
  (let (called)
    (cl-letf (((symbol-function 'my/note-capture)
               (lambda (type title) (setq called (list 'new type title)))))
      (my/palette--capture nil "T")
      (should (equal called '(new nil "T"))))
    (should-not (fboundp 'my/note-capture))))

;;; Slash menu

(defmacro my/test-palette--in-org (text &rest body)
  "Run BODY in an Org buffer holding TEXT, point at the marker ^ (removed)."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
     (goto-char (point-min))
     (when (search-forward "^" nil t) (delete-char -1))
     ,@body))

(ert-deftest my/slash-context-detection ()
  (my/test-palette--in-org "* H\n^"
    (should (my/slash--context-p)))
  (my/test-palette--in-org "* H\n  ^"
    (should (my/slash--context-p)))
  (my/test-palette--in-org "* H\ntext ^"
    (should-not (my/slash--context-p)))
  (my/test-palette--in-org "* H\n^text"
    (should-not (my/slash--context-p)))
  (my/test-palette--in-org "* H\n#+begin_src emacs-lisp\n^\n#+end_src\n"
    (should-not (my/slash--context-p)))
  (my/test-palette--in-org "* H\n#+begin_src emacs-lisp\n(a)\n#+end_src\n^"
    (should (my/slash--context-p)))
  (my/test-palette--in-org "* H\n| a | b |\n^| c | d |\n"
    (should-not (my/slash--context-p)))
  (my/test-palette--in-org "* H\n:PROPERTIES:\n:ID: x\n^\n:END:\n"
    (should-not (my/slash--context-p)))
  (my/test-palette--in-org "* H\n:PROPERTIES:\n:ID: x\n:END:\n^"
    (should (my/slash--context-p))))

(ert-deftest my/slash-evil-gate ()
  (my/test-palette--in-org "^"
    (should (my/slash--evil-ok-p))
    (let ((evil-local-mode t))
      (cl-letf (((symbol-function 'evil-insert-state-p) (lambda (&rest _) nil)))
        (should-not (my/slash--evil-ok-p)))
      (cl-letf (((symbol-function 'evil-insert-state-p) (lambda (&rest _) t)))
        (should (my/slash--evil-ok-p))))))

(defun my/test-palette--insert (text fn)
  "Run FN on an Org buffer holding TEXT (with ^ for point); return the result."
  (my/test-palette--in-org text
    (funcall fn)
    (cons (buffer-string) (point))))

(ert-deftest my/slash-builtin-insertions ()
  (cl-letf (((symbol-function 'my/palette--read-node)
             (lambda (&rest _) (list :id "n1" :title "Node One")))
            ((symbol-function 'my/views-load)
             (lambda () (list (list :name "Reading"))))
            ((symbol-function 'completing-read)
             (lambda (&rest _) "Reading"))
            ((symbol-function 'my/node-read-type)
             (lambda (&rest _) (car (my/test-palette--types))))
            ((symbol-function 'org-update-dblock) #'ignore))
    (should (equal (car (my/test-palette--insert "^" #'my/slash-insert-node-link))
                   "[[id:n1][Node One]]"))
    (should (equal (car (my/test-palette--insert "^" #'my/slash-insert-view-block))
                   "#+BEGIN: orgseq-view :view \"Reading\"\n#+END:"))
    (should (equal (car (my/test-palette--insert "^" #'my/slash-insert-query-block))
                   (concat "#+BEGIN: orgseq-query :type \"work\" "
                           ":sort \"modified\" :order desc\n#+END:")))
    (should (equal (car (my/test-palette--insert "  ^" #'my/slash-insert-checkbox))
                   "  - [ ] "))
    (should (equal (car (my/test-palette--insert "** A\n^" #'my/slash-insert-heading))
                   "** A\n** "))
    (should (equal (car (my/test-palette--insert "^" #'my/slash-insert-heading))
                   "* "))
    (should (equal (car (my/test-palette--insert "* A\n^"
                                                 #'my/slash-insert-todo-heading))
                   "* A\n* TODO "))
    (let ((result (my/test-palette--insert "^" #'my/slash-insert-table)))
      (should (equal (car result) "|   |   |\n|---+---|\n|   |   |"))
      (should (= (cdr result) 3)))
    (let ((result (my/test-palette--insert "^" #'my/slash-insert-source-block)))
      (should (equal (car result) "#+begin_src \n\n#+end_src"))
      (should (= (cdr result) 13)))
    (let ((result (my/test-palette--insert "^" #'my/slash-insert-quote-block)))
      (should (equal (car result) "#+begin_quote\n\n#+end_quote"))
      (should (= (cdr result) 15)))
    (should (string-match-p "\\`\\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [^]]+\\]\\'"
                            (car (my/test-palette--insert
                                  "^" #'my/slash-insert-date))))))

(ert-deftest my/slash-new-node-link-uses-returned-id ()
  (cl-letf (((symbol-function 'my/node-read-type)
             (lambda (&rest _) (car (my/test-palette--types))))
            ((symbol-function 'read-string) (lambda (&rest _) "Fresh"))
            ((symbol-function 'my/palette--capture)
             (lambda (_type _title) (list :id "z9" :title "Fresh"))))
    (should (equal (car (my/test-palette--insert
                         "^" #'my/slash-insert-new-node-link))
                   "[[id:z9][Fresh]]"))))

(ert-deftest my/slash-menu-runs-items-and-keeps-slash-on-quit ()
  (let ((my/slash-items (list (cons "Text" "hello") (cons "Fn" #'ignore))))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Text")))
      (should (equal (car (my/test-palette--insert "^" #'my/slash-menu)) "hello")))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (signal 'quit nil))))
      (should (equal (car (my/test-palette--insert "^" #'my/slash-menu)) "/")))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
      (should (equal (car (my/test-palette--insert "^" #'my/slash-menu)) "/")))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (user-error "Boom"))))
      (should (equal (car (my/test-palette--insert "^" #'my/slash-menu)) "/")))))

(ert-deftest my/slash-trigger-falls-back-to-plain-slash ()
  (my/test-palette--in-org "word ^"
    (my/slash-mode 1)
    (let ((last-command-event ?/)
          (called nil))
      (cl-letf (((symbol-function 'my/slash-menu) (lambda () (setq called t))))
        (my/slash-trigger))
      (should-not called)
      (should (equal (buffer-string) "word /"))))
  (my/test-palette--in-org "^"
    (my/slash-mode 1)
    (let ((last-command-event ?/)
          (called nil))
      (cl-letf (((symbol-function 'my/slash-menu) (lambda () (setq called t))))
        (my/slash-trigger))
      (should called))))

;;; Field panel

(defconst my/test-palette--note
  ":PROPERTIES:\n:ID: abc\n:STATUS: doing\n:END:\n#+title: T\n#+filetags: :work:\n\n* Body\n")

(defun my/test-palette--panel-overlays ()
  "Return the field panel overlays of the current buffer."
  (cl-remove-if-not (lambda (ov) (overlay-get ov 'my/node-fields))
                    (overlays-in (point-min) (point-max))))

(ert-deftest my/node-fields-panel-shows-fields ()
  (let ((my/node-types (my/test-palette--types)))
    (my/test-palette--in-org my/test-palette--note
      (let ((before (buffer-string)))
        (my/node-fields-mode 1)
        (let* ((overlays (my/test-palette--panel-overlays))
               (text (overlay-get (car overlays) 'after-string)))
          (should (= (length overlays) 1))
          (should (equal (substring-no-properties text)
                         "  Status   doing\n  Area     -\n"))
          (should (eq (get-text-property (- (length text) 2) 'face text)
                      'my/node-fields-empty))
          ;; The overlay sits at the end of the title line.
          (should (= (overlay-start (car overlays))
                     (save-excursion (goto-char (point-min))
                                     (search-forward "#+title: T")
                                     (point)))))
        (should (equal (buffer-string) before))))))

(ert-deftest my/node-fields-panel-refreshes-and-edits ()
  (let ((my/node-types (my/test-palette--types)))
    (my/test-palette--in-org my/test-palette--note
      (my/node-fields-mode 1)
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "STATUS"))
                ((symbol-function 'my/node--read-field-value)
                 (lambda (&rest _) "done")))
        (my/node-fields-edit))
      (should (equal (org-entry-get (point-min) "STATUS") "done"))
      (should (string-match-p
               "Status   done"
               (overlay-get (car (my/test-palette--panel-overlays)) 'after-string)))
      (my/node-fields-toggle)
      (should-not (my/test-palette--panel-overlays))
      (my/node-fields-toggle)
      (should (my/test-palette--panel-overlays)))))

(ert-deftest my/node-fields-panel-absent-without-type ()
  (let ((my/node-types (my/test-palette--types)))
    (my/test-palette--in-org
        ":PROPERTIES:\n:ID: abc\n:END:\n#+title: T\n#+filetags: :other:\n"
      (my/node-fields-mode 1)
      (should-not (my/test-palette--panel-overlays)))
    (my/test-palette--in-org "#+title: No id\n#+filetags: :work:\n"
      (my/node-fields-mode 1)
      (should-not (my/test-palette--panel-overlays)))
    (my/test-palette--in-org "* Just a heading\n"
      (my/node-fields-mode 1)
      (should-not (my/test-palette--panel-overlays))
      (should-error (my/node-fields-edit) :type 'user-error))))

(ert-deftest my/node-fields-panel-removed-on-disable ()
  (let ((my/node-types (my/test-palette--types)))
    (my/test-palette--in-org my/test-palette--note
      (org-indent-mode 1)
      (visual-line-mode 1)
      (my/node-fields-mode 1)
      (should (my/test-palette--panel-overlays))
      (my/node-fields-mode -1)
      (should-not (my/test-palette--panel-overlays))
      (should-not (memq 'my/node-fields-refresh after-save-hook)))))

(provide 'test-init-palette)
;;; test-init-palette.el ends here
