;;; early-init.el --- Pre-GUI initialization -*- lexical-binding: t; -*-

;; 1. GC suppression during startup
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; 2. Skip file-name-handler-alist regex matching during startup
(defvar my--file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist my--file-name-handler-alist)))

;; 3. Prevent UI elements from being created (faster than disabling after creation)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

(setq inhibit-startup-screen t
      inhibit-startup-message t)

;; 4. Native-comp settings
(setq native-comp-async-report-warnings-errors 'silent
      native-comp-jit-compilation t)

;;; early-init.el ends here
