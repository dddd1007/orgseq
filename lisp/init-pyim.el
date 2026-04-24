;;; init-pyim.el --- Chinese input method (pyim) configuration -*- lexical-binding: t; -*-
;;
;; Pyim is a pure-Elisp Chinese input method for Emacs, supporting
;; quanpin, shuangpin, wubi, cangjie and Rime backends.
;;
;; This module sets up pyim with the community-recommended defaults:
;; - quanpin (full pinyin) scheme
;; - pyim-basedict (the default ~100k-entry libpinyin dictionary)
;; - posframe tooltip when available, falling back to popup/minibuffer
;; - painless Chinese/English switching via probe functions
;; - pinyin-aware isearch via pyim-isearch-mode
;; - conservative sis integration for Evil/minibuffer/prefix-key switching
;;
;; Toggle input method: C-\
;; Force-convert word at point: M-j

;; ═══════════════════════════════════════════════════════════════════════════
;; Core package: pyim
;; ═══════════════════════════════════════════════════════════════════════════

(use-package pyim
  :defer 1
  :bind (("M-j" . pyim-convert-string-at-point))
  :init
  ;; Use pyim as the default input method.
  (setq default-input-method "pyim")

  ;; Default to quanpin (full pinyin).
  (setq pyim-default-scheme 'quanpin)

  ;; Show 7 candidates per page (a sweet spot between density and readability).
  (setq pyim-page-length 7)

  ;; Fuzzy pinyin: treat "in" and "ing" as equivalent.
  (setq pyim-pinyin-fuzzy-alist
        '(("in" "ing")
          ("en" "eng")
          ("an" "ang")))

  ;; Candidate tooltip: prefer posframe, then popup, then minibuffer.
  ;; posframe looks best on modern Emacs; popup works in TTY.
  ;; We use `locate-library' so the preference is recorded even before
  ;; the tooltip packages are actually loaded (pyim will require them
  ;; on demand when showing candidates).
  (setq pyim-page-tooltip
        (cond ((locate-library "posframe") 'posframe)
              ((locate-library "popup")    'popup)
              (t                           'minibuffer)))

  :config
  ;; Enable pinyin-aware isearch so you can search Chinese with pinyin.
  (pyim-isearch-mode 1)

  ;; Enable cloud pinyin (baidu backend) for better phrase prediction.
  (setq pyim-cloudim 'baidu)

  ;; Painless Chinese/English auto-switching probes.
  ;; Any probe returning t switches pyim to English temporarily.
  (setq-default pyim-english-input-switch-functions
                '(pyim-probe-dynamic-english    ; context-aware switching
                  pyim-probe-isearch-mode       ; English during isearch
                  pyim-probe-program-mode       ; English in code, Chinese in comments/strings
                  pyim-probe-org-structure-template)) ; English during org templates

  ;; Auto-switch to half-width punctuation in specific contexts.
  (setq-default pyim-punctuation-half-width-functions
                '(pyim-probe-punctuation-line-beginning
                  pyim-probe-punctuation-after-punctuation))

  ;; Restart pyim shortly after it loads so dictionaries are fully ready,
  ;; without blocking the very first frame draw.
  (run-with-idle-timer
   0.2 nil
   (lambda ()
     (when (featurep 'pyim)
       (pyim-restart-1 t)))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Dictionary: pyim-basedict (GNU ELPA)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; pyim-basedict is the official default dictionary (~100k entries,
;; sourced from libpinyin). It is small, fast, and sufficient for
;; daily use. For a larger dictionary (~3.3M entries, ~80 MB) see
;; pyim-greatdict on MELPA.

(use-package pyim-basedict
  :after pyim
  :config
  (pyim-basedict-enable))

;; ═══════════════════════════════════════════════════════════════════════════
;; Input source state management: sis
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Keep pyim as the actual input engine and let sis manage the "when"
;; around it: leaving Evil insert state, entering the minibuffer,
;; handling prefix keys, and restoring per-buffer state.
;;
;; We intentionally do NOT enable sis context/inline modes here because
;; pyim already handles context-sensitive English switching with its probe
;; functions above.  Running both systems aggressively would make the
;; switching rules harder to reason about.

(defun my/pyim-enable-sis-modes ()
  "Enable the conservative sis modes after startup."
  (sis-global-cursor-color-mode 1)
  (sis-global-respect-mode 1))

(use-package sis
  :after pyim
  :ensure t
  :config
  ;; Use pyim as sis's "other language" native input method.
  ;; English remains the nil/native no-input-method state.
  (sis-ism-lazyman-config nil (or default-input-method "pyim") 'native)

  ;; A stronger cursor color makes the current input state obvious.
  (setq sis-other-cursor-color "green")

  ;; This module loads before `init-evil', so enable sis's global modes
  ;; after startup when Evil and the rest of the editor state are present.
  ;; If this file is re-evaluated after startup, enable them immediately.
  (if after-init-time
      (my/pyim-enable-sis-modes)
    (add-hook 'emacs-startup-hook #'my/pyim-enable-sis-modes)))

;; ═══════════════════════════════════════════════════════════════════════════
;; Tooltip backend helpers
;; ═══════════════════════════════════════════════════════════════════════════

;; Install posframe if available for a modern floating candidate box.
(use-package posframe
  :defer t
  :ensure t
  :config
  (setq pyim-page-tooltip 'posframe))

;; Fallback popup tooltip (works in terminal too).
(use-package popup
  :defer t
  :ensure t)

(provide 'init-pyim)
;;; init-pyim.el ends here
