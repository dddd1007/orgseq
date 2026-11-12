;;; modules.el --- Which org-seq modules load -*- lexical-binding: t; -*-
;;
;; Read before any module loads.  List modules to leave out; the full list
;; is `my/init-modules-default' in init.el.  Startup warns when a module
;; that stays enabled depends on one listed here.
;;
;; (setq my/init-disabled-modules '(init-pyim init-python))
;;
;; Your own modules.  Each entry is (FEATURE . REQUIRES): FEATURE is loaded
;; from user/FEATURE.el or user/modules/FEATURE.el (the file must
;; (provide 'FEATURE)), after the modules it requires.  A module whose
;; requirement is unknown or disabled is skipped with a warning.  The load
;; position and any failure show up in M-x my/init-report and
;; M-x my/init-errors.
;;
;; (setq my/init-user-modules '((my-research . (init-org init-nodes))))

;;; modules.el ends here
