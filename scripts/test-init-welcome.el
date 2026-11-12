;;; test-init-welcome.el --- Tests for the welcome page -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar my/note-home)

(load-file
 (expand-file-name "../modules/ui/init-welcome.el"
                   (file-name-directory load-file-name)))

(defconst my/test-welcome--fresh
  (list :library "/tmp/lib/notes" :files 0 :notes 0 :bytes 0
        :sync "sync off (M-x my/sync-setup)"
        :snapshot-dir "/tmp/lib/snapshots" :snapshots 0
        :last-snapshot nil :legacy nil)
  "Storage plist of a library with nothing in it.")

(defconst my/test-welcome--configured
  (list :library "/tmp/lib/notes" :files 14 :notes 12 :bytes 4096
        :sync "remote dav:notes, last success 2026-11-01"
        :snapshot-dir "/tmp/lib/snapshots" :snapshots 3
        :last-snapshot "2026-11-10.tar.gz" :legacy nil)
  "Storage plist of a library that is set up.")

(defconst my/test-welcome--keymap
  '((my/daily-workspace-open . "SPC d") (my/note-capture . "SPC c")
    (my/palette . "SPC k") (my/node-find . "SPC n n")
    (consult-ripgrep . "SPC /") (execute-extended-command . "SPC SPC")
    (my/storage-snapshot . "SPC n S b") (my/sync-now . "SPC n S s")
    (my/storage-import . "SPC n S i") (my/sync-setup . "SPC n S c"))
  "Key table used by the tests.")

(defconst my/test-welcome--problems
  '((:id a :label "Ghostel native module" :status fail
     :detail "The compiled module is missing from the package directory and this line is long enough to wrap"
     :remedy "Run M-x ghostel-module-compile once")
    (:id b :label "ripgrep" :status warn :detail "rg not found" :remedy nil)
    (:id c :label "Emacs version" :status pass :detail "31.0" :remedy nil))
  "Doctor results with two problems and one pass.")

(defun my/test-welcome--section (data id)
  "Return the section with ID from DATA."
  (cl-find id data :key (lambda (s) (plist-get s :id))))

(defun my/test-welcome--items (data)
  "Return the checklist item lines of DATA."
  (cl-remove-if-not (lambda (line) (eq (car line) :item))
                    (plist-get (my/test-welcome--section data 'steps) :lines)))

(defun my/test-welcome--item (data command)
  "Return the checklist item for COMMAND in DATA."
  (cl-find command (my/test-welcome--items data)
           :key (lambda (line) (plist-get line :command))))

(defun my/test-welcome--render (info results width)
  "Render a page for INFO and RESULTS at WIDTH and return the buffer."
  (let ((buffer (generate-new-buffer " *welcome-test*")))
    (with-current-buffer buffer
      (my/welcome-render
       (my/welcome-data info results my/test-welcome--keymap) width))
    buffer))

(ert-deftest my/welcome-fresh-library-has-nothing-done ()
  (let ((data (my/welcome-data my/test-welcome--fresh nil
                               my/test-welcome--keymap)))
    (should (= 6 (length (my/test-welcome--items data))))
    (dolist (command '(my/storage-import my/sync-setup my/storage-snapshot
                                         my/note-capture))
      (should-not (plist-get (my/test-welcome--item data command) :done)))
    (should (equal "SPC n S b"
                   (plist-get (my/test-welcome--item data 'my/storage-snapshot)
                              :key)))))

(ert-deftest my/welcome-configured-library-shows-done-items ()
  (let ((data (my/welcome-data my/test-welcome--configured nil
                               my/test-welcome--keymap)))
    (should (= 6 (length (my/test-welcome--items data))))
    (dolist (command '(my/storage-import my/sync-setup my/storage-snapshot
                                         my/note-capture))
      (should (plist-get (my/test-welcome--item data command) :done)))
    (should (string-match-p
             "3 snapshots"
             (plist-get (my/test-welcome--item data 'my/storage-snapshot)
                        :note)))
    (should-not (plist-get (my/test-welcome--item data 'my/palette) :done))))

(ert-deftest my/welcome-legacy-hint-only-with-legacy ()
  (let* ((legacy (plist-put (copy-sequence my/test-welcome--fresh)
                            :legacy "/home/u/NoteHQ"))
         (with (my/test-welcome--item
                (my/welcome-data legacy nil my/test-welcome--keymap)
                'my/storage-import))
         (without (my/test-welcome--item
                   (my/welcome-data my/test-welcome--fresh nil
                                    my/test-welcome--keymap)
                   'my/storage-import)))
    (should (string-match-p "NoteHQ" (plist-get with :note)))
    (should-not (plist-get without :note))
    ;; A pending legacy library keeps the import step open even with notes.
    (let ((pending (plist-put (copy-sequence my/test-welcome--configured)
                              :legacy "/home/u/NoteHQ")))
      (should-not (plist-get (my/test-welcome--item
                              (my/welcome-data pending nil my/test-welcome--keymap)
                              'my/storage-import)
                             :done)))))

(ert-deftest my/welcome-health-section ()
  (let* ((ok (my/test-welcome--section
              (my/welcome-data my/test-welcome--fresh
                               '((:id c :label "X" :status pass :detail "ok"))
                               my/test-welcome--keymap)
              'health))
         (bad (my/test-welcome--section
               (my/welcome-data my/test-welcome--fresh
                                my/test-welcome--problems my/test-welcome--keymap)
               'health))
         (lines (plist-get bad :lines)))
    (should (equal '((:text "Everything passed.")) (plist-get ok :lines)))
    (should (= 2 (length lines)))
    (should (equal "Ghostel native module" (plist-get (car lines) :label)))
    (should (eq 'warn (plist-get (cadr lines) :status)))
    (should (equal "Run M-x ghostel-module-compile once"
                   (plist-get (car lines) :remedy)))))

(ert-deftest my/welcome-health-caps-long-lists ()
  (let* ((many (cl-loop for i below 10
                        collect (list :label (format "c%d" i) :status 'warn
                                      :detail "d" :remedy nil)))
         (lines (plist-get (my/test-welcome--section
                            (my/welcome-data my/test-welcome--fresh many nil)
                            'health)
                           :lines)))
    (should (= (1+ my/welcome--max-problems) (length lines)))
    (should (eq :more (car (car (last lines)))))))

(ert-deftest my/welcome-keys-section-has-at-most-eight-rows ()
  (let ((lines (plist-get (my/test-welcome--section
                           (my/welcome-data my/test-welcome--fresh nil
                                            my/test-welcome--keymap)
                           'keys)
                          :lines)))
    (should (<= (length lines) 8))
    (should (member "SPC k" (mapcar (lambda (l) (plist-get l :key)) lines)))))

(ert-deftest my/welcome-key-alist-falls-back-to-documented-keys ()
  (let ((alist (my/welcome-key-alist)))
    (should (equal "SPC k" (cdr (assq 'my/palette alist))))
    (should (equal "SPC n S i" (cdr (assq 'my/storage-import alist))))))

(ert-deftest my/welcome-key-alist-prefers-live-bindings ()
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c w p") #'my/test-welcome--cmd)
    (defalias 'my/test-welcome--cmd (lambda () (interactive) nil))
    (cl-letf (((symbol-function 'my/welcome--lookup-maps) (lambda () (list map))))
      (let ((my/welcome--key-rows '((my/test-welcome--cmd "Probe"))))
        (should (equal "C-c w p"
                       (cdr (assq 'my/test-welcome--cmd (my/welcome-key-alist)))))))))

(ert-deftest my/welcome-every-line-fits-57-columns ()
  (dolist (info (list my/test-welcome--fresh my/test-welcome--configured
                      (plist-put (copy-sequence my/test-welcome--fresh)
                                 :legacy "/home/someone/very/long/path/NoteHQ")
                      (plist-put (copy-sequence my/test-welcome--configured)
                                 :library
                                 "/home/someone/a/really/quite/deep/directory/tree/for/the/library")))
    (dolist (results (list nil my/test-welcome--problems))
      (dolist (width '(54 40))
        (let ((buffer (my/test-welcome--render info results width)))
          (unwind-protect
              (with-current-buffer buffer
                (goto-char (point-min))
                (while (not (eobp))
                  (let ((line (buffer-substring (line-beginning-position)
                                                (line-end-position))))
                    (should (<= (string-width line) width))
                    (should-not (string-match-p "[^[:ascii:]]" line)))
                  (forward-line 1)))
            (kill-buffer buffer)))))))

(ert-deftest my/welcome-buttons-run-the-listed-commands ()
  (let ((buffer (my/test-welcome--render my/test-welcome--fresh
                                         my/test-welcome--problems 54))
        commands)
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (let (button)
            (while (setq button (next-button (point)))
              (push (button-get button 'my/welcome-command) commands)
              (goto-char (button-end button))))
          (setq commands (nreverse commands))
          (should (equal '(my/storage-import my/sync-setup my/storage-snapshot
                                             my/daily-workspace-open my/note-capture
                                             my/palette)
                         (cl-subseq commands 0 6)))
          (should (memq 'my/node-find commands)))
      (kill-buffer buffer))))

(ert-deftest my/welcome-button-action-calls-the-command ()
  (let ((buffer (my/test-welcome--render my/test-welcome--fresh nil 54))
        called)
    (defalias 'my/palette (lambda () (interactive) (setq called t)))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (search-forward "command palette")
          (push-button (1- (point)))
          (should called))
      (kill-buffer buffer)
      (fmakunbound 'my/palette))))

(ert-deftest my/welcome-footer-names-the-reopen-command ()
  (let ((text (with-current-buffer (my/test-welcome--render
                                    my/test-welcome--fresh nil 54)
                (prog1 (buffer-string) (kill-buffer)))))
    (should (string-match-p "my/welcome" text))
    (should (string-match-p "never" text))))

;; ---- First-run logic ----

(defmacro my/test-welcome--with-startup (state &rest body)
  "Run BODY with stubbed state file STATE (a plist symbol) and recorders."
  (declare (indent 1))
  `(let ((puts nil) (shown 0))
     (cl-letf (((symbol-function 'my/sync--state) (lambda () ,state))
               ((symbol-function 'my/sync--state-put)
                (lambda (&rest changes)
                  (push changes puts)
                  (setq ,state (apply #'plist-put ,state changes))))
               ((symbol-function 'my/welcome) (lambda () (cl-incf shown)))
               ((symbol-function 'run-with-idle-timer)
                (lambda (_secs _repeat fn &rest _) (funcall fn) 'timer))
               ((symbol-function 'daemonp) (lambda () nil)))
       (let ((noninteractive nil))
         ,@body))))

(ert-deftest my/welcome-first-run-shows-once-and-records-once ()
  (let ((state nil) (my/welcome-at-startup 'first-run))
    (my/test-welcome--with-startup state
      (should (eq 'scheduled (my/welcome-maybe-show)))
      (should (= 1 shown))
      (should (= 1 (length puts)))
      (should (plist-get state :welcome-shown))
      (should-not (my/welcome-maybe-show))
      (should (= 1 shown))
      (should (= 1 (length puts))))))

(ert-deftest my/welcome-always-shows-every-time-but-records-once ()
  (let ((state nil) (my/welcome-at-startup 'always))
    (my/test-welcome--with-startup state
      (my/welcome-maybe-show)
      (my/welcome-maybe-show)
      (should (= 2 shown))
      (should (= 1 (length puts))))))

(ert-deftest my/welcome-never-shows-nothing ()
  (let ((state nil) (my/welcome-at-startup 'never))
    (my/test-welcome--with-startup state
      (should-not (my/welcome-maybe-show))
      (should (= 0 shown))
      (should-not puts))))

(ert-deftest my/welcome-batch-mode-shows-nothing ()
  (let ((state nil) (my/welcome-at-startup 'always))
    (my/test-welcome--with-startup state
      (let ((noninteractive t))
        (should-not (my/welcome-maybe-show)))
      (should (= 0 shown)))))

(ert-deftest my/welcome-frameless-daemon-waits-for-the-first-frame ()
  (let ((state nil) (my/welcome-at-startup 'first-run)
        (after-make-frame-functions nil))
    (my/test-welcome--with-startup state
      (cl-letf (((symbol-function 'daemonp) (lambda () t))
                ((symbol-function 'terminal-name)
                 (lambda (&rest _) "initial_terminal")))
        (should (eq 'deferred (my/welcome-maybe-show)))
        (should (= 0 shown))
        (should (= 1 (length after-make-frame-functions)))
        ;; The first real frame arrives.
        (cl-letf (((symbol-function 'terminal-name)
                   (lambda (&rest _) "/dev/pts/1")))
          (run-hook-with-args 'after-make-frame-functions nil))
        (should (= 1 shown))
        (should-not after-make-frame-functions)
        (should (= 1 (length puts)))))))

;; ---- Read-only rendering ----

(ert-deftest my/welcome-rendering-creates-no-files ()
  (let* ((root (make-temp-file "welcome-lib" t))
         (my/note-home root)
         (before (directory-files-recursively root "" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'my/storage-info)
                   (lambda () my/test-welcome--fresh))
                  ((symbol-function 'my/doctor-run)
                   (lambda () my/test-welcome--problems))
                  ((symbol-function 'my/sync--state) (lambda () nil))
                  ((symbol-function 'my/sync--state-put)
                   (lambda (&rest _) (error "Rendering must not write state"))))
          (save-window-excursion
            (let ((buffer (my/welcome)))
              (unwind-protect
                  (with-current-buffer buffer
                    (should (derived-mode-p 'my/welcome-mode))
                    (should buffer-read-only)
                    (should (string-match-p "Your library" (buffer-string)))
                    (my/welcome-refresh))
                (kill-buffer buffer))))
          (should (equal before (directory-files-recursively root "" t))))
      (delete-directory root t))))

(provide 'test-init-welcome)
;;; test-init-welcome.el ends here
