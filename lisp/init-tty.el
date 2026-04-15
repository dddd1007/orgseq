;;; init-tty.el --- Terminal-mode polish to align with the GUI experience -*- lexical-binding: t; -*-

;; Requires: init-completion (for corfu), init-ui (for theme/modeline)

;; Everything in this module is gated on running Emacs in a TTY.  The goal
;; is for a `emacs -nw' (or `emacsclient -t') session to match the desktop
;; experience as closely as possible: mouse works, clipboard integrates
;; with the host OS, corfu popups appear in-buffer instead of silently
;; failing, and window separators use a solid box-drawing glyph.
;;
;; All dependencies are :ensure t via `use-package-always-ensure' (set in
;; init.el), so first boot in a terminal downloads them on demand; GUI
;; sessions never install them.

(defun my/tty-frame-setup (frame)
  "Enable TTY-specific packages and settings for FRAME."
  (with-selected-frame frame
    (unless (display-graphic-p)
      (setq mouse-wheel-scroll-amount '(1 ((shift) . 1))
            mouse-wheel-progressive-speed nil)
      (set-display-table-slot standard-display-table 'vertical-border ?│)
      (require 'corfu-terminal nil t)
      (when (fboundp 'corfu-terminal-mode)
        (corfu-terminal-mode 1))
      (require 'clipetty nil t)
      (when (fboundp 'global-clipetty-mode)
        (global-clipetty-mode 1)))))

;; Apply to the current frame if it's a TTY, and hook for future frames.
(when (not (display-graphic-p))
  (my/tty-frame-setup (selected-frame)))

(add-hook 'after-make-frame-functions #'my/tty-frame-setup)

(provide 'init-tty)
;;; init-tty.el ends here
