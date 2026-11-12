;;; test-cli-yazi.el --- Tests for CLI popup and yazi helpers -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'package)
(require 'use-package)

(defvar my/note-home)
(defvar my/orgseq-dir)
(defvar my/roam-dir)
(defvar my/outputs-dir)
(defvar my/practice-dir)
(defvar my/library-dir)
(defvar my/archives-dir)
(defvar my/dashboards-dir)
(defvar my/codex-use-powershell-wrapper)
(defvar my/powershell-command)
(defvar my/powershell-popup-arguments)
(defvar my/codex-command)
(defvar my/codex-arguments)
(defvar claude-code-terminal-backend)

(declare-function my/powershell--quote-argument "init-ai-cli" (argument))
(declare-function my/powershell--command-script "init-ai-cli" (command &optional arguments))
(declare-function my/codex--popup-command "init-ai-cli" ())
(declare-function my/codex--popup-arguments "init-ai-cli" ())
(declare-function my/cli-popup-open "init-terminal"
                  (buffer-name command &optional arguments directory height
                               restart display-kind setup-function))
(declare-function my/yazi--read-path-file "init-dired" (file))
(declare-function my/yazi--open-path "init-dired" (path))
(declare-function my/yazi--exit-setup "init-dired"
                  (source-window source-buffer chooser-file cwd-file))

(let ((root (file-name-as-directory
             (expand-file-name "org-seq-test-notehq" temporary-file-directory))))
  (setq my/note-home root
        my/orgseq-dir (expand-file-name ".orgseq/" root)
        my/roam-dir (expand-file-name "00_Roam/" root)
        my/outputs-dir (expand-file-name "10_Outputs/" root)
        my/practice-dir (expand-file-name "20_Practice/" root)
        my/library-dir (expand-file-name "30_Library/" root)
        my/archives-dir (expand-file-name "40_Archives/" root)
        my/dashboards-dir (expand-file-name "dashboards/" my/roam-dir)))

(when (file-directory-p my/orgseq-dir)
  (delete-directory my/orgseq-dir t))

(load-file (expand-file-name "../core/init-packages.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../modules/ui/init-popup.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../modules/tools/init-terminal.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../modules/tools/init-ai.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../modules/tools/init-ai-cli.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../modules/tools/init-dired.el" (file-name-directory load-file-name)))

;; Tests stub Ghostel's public functions and do not need its native module.
(unless (featurep 'ghostel)
  (provide 'ghostel))

(ert-deftest my/ai-config-is-not-created-during-noninteractive-load ()
  (should noninteractive)
  (should-not (file-exists-p my/orgseq-ai-config)))

(ert-deftest my/powershell-quote-argument-uses-single-quote-escaping ()
  (should (equal (my/powershell--quote-argument "C:/Tools/it's/codex.ps1")
                 "'C:/Tools/it''s/codex.ps1'")))

(ert-deftest my/powershell-command-script-resolves-command-and-arguments ()
  (cl-letf (((symbol-function 'my/cli-popup--resolve-command)
             (lambda (_command) "C:/Program Files/Codex/codex.ps1")))
    (should (equal (my/powershell--command-script "codex" '("--model" "gpt 5"))
                   "& 'C:/Program Files/Codex/codex.ps1' '--model' 'gpt 5'"))))

(ert-deftest my/codex-popup-uses-powershell-wrapper-when-enabled ()
  (let ((my/codex-use-powershell-wrapper t)
        (my/powershell-command "pwsh")
        (my/powershell-popup-arguments '("-NoLogo" "-NoExit" "-Command"))
        (my/codex-command "codex")
        (my/codex-arguments '("--profile" "note hq")))
    (cl-letf (((symbol-function 'my/cli-popup--resolve-command)
               (lambda (_command) "C:/Tools/codex.ps1")))
      (should (equal (my/codex--popup-command) "pwsh"))
      (should (equal (my/codex--popup-arguments)
                     '("-NoLogo" "-NoExit" "-Command"
                       "& 'C:/Tools/codex.ps1' '--profile' 'note hq'"))))))

(ert-deftest my/yazi-read-path-file-trims-nuls-and-newlines ()
  (let ((file (make-temp-file "org-seq-yazi-path")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "C:/Users/exrld/NoteHQ\0\r\n"))
          (should (equal (my/yazi--read-path-file file)
                         "C:/Users/exrld/NoteHQ")))
      (delete-file file))))

(ert-deftest my/yazi-open-path-opens-files-with-find-file ()
  (let* ((dir (make-temp-file "org-seq-yazi-dir" t))
         (file (expand-file-name "note.org" dir))
         opened)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+title: Test\n"))
          (cl-letf (((symbol-function 'find-file)
                     (lambda (path) (setq opened path))))
            (my/yazi--open-path file)
            (should (equal opened file))))
      (delete-directory dir t))))

(ert-deftest my/yazi-open-path-opens-directories-with-dirvish-when-available ()
  (let ((dir (make-temp-file "org-seq-yazi-dir" t))
        opened)
    (unwind-protect
        (cl-letf (((symbol-function 'dirvish)
                   (lambda (path) (setq opened (list 'dirvish path)))))
          (my/yazi--open-path dir)
          (should (equal opened (list 'dirvish dir))))
      (delete-directory dir t))))

(ert-deftest my/yazi-ghostel-exit-hook-applies-cwd-and-cleans-files ()
  (let* ((terminal-buffer (generate-new-buffer " *org-seq-yazi-hook-test*"))
         (source-buffer (generate-new-buffer " *org-seq-yazi-source-test*"))
         (target-dir (make-temp-file "org-seq-yazi-cwd" t))
         (chooser-file (make-temp-file "org-seq-yazi-choice"))
         (cwd-file (make-temp-file "org-seq-yazi-cwd")))
    (unwind-protect
        (progn
          (with-temp-file cwd-file
            (insert target-dir "\n"))
          (funcall
           (my/yazi--exit-setup
            nil source-buffer chooser-file cwd-file)
           terminal-buffer)
          (with-current-buffer terminal-buffer
            (run-hook-with-args
             'ghostel-exit-functions terminal-buffer "finished"))
          (with-current-buffer source-buffer
            (should (equal default-directory
                           (file-name-as-directory
                            (file-truename target-dir)))))
          (should-not (file-exists-p chooser-file))
          (should-not (file-exists-p cwd-file)))
      (when (buffer-live-p terminal-buffer) (kill-buffer terminal-buffer))
      (when (buffer-live-p source-buffer) (kill-buffer source-buffer))
      (when (file-exists-p chooser-file) (delete-file chooser-file))
      (when (file-exists-p cwd-file) (delete-file cwd-file))
      (when (file-directory-p target-dir) (delete-directory target-dir t)))))

;;; test-cli-yazi.el ends here
