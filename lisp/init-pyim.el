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
;;
;; Toggle input method: C-\
;; Force-convert word at point: M-j

;; ═══════════════════════════════════════════════════════════════════════════
;; Core package: pyim
;; ═══════════════════════════════════════════════════════════════════════════

(use-package pyim
  :demand t
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

  ;; "Golden finger": force-convert the pinyin string before point to Chinese.
  (global-set-key (kbd "M-j") #'pyim-convert-string-at-point)

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

  ;; Restart pyim after init so dictionaries are fully loaded.
  (add-hook 'emacs-startup-hook
            (lambda () (pyim-restart-1 t))))

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
