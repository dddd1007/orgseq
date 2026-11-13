;;; orgseq-paths.el --- Library locations -*- lexical-binding: t; -*-
;;
;; Kernel file: no UI, no dependency on any module.  Every path into the
;; note library is defined here once; modules consume these variables and
;; never rebuild a layer name by string.

(require 'cl-lib)

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
  "Root directory for all PKM content (Inbox, PARA layers, AI System).
Defaults to notes/ under `user-emacs-directory'; devices share it through
init-sync (WebDAV, OneDrive, Google Drive).  ORG_SEQ_NOTE_HOME overrides
the default when set.

Changing this requires restarting Emacs for derived paths
\(`my/inbox-dir', `my/orgseq-dir') to take effect."
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

(defconst my/inbox-dir-legacy-name "00_Roam/"
  "Name of the Inbox layer before 0.2.0.
A library that still has this directory and no 00_Inbox/ keeps working
from the old name until `my/storage-migrate-layout' renames it.")

(defun my/inbox-dir--resolve-default ()
  "Return the default Inbox layer directory under `my/note-home'.
00_Inbox/, except in a library that was not migrated yet: there the old
00_Roam/ directory is used so nothing moves without being asked."
  (let ((new (expand-file-name "00_Inbox/" my/note-home))
        (old (expand-file-name my/inbox-dir-legacy-name my/note-home)))
    (if (and (file-directory-p old) (not (file-directory-p new)))
        old
      new)))

(define-obsolete-variable-alias 'my/roam-dir 'my/inbox-dir "0.2.0")

(defcustom my/inbox-dir (my/inbox-dir--resolve-default)
  "Inbox layer: Daily notes, drafts and captured notes waiting to be filed.
The library has three parts.  The Inbox is the staging area, organized
like an outliner with backlinks: one idea per node, no type or field
required at capture time.  The PARA layers (`my/outputs-dir',
`my/practice-dir', `my/library-dir', `my/archives-dir') hold what was
kept, as typed nodes with fields and views.  `my/ai-dir' holds what the
AI clients share.

The numeric prefixes make the layers sort in workflow order when a
sidebar lists them alphabetically."
  :type 'directory
  :group 'org-seq)

;; PARA layers.  Keep these central so GTD, Dired and dashboards do not
;; each hard-code a layer name.
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

(defcustom my/ai-dir (expand-file-name "50_AI/" my/note-home)
  "AI System layer: what the AI clients share through the CLI and MCP.
Holds the context files (purpose.org, schema.org, overview.org) and the
memory, instruction and skill nodes."
  :type 'directory
  :group 'org-seq)

;; The private zone is deliberately not a layer and not inside the library.
(defun my/private-dir--resolve-default ()
  "Return the default directory of the private zone.
private/ under `user-emacs-directory', beside the library and never
inside it, so that the index, sync, text search and the AI tools rooted
at the library do not reach it.  ORG_SEQ_PRIVATE_DIR overrides the
location.  When ORG_SEQ_NOTE_HOME redirects the library (validation
runs), the zone follows it to a sibling directory."
  (let ((override (getenv "ORG_SEQ_PRIVATE_DIR"))
        (note-home (my/note-home--environment-value)))
    (file-name-as-directory
     (expand-file-name
      (cond
       ((and override (string-match-p "[^[:space:]]" override))
        (substitute-in-file-name override))
       (note-home
        (concat (directory-file-name
                 (expand-file-name (substitute-in-file-name note-home)))
                ".private"))
       (t (expand-file-name "private/" user-emacs-directory)))))))

(defcustom my/private-dir (my/private-dir--resolve-default)
  "Private zone: notes that must stay out of the index, sync and AI tools.
Meant for counseling records.  It is
not a layer of the library: nothing in it is a node, no view, search,
command-line or MCP call returns it, and it is not synced to a remote.
Files are plain Org text and are not encrypted."
  :type 'directory
  :group 'org-seq)

(defun my/private-file-p (file)
  "Return non-nil when FILE lies in the private zone."
  (and file
       (string-prefix-p (file-name-as-directory (expand-file-name my/private-dir))
                        (expand-file-name file))))

(defun my/private-inside-library-p ()
  "Return non-nil when the private zone was configured inside the library.
That defeats the isolation: sync and text search work on the library
directory.  The index still leaves the zone out."
  (string-prefix-p (file-name-as-directory (expand-file-name my/note-home))
                   (file-name-as-directory (expand-file-name my/private-dir))))

(defun my/note-layer (file)
  "Return the layer of the library FILE belongs to, or nil.
One of the symbols `inbox', `project', `area', `resource', `archive'
and `ai'."
  (let ((file (expand-file-name file)))
    (cl-loop for (layer . dir) in `((inbox . ,my/inbox-dir)
                                    (project . ,my/outputs-dir)
                                    (area . ,my/practice-dir)
                                    (resource . ,my/library-dir)
                                    (archive . ,my/archives-dir)
                                    (ai . ,my/ai-dir))
             when (string-prefix-p
                   (file-name-as-directory (expand-file-name dir)) file)
             return layer)))

(defun my/note-layer-dir (layer)
  "Return the directory of LAYER, a symbol accepted by `my/note-layer'."
  (pcase layer
    ('inbox my/inbox-dir)
    ('project my/outputs-dir)
    ('area my/practice-dir)
    ('resource my/library-dir)
    ('archive my/archives-dir)
    ('ai my/ai-dir)
    (_ (error "Unknown library layer: %S" layer))))

(defun my/daily-dir ()
  "Return the directory of Daily notes, daily/ under `my/inbox-dir'.
A function rather than a constant so it follows `my/inbox-dir' when that
is rebound (validation and tests use temporary libraries)."
  (file-name-as-directory (expand-file-name "daily/" my/inbox-dir)))

(defcustom my/dashboards-dir (expand-file-name "dashboards/" my/inbox-dir)
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
  "User capture templates file (org-seq capture template format)."
  :type 'file
  :group 'org-seq)

(provide 'orgseq-paths)
;;; orgseq-paths.el ends here
