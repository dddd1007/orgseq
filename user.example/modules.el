;;; modules.el --- Which org-seq modules load -*- lexical-binding: t; -*-
;;
;; Read before any module loads.  List modules to leave out; the full list
;; is `my/init-modules-default' in init.el.  Startup warns when a module
;; that stays enabled depends on one listed here.
;;
;; (setq my/init-disabled-modules '(init-pyim init-python))
;;
;; Optional modules (`my/init-optional-modules') are off until listed
;; here.  init-roam adds org-roam on top of org-seq's own node index: the
;; org-roam backlinks panel, the graph view (org-roam-ui, SPC n g) and
;; the consult-org-roam commands.
;;
;; (setq my/init-enabled-optional-modules '(init-roam))

;;; modules.el ends here
