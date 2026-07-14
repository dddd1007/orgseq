;;; test-init-languages.el --- Tests for language integration -*- lexical-binding: t; -*-

(require 'ert)

(load-file
 (expand-file-name "../lisp/init-languages.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/polymode-keymap-adapter-flattens-cons-bindings ()
  (should
   (equal
    (my/polymode--normalize-define-keymap-args
     '(:parent parent ("<" . poly-noweb-electric-<)))
    '(:parent parent "<" poly-noweb-electric-<))))

(ert-deftest my/polymode-keymap-adapter-preserves-modern-bindings ()
  (should
   (equal
    (my/polymode--normalize-define-keymap-args
     '(:parent parent "<" poly-noweb-electric-<))
    '(:parent parent "<" poly-noweb-electric-<))))

(ert-deftest my/polymode-loader-removes-temporary-advice-on-error ()
  (let (added removed)
    (cl-letf (((symbol-function 'advice-add)
               (lambda (&rest _arguments) (setq added t)))
              ((symbol-function 'advice-remove)
               (lambda (&rest _arguments) (setq removed t)))
              ((symbol-function 'require)
               (lambda (&rest _arguments) (error "load failed"))))
      (should-error (my/polymode--require-poly-r))
      (should added)
      (should removed))))

;;; test-init-languages.el ends here
