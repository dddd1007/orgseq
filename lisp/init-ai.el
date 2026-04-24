;;; init-ai.el --- AI integration via gptel -*- lexical-binding: t; -*-

;; Requires: init-org (my/note-home, my/orgseq-dir, my/roam-dir)
(defvar my/orgseq-dir)  ; forward-declare from init-org
(defvar my/roam-dir)    ; forward-declare from init-org
(declare-function package-installed-p "package")

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

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 0: .orgseq AI service configuration
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Non-sensitive AI settings (backends, models, defaults) are stored in
;; ~/NoteHQ/.orgseq/ai-config.org — an editable org file.
;; API keys remain in ~/.authinfo.gpg via auth-source (see above).
;;
;; The org file uses headings + property drawers + plain lists:
;;   * Settings          — DEFAULT_BACKEND, DEFAULT_MODEL
;;   * Backends
;;   ** <Name>           — TYPE, HOST, ENDPOINT, STREAM, AUTH_HOST
;;     - model-1         — plain list items = available models
;;     - model-2

(defcustom my/orgseq-ai-config
  (expand-file-name "ai-config.org" my/orgseq-dir)
  "Path to .orgseq AI service configuration file."
  :type 'file :group 'org-seq)

(defconst my/orgseq--ai-config-template
  "#+TITLE: AI Services Configuration
#+DESCRIPTION: Backend and model settings for org-seq (API keys stay in ~/.authinfo.gpg)
#+STARTUP: showall

* Settings
:PROPERTIES:
:DEFAULT_BACKEND: OpenRouter
:DEFAULT_MODEL: deepseek/deepseek-chat-v3-0324
:END:

* Backends

** OpenRouter
:PROPERTIES:
:TYPE: openai-compatible
:HOST: openrouter.ai
:ENDPOINT: /api/v1/chat/completions
:STREAM: t
:AUTH_HOST: openrouter.ai
:END:

- deepseek/deepseek-chat-v3-0324
- anthropic/claude-sonnet-4
- google/gemini-2.5-flash
- openai/gpt-4o-mini
- qwen/qwen-2.5-72b-instruct
- mistralai/mistral-large
"
  "Template content for ai-config.org.
Created once if the file does not exist; never overwritten.")

(defun my/orgseq--ensure-ai-config ()
  "Create .orgseq/ai-config.org with defaults if it does not exist.
Idempotent — skips entirely when the file is already present."
  (unless (file-exists-p my/orgseq-ai-config)
    (make-directory (file-name-directory my/orgseq-ai-config) t)
    (with-temp-file my/orgseq-ai-config
      (insert my/orgseq--ai-config-template))
    (message "org-seq: created %s" my/orgseq-ai-config)))

(defun my/orgseq--collect-list-items ()
  "Collect plain-list items from point to next heading.
Returns a list of trimmed strings."
  (let ((bound (save-excursion
                 (if (re-search-forward "^\\*" nil t)
                     (line-beginning-position)
                   (point-max))))
        items)
    (while (re-search-forward "^[ \t]*- \\(.+\\)" bound t)
      (push (string-trim (match-string-no-properties 1)) items))
    (nreverse items)))

(defun my/orgseq--parse-ai-config ()
  "Parse .orgseq/ai-config.org into a configuration plist.
Returns (:default-backend STR :default-model STR :backends LIST) or nil.
Each backend in LIST is a plist with :name :type :host :endpoint :stream
:auth-host :models."
  (when (file-exists-p my/orgseq-ai-config)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents my/orgseq-ai-config)
          (org-mode)
          (let (default-backend default-model backends)
            ;; Parse Settings heading
            (goto-char (point-min))
            (when (re-search-forward "^\\* Settings" nil t)
              (let ((props (org-entry-properties nil 'standard)))
                (setq default-backend (cdr (assoc "DEFAULT_BACKEND" props)))
                (setq default-model  (cdr (assoc "DEFAULT_MODEL" props)))))
            ;; Parse each level-2 heading under Backends
            (goto-char (point-min))
            (when (re-search-forward "^\\* Backends" nil t)
              (let ((section-end (save-excursion
                                   (org-end-of-subtree t)
                                   (point))))
                (while (re-search-forward "^\\*\\* \\(.+\\)" section-end t)
                  (let* ((name  (string-trim (match-string-no-properties 1)))
                         (props (org-entry-properties nil 'standard))
                         (host  (cdr (assoc "HOST" props))))
                    (when host ; skip entries without HOST
                      (push (list :name name
                                  :type (or (cdr (assoc "TYPE" props))
                                            "openai-compatible")
                                  :host host
                                  :endpoint (or (cdr (assoc "ENDPOINT" props))
                                                "/v1/chat/completions")
                                  :stream (equal (cdr (assoc "STREAM" props)) "t")
                                  :auth-host (or (cdr (assoc "AUTH_HOST" props)) host)
                                  :models (my/orgseq--collect-list-items))
                            backends))))))
            (list :default-backend default-backend
                  :default-model default-model
                  :backends (nreverse backends))))
      (error
       (message "org-seq: failed to parse %s: %s" my/orgseq-ai-config err)
       nil))))

(defun my/orgseq--apply-ai-config ()
  "Apply parsed .orgseq/ai-config.org settings to gptel.
Returns non-nil on success.  On failure (missing file, parse error)
returns nil so the caller can fall back to hardcoded defaults."
  (when-let ((config (my/orgseq--parse-ai-config)))
    (let ((backends-cfg (plist-get config :backends))
          (default-name (plist-get config :default-backend))
          (default-model (plist-get config :default-model))
          chosen-backend)
      (dolist (b backends-cfg)
        (let* ((name      (plist-get b :name))
               (auth-host (plist-get b :auth-host))
               (models    (mapcar #'intern (plist-get b :models)))
               (backend
                (pcase (plist-get b :type)
                  ((or "openai-compatible" "openai")
                   (gptel-make-openai name
                     :host     (plist-get b :host)
                     :endpoint (plist-get b :endpoint)
                     :stream   (plist-get b :stream)
                     :key      (let ((h auth-host))
                                 (lambda () (my/gptel-api-key h)))
                     :models   models))
                  ("ollama"
                   (when (fboundp 'gptel-make-ollama)
                     (gptel-make-ollama name
                       :host   (plist-get b :host)
                       :stream (plist-get b :stream)
                       :models models)))
                  (type
                   (message "org-seq: unknown backend type '%s' for %s" type name)
                   nil))))
          (when (and backend (equal name default-name))
            (setq chosen-backend backend))))
      (when chosen-backend
        (setq gptel-backend chosen-backend))
      (when default-model
        (setq gptel-model (intern default-model)))
      (message "org-seq: AI config loaded from .orgseq/ai-config.org")
      t)))

;; Ensure config file exists on module load (incremental — no-op if present)
(my/orgseq--ensure-ai-config)

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Purpose + Schema persistent context
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Inspired by llm_wiki's purpose.md + schema.md pattern:
;; purpose.org defines your knowledge base goals and research scope.
;; schema.org defines note types, tag conventions, and linking rules.
;; Both are auto-injected into gptel's system prompt so every AI interaction
;; understands your PKM context without manual repetition.

(defcustom my/ai-purpose-file
  (expand-file-name "purpose.org" my/roam-dir)
  "Path to the purpose.org file defining knowledge base goals and scope.
Auto-injected into gptel system prompts.  Edit to define your research
interests, key questions, and knowledge domains."
  :type 'file :group 'org-seq)

(defcustom my/ai-schema-file
  (expand-file-name "schema.org" my/roam-dir)
  "Path to the schema.org file defining note structure rules.
Auto-injected into gptel system prompts.  Edit to define your note
types, tag conventions, and linking rules."
  :type 'file :group 'org-seq)

(defun my/ai--read-context-file (filepath &optional max-chars)
  "Read FILEPATH and return its content as a string, or empty string if absent.
Truncate to MAX-CHARS if non-nil (default 2000)."
  (if (file-exists-p filepath)
      (let ((content (with-temp-buffer
                       (insert-file-contents filepath)
                       (buffer-string))))
        (if max-chars
            (substring content 0 (min (length content) max-chars))
          content))
    ""))

(defun my/ai--build-system-prompt (&optional base-prompt)
  "Build a system prompt with purpose + schema context appended.
BASE-PROMPT is the original prompt text (default: gptel's PKM prompt)."
  (let* ((base (or base-prompt
                   (alist-get 'pkm gptel-directives nil nil #'string=)
                   "You are a helpful PKM assistant in Emacs. \
Respond concisely in the user's language. Preserve org-mode markup \
when working with notes."))
         (purpose (my/ai--read-context-file my/ai-purpose-file))
         (schema  (my/ai--read-context-file my/ai-schema-file))
         (parts   (list base)))
    (unless (string-empty-p purpose)
      (push (format "\n\n## Knowledge Base Purpose\n%s" purpose) parts))
    (unless (string-empty-p schema)
      (push (format "\n\n## Note Structure Rules\n%s" schema) parts))
    (apply #'concat (nreverse parts))))

(defun my/ai--ensure-context-files ()
  "Create purpose.org and schema.org if they don't exist, with template content."
  (dolist (spec `((,my/ai-purpose-file . ,(concat
                   "#+title: Knowledge Base Purpose\n"
                   "#+filetags: :concept:meta:\n\n"
                   "* Purpose\n\n"
                   "Define your knowledge base goals here.\n\n"
                   "* Key Questions\n\n"
                   "- What questions drive your research?\n\n"
                   "* Research Domains\n\n"
                   "- List your main knowledge domains.\n"))
                  (,my/ai-schema-file . ,(concat
                   "#+title: Note Structure Rules\n"
                   "#+filetags: :concept:meta:\n\n"
                   "* Note Types\n\n"
                   "- =concept= — Definitions, explanations, related concepts\n"
                   "- =literature= — Source summaries with core ideas, methodology, relevance\n"
                   "- =fleeting= — Quick captures, processed later\n"
                   "- =daily= — Journal entries, task logs\n\n"
                   "* Tag Conventions\n\n"
                   "- Use =#+filetags:= for broad categories\n"
                   "- Use org-supertag =#tags= for structured data with fields\n"
                   "- Prefix context tags with =@= (e.g., =@work=, =@home=)\n\n"
                   "* Linking Rules\n\n"
                   "- Link to existing notes with =[[id:...]]= or =[[*Heading]]=\n"
                   "- Every note should connect to at least one other note\n"
                   "- Literature notes should link to concepts they reference\n"))))
    (let ((file (car spec))
          (content (cdr spec)))
      (unless (file-exists-p file)
        (make-directory (file-name-directory file) t)
        (with-temp-buffer
          (insert content)
          (write-file file))
        (message "org-seq: created %s" file)))))

;; ---- gptel: LLM client ----
(use-package gptel
  :defer t
  :commands (gptel gptel-send gptel-menu gptel-rewrite gptel-add
             gptel-request gptel-make-openai gptel-make-preset)
  :config
  (setq gptel-default-mode 'org-mode)

  ;; Load backends & default model from .orgseq/ai-config.org
  ;; Falls back to hardcoded OpenRouter if config is missing or broken
  (unless (my/orgseq--apply-ai-config)
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
    (setq gptel-model 'deepseek/deepseek-chat-v3-0324))

  ;; PKM-oriented system prompt — dynamically enriched with purpose + schema context
  ;; The base prompt is stored here; my/ai--build-system-prompt appends context at call time.
  (push '(pkm . "You are a helpful PKM assistant in Emacs. \
Respond concisely in the user's language. Preserve org-mode markup \
when working with notes.")
        gptel-directives)

  ;; Ensure context template files exist on first load
  (my/ai--ensure-context-files)

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
    :system (my/ai--build-system-prompt
             "Summarize the following text concisely, preserving key concepts \
and their relationships. Use the same language as the input. Format with \
org-mode markup.")
    :callback #'my/ai--display-result))

(defun my/ai-suggest-tags ()
  "Suggest org-roam filetags for the current note."
  (interactive)
  (gptel-request (my/ai--get-text)
    :system (my/ai--build-system-prompt
             "Based on this note, suggest 3-5 relevant tags. Output ONLY in \
#+filetags: :tag1:tag2:tag3: format. No explanation.")
    :callback #'my/ai--display-result))

(defun my/ai-translate ()
  "Translate the selected region between Chinese and English."
  (interactive)
  (unless (use-region-p) (user-error "Select a region to translate"))
  (gptel-request (buffer-substring-no-properties (region-beginning) (region-end))
    :system (my/ai--build-system-prompt
             "Translate: Chinese→English or English→Chinese. \
Preserve formatting. Output only the translation.")
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
    :system (my/ai--build-system-prompt
             "Based on this note from a Zettelkasten PKM system, suggest 3-5 \
related concepts. For each, explain the connection briefly. Respond in the \
same language. Use org-mode list format.")
    :callback #'my/ai--display-result))

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 3: Knowledge base overview generation
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Inspired by llm_wiki's overview.md pattern: auto-generate a summary of the
;; entire knowledge base, identifying themes, gaps, and recent activity.

(defun my/ai--roam-stats ()
  "Collect org-roam statistics for overview generation.
Returns a plist with :total-nodes, :recent-nodes,
:tag-distribution and :recent-titles."
  (let* ((all-nodes (org-roam-node-list))
         (total (length all-nodes))
         ;; Get titles of 10 most recently created nodes
         (recent (seq-take
                  (sort all-nodes
                        (lambda (a b)
                          (string> (org-roam-node-file a)
                                   (org-roam-node-file b))))
                  10))
         (recent-titles (mapcar #'org-roam-node-title recent))
         ;; Collect filetags
         (tag-counts (make-hash-table :test #'equal)))
    ;; Count tags from all files
    (dolist (node all-nodes)
      (let ((tags (org-roam-node-tags node)))
        (dolist (tag tags)
          (puthash tag (1+ (gethash tag tag-counts 0)) tag-counts))))
    ;; Sort tags by frequency, take top 15
    (let ((sorted-tags
           (seq-take
            (sort (hash-table-keys tag-counts)
                  (lambda (a b)
                    (> (gethash a tag-counts 0)
                       (gethash b tag-counts 0))))
            15)))
      `(:total-nodes ,total
        :recent-titles ,recent-titles
        :tag-distribution ,(mapcar (lambda (tag)
                                     (cons tag (gethash tag tag-counts 0)))
                                   sorted-tags)))))

(defun my/ai-overview ()
  "Generate or update a knowledge base overview using AI.
Collects org-roam statistics and asks the LLM to summarize themes,
identify gaps, and suggest connections. Result opens in an org buffer."
  (interactive)
  (let* ((stats (my/ai--roam-stats))
         (total (plist-get stats :total-nodes))
         (recent (plist-get stats :recent-titles))
         (tags (plist-get stats :tag-distribution))
         (tag-str (mapconcat
                   (lambda (pair) (format "- %s (%d)" (car pair) (cdr pair)))
                   tags "\n"))
         (recent-str (mapconcat (lambda (title) (format "- %s" title))
                                 recent "\n"))
         (prompt (format
                  (concat "Analyze this personal knowledge base and generate "
                          "an overview report.\n\n"
                          "## Statistics\n"
                          "- Total notes: %d\n\n"
                          "## Top Tags\n%s\n\n"
                          "## Recent Notes\n%s\n\n"
                          "Generate an org-mode overview with these sections:\n"
                          "1. *Themes* — What major knowledge domains are covered?\n"
                          "2. *Gaps* — What topics seem underrepresented?\n"
                          "3. *Connections* — What surprising links could emerge?\n"
                          "4. *Suggestions* — What notes or domains to explore next?\n\n"
                          "Be concise and specific. Use org-mode headings and lists. "
                          "Respond in the same language as the user's notes "
                          "(assume Chinese if unclear).")
                  total tag-str recent-str)))
    (gptel-request prompt
      :system (my/ai--build-system-prompt
               "You are a knowledge base analyst. Generate structured org-mode \
overviews that help the user understand their knowledge landscape, find gaps, \
and discover unexpected connections.")
      :callback
      (lambda (response info)
        (if response
            (let ((overview-file (expand-file-name "overview.org" my/roam-dir)))
              (with-current-buffer (find-file overview-file)
                (erase-buffer)
                (insert (format
                         "#+title: Knowledge Base Overview\n\
#+filetags: :concept:meta:\n\
#+date: %s\n\n"
                         (format-time-string "[%Y-%m-%d %a]")))
                (insert response)
                (save-buffer)
                (message "Overview updated: %s" overview-file)))
          (message "AI request failed: %s" (plist-get info :status)))))))

;; ---- ob-gptel: org-babel integration ----
;; Enables #+begin_src gptel blocks in org notes, executed with C-c C-c.
;; Not on MELPA; install from GitHub via package-vc-install (Emacs 29+).

(unless (package-installed-p 'ob-gptel)
  (if noninteractive
      (message "org-seq: skipping ob-gptel bootstrap in noninteractive session")
    (condition-case err
        (package-vc-install "https://github.com/jwiegley/ob-gptel")
      (error
       (message "WARNING org-seq: failed to install ob-gptel: %s" err)))))

(use-package ob-gptel
  :if (locate-library "ob-gptel")
  :after (org gptel)
  :config
  (add-to-list 'org-babel-load-languages '(gptel . t))
  (org-babel-do-load-languages 'org-babel-load-languages
                               org-babel-load-languages))

;; ---- claude-code: Claude Code CLI inside Emacs ----
;; Runs the Claude Code CLI as an interactive terminal session.
;; Uses eat (Emulate A Terminal) as backend — pure Elisp, works on Windows.

(use-package eat
  :defer t
  :commands (eat-make))

;; inheritenv: required by claude-code, must be installed before it
(use-package inheritenv :defer t)

;; Bootstrap claude-code from GitHub (not on MELPA).  Works on Emacs 29+
;; via package-vc-install.
(unless (package-installed-p 'claude-code)
  (if noninteractive
      (message "org-seq: skipping claude-code bootstrap in noninteractive session")
    (condition-case err
        (package-vc-install "https://github.com/stevemolitor/claude-code.el")
      (error
       (message "WARNING org-seq: failed to install claude-code: %s" err)))))

(use-package claude-code
  :if (locate-library "claude-code")
  :defer t
  :commands (claude-code claude-code-toggle claude-code-transient
             claude-code-send-region claude-code-send-command
             claude-code-send-command-with-context
             claude-code-fix-error-at-point)
  :custom
  (claude-code-terminal-backend 'eat)
  (claude-code-enable-notifications t))

(provide 'init-ai)
;;; init-ai.el ends here
