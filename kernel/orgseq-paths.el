;;; orgseq-paths.el --- Library locations -*- lexical-binding: t; -*-
;;
;; Kernel file: no UI, no dependency on any module.  Every path into the
;; note library is defined here once; modules consume these variables and
;; never rebuild a layer name by string.

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 1: Customization group
;; ═══════════════════════════════════════════════════════════════════════════

(defgroup org-seq nil
  "org-seq: Modular Emacs PKM configuration."
  :group 'convenience
  :prefix "my/")

;; ═══════════════════════════════════════════════════════════════════════════
;; Section 2: Library directories
;; ═══════════════════════════════════════════════════════════════════════════

(defun my/note-home--environment-value ()
  "Return ORG_SEQ_NOTE_HOME when it is set to a non-empty value."
  (let ((value (getenv "ORG_SEQ_NOTE_HOME")))
    (when (and value (string-match-p "[^[:space:]]" value))
      value)))

(defconst my/note-home-legacy "~/NoteHQ/"
  "Library location used before notes moved under the Emacs directory.
Only read by the one-time import in init-sync; never written.")

(defun my/note-home--resolve-default ()
  "Return the default library root for `my/note-home'.
The library lives in notes/ under `user-emacs-directory', so org-seq owns
its storage and no folder has to be chosen.  ORG_SEQ_NOTE_HOME overrides
the location; validation runs use it to isolate writes."
  (let* ((raw (or (my/note-home--environment-value)
                  (expand-file-name "notes/" user-emacs-directory)))
         (dir (file-name-as-directory
               (expand-file-name (substitute-in-file-name raw)))))
    (if (file-directory-p dir) (file-truename dir) dir)))

(defcustom my/note-home (my/note-home--resolve-default)
  "Root directory for all PKM content (Roam atomic layer + PARA layers).
Defaults to notes/ under `user-emacs-directory'; devices share it through
init-sync (WebDAV, OneDrive, Google Drive).  ORG_SEQ_NOTE_HOME overrides
the default when set.

Changing this requires restarting Emacs for derived paths
\(`my/roam-dir', `my/orgseq-dir') to take effect."
  :type 'directory
  :group 'org-seq)

(defun my/snapshot-dir--resolve-default ()
  "Return the default directory for library snapshots.
Snapshots sit outside `user-emacs-directory' so that removing or
replacing the Emacs directory cannot take the library and its local
copies together.  ORG_SEQ_SNAPSHOT_DIR overrides the location.  When
ORG_SEQ_NOTE_HOME redirects the library (validation runs), snapshots
follow it into a sibling directory instead of the real data directory."
  (let ((override (getenv "ORG_SEQ_SNAPSHOT_DIR"))
        (note-home (my/note-home--environment-value)))
    (file-name-as-directory
     (expand-file-name
      (cond
       ((and override (string-match-p "[^[:space:]]" override))
        (substitute-in-file-name override))
       (note-home
        (concat (directory-file-name
                 (expand-file-name (substitute-in-file-name note-home)))
                ".snapshots"))
       ((eq system-type 'windows-nt)
        (expand-file-name "org-seq/snapshots"
                          (or (getenv "LOCALAPPDATA") "~/AppData/Local")))
       ((eq system-type 'darwin)
        "~/Library/Application Support/org-seq/snapshots")
       (t
        (expand-file-name "org-seq/snapshots"
                          (or (getenv "XDG_DATA_HOME") "~/.local/share"))))))))

(defcustom my/snapshot-dir (my/snapshot-dir--resolve-default)
  "Directory holding dated local copies of the library; see init-sync.
Kept outside `user-emacs-directory' and outside the library."
  :type 'directory
  :group 'org-seq)

(defcustom my/orgseq-dir (expand-file-name ".orgseq/" my/note-home)
  "Per-library personalized configuration directory.
Analogous to .vscode/ or .cursor/ — stores non-sensitive settings
\(AI backends, capture templates) that customize org-seq behavior
per note library.  Distinct from API keys, which stay in `auth-source'."
  :type 'directory
  :group 'org-seq)

(defcustom my/roam-dir (expand-file-name "00_Roam/" my/note-home)
  "Atomic-notes layer (org-roam-directory equivalent).
Used by `org-roam-directory', `org-mem-watch-dirs',
the node type registry, and the AI context files
\(purpose.org, schema.org, overview.org).

The \"00_\" numeric prefix exists so that the NoteHQ directory
layers sort in workflow priority order (00_Roam first, then
10_Outputs / 20_Practice / 30_Library / 40_Archives) when the
the sidebar displays them alphabetically."
  :type 'directory
  :group 'org-seq)

;; Numeric prefixes (10/20/30/40) ensure the NoteHQ layers sort in
;; workflow priority order in the sidebar.  Keep these central so GTD,
;; Dired, dashboards, and SuperTag do not each hard-code PARA paths.
(defcustom my/outputs-dir (expand-file-name "10_Outputs/" my/note-home)
  "Active deliverables and project outputs under `my/note-home'."
  :type 'directory
  :group 'org-seq)

(defcustom my/practice-dir (expand-file-name "20_Practice/" my/note-home)
  "Long-term practice areas/domains under `my/note-home'."
  :type 'directory
  :group 'org-seq)

(defcustom my/library-dir (expand-file-name "30_Library/" my/note-home)
  "Reference library under `my/note-home'."
  :type 'directory
  :group 'org-seq)

(defcustom my/archives-dir (expand-file-name "40_Archives/" my/note-home)
  "Completed or paused material under `my/note-home'."
  :type 'directory
  :group 'org-seq)

(defcustom my/dashboards-dir (expand-file-name "dashboards/" my/roam-dir)
  "Directory for query-only dashboard org files."
  :type 'directory
  :group 'org-seq)

(defcustom my/types-file
  (expand-file-name "types.org" my/orgseq-dir)
  "Node type registry (Tana supertags / Fibery databases), see init-nodes.
Kept in .orgseq/ so TODO headings inside type templates never reach
the GTD agenda, which scans the PARA layers."
  :type 'file
  :group 'org-seq)

(defcustom my/views-file
  (expand-file-name "views.org" my/orgseq-dir)
  "Saved views (query + layout), one heading per view; see init-views.
Kept in .orgseq/ next to the type registry so it syncs with the library."
  :type 'file
  :group 'org-seq)

(defcustom my/capture-templates-file
  (expand-file-name "capture-templates.el" my/orgseq-dir)
  "User-defined org-roam capture templates file."
  :type 'file
  :group 'org-seq)

(provide 'orgseq-paths)
;;; orgseq-paths.el ends here
