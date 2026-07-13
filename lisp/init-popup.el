;;; init-popup.el --- Central display-buffer policy -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defcustom my/popup-rules
  '((:id cli
     :matcher "\\`\\*NoteHQ-"
     :side bottom :slot 1 :height 0.38 :select t)
    (:id ai-result
     :matcher "\\`\\*AI Result\\*\\'"
     :side bottom :slot 0 :height 0.33 :select nil)
    (:id diagnostics
     :matcher "\\`\\*org-seq \\(?:doctor\\|init report\\|init errors\\|keymap audit\\|package audit\\)\\*\\'"
     :side bottom :slot 0 :height 0.33 :select t)
    (:id compilation
     :matcher "\\`\\*\\(?:compilation\\|Compile-Log\\)\\*\\'"
     :side bottom :slot 0 :height 0.3 :select nil)
    (:id help
     :matcher "\\`\\*\\(?:Help\\|helpful.*\\)\\*\\'"
     :side right :slot 0 :width 0.38 :select t))
  "Ordered org-seq popup specifications.

User entries already present in `display-buffer-alist' keep priority. Each
specification accepts :id, :matcher, :side, :slot, :height, :width, :select,
and :dedicated keys."
  :type '(repeat sexp)
  :group 'org-seq)

(defun my/popup--merge-plists (base overrides)
  "Return BASE with every key in OVERRIDES replaced."
  (let ((result (copy-sequence base))
        (rest overrides))
    (while rest
      (setq result (plist-put result (pop rest) (pop rest))))
    result))

(defun my/popup--action (spec)
  "Return a display action for popup SPEC."
  (let* ((side (or (plist-get spec :side) 'bottom))
         (action (list '(display-buffer-in-side-window)
                       (cons 'side side)
                       (cons 'slot (or (plist-get spec :slot) 0))
                       (cons 'preserve-size
                             (if (memq side '(left right))
                                 '(t . nil)
                               '(nil . t))))))
    (when (and (plist-member spec :height)
               (plist-get spec :height))
      (setq action
            (append action
                    (list (cons 'window-height
                                (plist-get spec :height))))))
    (when (and (plist-member spec :width)
               (plist-get spec :width))
      (setq action
            (append action
                    (list (cons 'window-width
                                (plist-get spec :width))))))
    (when (plist-get spec :dedicated)
      (setq action (append action '((dedicated . t)))))
    action))

(defun my/popup--build-rule (spec)
  "Build one `display-buffer-alist' rule from SPEC."
  (append (list (plist-get spec :matcher))
          (my/popup--action spec)
          (list (cons 'my/popup-rule-id (plist-get spec :id)))))

(defun my/popup--owned-rule-p (rule)
  "Return non-nil when RULE is owned by org-seq."
  (and (consp rule)
       (assq 'my/popup-rule-id (cdr rule))))

(defun my/popup-register-rules ()
  "Register org-seq popup rules without replacing user rules.

Registration is idempotent. Existing non-org-seq rules retain their order and
priority, including rules loaded earlier from `custom.el'."
  (interactive)
  (setq display-buffer-alist
        (append (cl-remove-if #'my/popup--owned-rule-p
                              display-buffer-alist)
                (mapcar #'my/popup--build-rule my/popup-rules))))

(defun my/popup-rule-for-buffer (buffer)
  "Return the first popup spec matching BUFFER, or nil."
  (let ((name (if (bufferp buffer) (buffer-name buffer) buffer)))
    (seq-find
     (lambda (spec)
       (string-match-p (plist-get spec :matcher) name))
     my/popup-rules)))

(defun my/popup-display-buffer (buffer &optional overrides)
  "Display BUFFER according to org-seq popup policy.

OVERRIDES is a plist merged over the matching rule for this call only. Return
the displayed window and select it when the merged :select value is non-nil."
  (let* ((base (or (my/popup-rule-for-buffer buffer)
                   '(:side bottom :slot 0 :height 0.33 :select nil)))
         (spec (my/popup--merge-plists base overrides))
         (window (display-buffer buffer (my/popup--action spec))))
    (when (and window (plist-get spec :select))
      (select-window window))
    window))

(my/popup-register-rules)

(provide 'init-popup)
;;; init-popup.el ends here
