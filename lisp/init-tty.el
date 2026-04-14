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

(when (not (display-graphic-p))

  ;; ---- Mouse: click, drag, and scroll in terminal ----
  ;; xterm-mouse-mode translates xterm escape sequences into Emacs mouse
  ;; events.  Works in every modern terminal emulator (WezTerm, Alacritty,
  ;; Windows Terminal, iTerm2, tmux, ...).
  (xterm-mouse-mode 1)
  (setq mouse-wheel-scroll-amount '(1 ((shift) . 1))
        mouse-wheel-progressive-speed nil)

  ;; ---- Window separators: box-drawing glyph instead of plain `|' ----
  ;; The default vertical-border char is `|' which looks broken.  U+2502
  ;; renders as a solid line in any Unicode-capable terminal.
  (set-display-table-slot standard-display-table 'vertical-border ?│)

  ;; ---- corfu-terminal: overlay popups for in-buffer completion ----
  ;; Upstream corfu uses child frames, which TTY doesn't have.  This
  ;; package re-implements the popup with a text overlay so ESS, eglot,
  ;; and cape all keep working over SSH.
  (use-package corfu-terminal
    :after corfu
    :config
    (corfu-terminal-mode 1))

  ;; ---- clipetty: system clipboard via OSC 52 (SSH-friendly) ----
  ;; Every copy/kill is forwarded to the terminal emulator's clipboard
  ;; using the OSC 52 escape sequence, which is relayed through tmux and
  ;; SSH without any external helper like xclip/xsel/pbcopy.  Paste still
  ;; uses the terminal's own paste binding (Ctrl+Shift+V, cmd+v, ...).
  (use-package clipetty
    :config
    (global-clipetty-mode 1)))

(provide 'init-tty)
;;; init-tty.el ends here
