;;; test-init-keymap.el --- Tests for leader-key metadata -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(load-file
 (expand-file-name "../lisp/init-keymap.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/keymap-prefix-and-critical-keys-are-unique ()
  (let* ((keys (append (mapcar (lambda (spec) (plist-get spec :key))
                               my/leader-prefixes)
                       (mapcar (lambda (spec) (plist-get spec :key))
                               my/leader-critical-bindings)))
         (unique (delete-dups (copy-sequence keys))))
    (should (= (length keys) (length unique)))))

(ert-deftest my/keymap-critical-contract-covers-core-workflows ()
  (dolist (expected '(("'" . my/terminal-popup-toggle)
                      ("ad" . my/org-dashboard)
                      ("af" . org-focus-start)
                      ("nF" . org-roam-node-find)
                      ("npp" . my/supertag-quick-action)
                      ("ix" . my/codex-popup-toggle)
                      ("oy" . my/yazi-popup-toggle)))
    (let ((spec (seq-find
                 (lambda (entry)
                   (equal (plist-get entry :key) (car expected)))
                 my/leader-critical-bindings)))
      (should spec)
      (should (eq (plist-get spec :command) (cdr expected))))))

(ert-deftest my/keymap-metadata-has-descriptions-and-no-eaf-contract ()
  (dolist (spec (append my/leader-prefixes my/leader-critical-bindings))
    (should (stringp (plist-get spec :description)))
    (should-not (string-empty-p (plist-get spec :description)))
    (should-not (string-match-p
                 "eaf\\|pyqterminal"
                 (downcase (format "%S" spec))))))

(ert-deftest my/keymap-general-arguments-preserve-contract-shape ()
  (let ((arguments (my/keymap-general-arguments)))
    (should (equal (plist-get (cadr (member "a" arguments)) :wk)
                   "agenda"))
    (should (eq (car (cadr (member "'" arguments)))
                'my/terminal-popup-toggle))
    (should (equal (plist-get (cdr (cadr (member "'" arguments))) :wk)
                   "Terminal popup"))))

(ert-deftest my/keymap-apply-contract-uses-general-function-boundary ()
  (let (captured)
    (cl-letf (((symbol-function 'general-define-key)
               (lambda (&rest arguments)
                 (setq captured arguments))))
      (my/keymap-apply-general-contract))
    (should (equal (plist-get captured :states)
                   '(normal visual emacs)))
    (should (eq (plist-get captured :keymaps) 'override))
    (should (equal (plist-get captured :prefix) "SPC"))
    (should (equal (plist-get captured :global-prefix) "M-SPC"))
    (let ((binding (cadr (member "'" captured))))
      (should (eq (car binding) 'my/terminal-popup-toggle))
      (should (equal (plist-get (cdr binding) :wk)
                     "Terminal popup")))))


(ert-deftest my/keymap-default-resolver-uses-evil-normal-state ()
  (let ((my/leader-critical-bindings
         '((:key "'" :command my/terminal-popup-toggle
            :description "Terminal popup")))
        local-mode normal-state)
    (cl-letf (((symbol-function 'evil-local-mode)
               (lambda (&optional _arg) (setq local-mode t)))
              ((symbol-function 'evil-normal-state)
               (lambda () (setq normal-state t)))
              ((symbol-function 'key-binding)
               (lambda (_key) 'my/terminal-popup-toggle)))
      (should (eq (plist-get (car (my/keymap-audit-results)) :status) 'pass))
      (should local-mode)
      (should normal-state))))
(ert-deftest my/keymap-audit-results-report-mismatches ()
  (let ((results
         (my/keymap-audit-results
          (lambda (key)
            (if (equal key "ad") 'wrong-command
              (plist-get
               (seq-find (lambda (spec)
                           (equal (plist-get spec :key) key))
                         my/leader-critical-bindings)
               :command))))))
    (should (eq (plist-get (seq-find
                            (lambda (result)
                              (equal (plist-get result :key) "ad"))
                            results)
                           :status)
                'fail))
    (should (= (cl-count 'pass results
                         :key (lambda (result)
                                (plist-get result :status)))
               (1- (length my/leader-critical-bindings))))))

;;; test-init-keymap.el ends here
