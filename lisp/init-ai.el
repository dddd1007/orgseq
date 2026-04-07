;;; init-ai.el --- AI integration via gptel -*- lexical-binding: t; -*-

;; ---- API key retrieval via auth-source ----
;; Store your key in ~/.authinfo (or ~/.authinfo.gpg for encryption):
;;   machine openrouter.ai login apikey password sk-or-XXXXX

(defun my/gptel-api-key (host)
  "Retrieve API key for HOST from auth-source."
  (if-let ((found (car (auth-source-search :host host :max 1))))
      (let ((secret (plist-get found :secret)))
        (if (functionp secret) (funcall secret) secret))
    (user-error "No API key for %s. Add to ~/.authinfo: machine %s login apikey password YOUR-KEY"
                host host)))

;; ---- gptel: LLM client ----
(use-package gptel
  :defer t
  :commands (gptel gptel-send gptel-menu gptel-rewrite gptel-add
             gptel-request gptel-make-openai gptel-make-preset)
  :config
  (setq gptel-default-mode 'org-mode)

  ;; OpenRouter: 300+ models via single API, works in China
  (setq gptel-backend
        (gptel-make-openai "OpenRouter"
          :host "openrouter.ai"
          :endpoint "/api/v1/chat/completions"
          :stream t
          :key (lambda () (my/gptel-api-key "openrouter.ai"))
          :models '(deepseek/deepseek-chat-v3-0324
                    anthropic/claude-sonnet-4
                    google/gemini-2.5-flash
                    openai/gpt-4o-mini
                    qwen/qwen-2.5-72b-instruct
                    mistralai/mistral-large)))

  (setq gptel-model 'deepseek/deepseek-chat-v3-0324)

  ;; PKM-oriented default system prompt (public API)
  (push '(pkm . "You are a helpful PKM assistant in Emacs. Respond concisely in the user's language. Preserve org-mode markup when working with notes.")
        gptel-directives)

  ;; Org-mode: branching conversations per heading
  (setq gptel-org-branching-context t)

  ;; ---- PKM Presets ----
  ;; Available via gptel-menu (@preset-name) or programmatically.
  ;; gptel-make-preset requires gptel v0.9.9+; guard for older versions.
  (when (fboundp 'gptel-make-preset)
    (gptel-make-preset 'summarize
      :description "Summarize note"
      :system "Summarize the following text concisely, preserving key concepts and their relationships. Use the same language as the input. Format with org-mode markup.")

    (gptel-make-preset 'suggest-tags
      :description "Suggest filetags"
      :system "Based on this note content, suggest 3-5 relevant tags. Output ONLY in #+filetags: :tag1:tag2:tag3: format. No explanation needed.")

    (gptel-make-preset 'translate
      :description "Translate CN↔EN"
      :system "You are a professional translator. If the input is Chinese, translate to English. If English, translate to Chinese. Preserve formatting. Output only the translation.")

    (gptel-make-preset 'connections
      :description "Suggest note connections"
      :system "Based on this note from a Zettelkasten PKM system, suggest 3-5 related concepts or topics that might already exist as separate notes. For each, briefly explain the connection. Use org-mode list format. Respond in the same language as the input.")))

;; ---- Custom PKM AI commands ----

(defun my/ai--display-result (response info)
  "Display AI RESPONSE in a side window."
  (if response
      (with-current-buffer (get-buffer-create "*AI Result*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (org-mode)
          (insert response)
          (goto-char (point-min)))
        (display-buffer (current-buffer)
                        '((display-buffer-in-side-window)
                          (side . bottom)
                          (window-height . 0.33))))
    (message "AI request failed: %s" (plist-get info :status))))

(defun my/ai--get-text ()
  "Return the active region or the entire buffer as text."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun my/ai-summarize ()
  "Summarize the current buffer or region using AI."
  (interactive)
  (gptel-request (my/ai--get-text)
    :system "Summarize the following text concisely, preserving key concepts and their relationships. Use the same language as the input. Format with org-mode markup."
    :callback #'my/ai--display-result))

(defun my/ai-suggest-tags ()
  "Suggest org-roam filetags for the current note."
  (interactive)
  (gptel-request (my/ai--get-text)
    :system "Based on this note, suggest 3-5 relevant tags. Output ONLY in #+filetags: :tag1:tag2:tag3: format. No explanation."
    :callback #'my/ai--display-result))

(defun my/ai-translate ()
  "Translate the selected region between Chinese and English."
  (interactive)
  (unless (use-region-p) (user-error "Select a region to translate"))
  (gptel-request (buffer-substring-no-properties (region-beginning) (region-end))
    :system "Translate: Chinese→English or English→Chinese. Output only the translation."
    :callback #'my/ai--display-result))

(defun my/ai-improve ()
  "Improve writing quality of selected region via gptel-rewrite."
  (interactive)
  (unless (use-region-p) (user-error "Select a region to improve"))
  (call-interactively #'gptel-rewrite))

(defun my/ai-connections ()
  "Suggest conceptual connections for the current note."
  (interactive)
  (gptel-request (my/ai--get-text)
    :system "Based on this note from a Zettelkasten PKM system, suggest 3-5 related concepts. For each, explain the connection briefly. Respond in the same language. Use org-mode list format."
    :callback #'my/ai--display-result))

;; ---- ob-gptel: org-babel integration ----
;; Enables #+begin_src gptel blocks in org notes, executed with C-c C-c.
;; Not on MELPA; install from GitHub.

(when (< emacs-major-version 30)
  (unless (package-installed-p 'ob-gptel)
    (when (fboundp 'package-vc-install)
      (condition-case err
          (package-vc-install "https://github.com/jwiegley/ob-gptel")
        (error
         (message "⚠️ org-seq: failed to install ob-gptel: %s" err))))))

(if (>= emacs-major-version 30)
    (use-package ob-gptel
      :after (org gptel)
      :vc (:url "https://github.com/jwiegley/ob-gptel" :rev :newest)
      :config
      (add-to-list 'org-babel-load-languages '(gptel . t))
      (org-babel-do-load-languages 'org-babel-load-languages
                                   org-babel-load-languages))
  (use-package ob-gptel
    :after (org gptel)
    :if (locate-library "ob-gptel")
    :config
    (add-to-list 'org-babel-load-languages '(gptel . t))
    (org-babel-do-load-languages 'org-babel-load-languages
                                 org-babel-load-languages)))

(provide 'init-ai)
;;; init-ai.el ends here
