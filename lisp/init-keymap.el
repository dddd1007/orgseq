;;; init-keymap.el --- Leader-key metadata and audit -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function general-define-key "general" (&rest arguments))
(declare-function evil-local-mode "evil" (&optional arg))
(declare-function evil-normal-state "evil" ())

(defconst my/leader-prefixes
  '((:key "a" :description "agenda")
    (:key "b" :description "buffer")
    (:key "c" :description "casual")
    (:key "e" :description "eval")
    (:key "f" :description "file")
    (:key "g" :description "git")
    (:key "h" :description "help")
    (:key "i" :description "AI")
    (:key "l" :description "layout")
    (:key "n" :description "notes")
    (:key "o" :description "open")
    (:key "P" :description "PARA")
    (:key "p" :description "project")
    (:key "s" :description "search")
    (:key "t" :description "toggle")
    (:key "w" :description "window")
    (:key "q" :description "quit"))
  "Top-level SPC leader namespaces and their which-key descriptions.")

(defconst my/leader-critical-bindings
  '((:key "'" :command my/terminal-popup-toggle
     :description "Terminal popup")
    (:key "ad" :command my/org-dashboard
     :description "GTD Dashboard")
    (:key "af" :command org-focus-start
     :description "Focus: start slice")
    (:key "nF" :command org-roam-node-find
     :description "Find note (roam)")
    (:key "npp" :command my/supertag-quick-action
     :description "Quick action")
    (:key "ix" :command my/codex-popup-toggle
     :description "Codex CLI popup")
    (:key "oy" :command my/yazi-popup-toggle
     :description "Yazi popup"))
  "Critical leader bindings treated as org-seq's tested keymap contract.")

(defun my/keymap-general-arguments ()
  "Return general.el arguments for registered prefixes and critical keys."
  (append
   (cl-mapcan
    (lambda (spec)
      (list (plist-get spec :key)
            (list :ignore t :wk (plist-get spec :description))))
    my/leader-prefixes)
   (cl-mapcan
    (lambda (spec)
      (list (plist-get spec :key)
            (list (plist-get spec :command)
                  :wk (plist-get spec :description))))
    my/leader-critical-bindings)))

(defun my/keymap-apply-general-contract ()
  "Apply registered prefixes and critical bindings with general.el."
  (apply #'general-define-key
         :states '(normal visual emacs)
         :keymaps 'override
         :prefix "SPC"
         :global-prefix "M-SPC"
         (my/keymap-general-arguments)))
(defun my/keymap--leader-key-sequence (key)
  "Return a `kbd' sequence for compact leader KEY metadata."
  (kbd
   (concat "SPC "
           (string-join
            (mapcar #'char-to-string (string-to-list key))
            " "))))


(defun my/keymap--effective-leader-command (key)
  "Resolve compact leader KEY in an Evil normal-state buffer."
  (if (and (fboundp 'evil-local-mode)
           (fboundp 'evil-normal-state))
      (with-temp-buffer
        (evil-local-mode 1)
        (evil-normal-state)
        (key-binding (my/keymap--leader-key-sequence key)))
    (key-binding (my/keymap--leader-key-sequence key))))
(defun my/keymap-audit-results (&optional resolver)
  "Return audit results for critical leader bindings.

RESOLVER receives each compact leader key and returns its effective command.
When nil, inspect an Evil normal-state buffer with `key-binding'."
  (let ((resolve (or resolver #'my/keymap--effective-leader-command)))
    (mapcar
     (lambda (spec)
       (let* ((key (plist-get spec :key))
              (expected (plist-get spec :command))
              (actual (funcall resolve key)))
         (list :key key
               :expected expected
               :actual actual
               :status (if (eq actual expected) 'pass 'fail))))
     my/leader-critical-bindings)))

(defun my/keymap-audit ()
  "Display the effective state of org-seq's critical leader bindings."
  (interactive)
  (let ((buffer (get-buffer-create "*org-seq keymap audit*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "org-seq critical leader bindings\n\n")
        (dolist (result (my/keymap-audit-results))
          (insert
           (format "%-4s SPC %-4s expected=%-32s actual=%s\n"
                   (upcase (symbol-name (plist-get result :status)))
                   (plist-get result :key)
                   (plist-get result :expected)
                   (plist-get result :actual))))
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer buffer)))

(provide 'init-keymap)
;;; init-keymap.el ends here
