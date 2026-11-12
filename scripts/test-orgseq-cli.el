;;; test-orgseq-cli.el --- Tests for the command line and MCP server -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(load-file
 (expand-file-name "../core/orgseq-cli.el"
                   (file-name-directory load-file-name)))

(ert-deftest my/cli-options-split-flags-values-and-positionals ()
  (pcase-let ((`(,options . ,rest)
               (my/cli--options
                '("A" "note" "--type" "reading" "--field" "YEAR=2024"
                  "--field" "STATUS=queued" "--json")
                '(("--json" . flag) ("--type" . value) ("--field" . multi)))))
    (should (equal rest '("A" "note")))
    (should (equal (cdr (assoc "--type" options)) "reading"))
    (should (equal (cdr (assoc "--field" options))
                   '("YEAR=2024" "STATUS=queued")))
    (should (cdr (assoc "--json" options))))
  (should-error (my/cli--options '("--nope") nil) :type 'user-error)
  (should-error (my/cli--options '("--type") '(("--type" . value)))
                :type 'user-error))

(ert-deftest my/cli-query-params-read-the-filter-as-data ()
  (let ((params (my/cli--query-params
                 '(("--type" . "reading")
                   ("--filter" . "(field \"YEAR\" > 2020)")
                   ("--columns" . "YEAR, STATUS")
                   ("--limit" . "5")))))
    (should (equal (plist-get params :type) "reading"))
    (should (equal (plist-get params :filter) '(field "YEAR" > 2020)))
    (should (equal (plist-get params :columns) '("YEAR" "STATUS")))
    (should (= (plist-get params :limit) 5))))

(ert-deftest my/api-slug-keeps-letters-of-any-script ()
  (should (equal (my/api--slug "Hello,  World!") "hello_world"))
  (should (equal (my/api--slug "统计学 notes") "统计学_notes"))
  (should (equal (my/api--slug "!!!") "note")))

(ert-deftest my/mcp-handshake-and-tool-listing ()
  (let* ((init (my/mcp-handle
                '((jsonrpc . "2.0") (id . 1) (method . "initialize")
                  (params . ((protocolVersion . "2025-03-26"))))))
         (result (alist-get 'result init)))
    (should (equal (alist-get 'id init) 1))
    (should (equal (alist-get 'protocolVersion result) "2025-03-26"))
    (should (assq 'tools (alist-get 'capabilities result))))
  ;; Notifications get no response.
  (should-not (my/mcp-handle '((jsonrpc . "2.0")
                               (method . "notifications/initialized"))))
  (let* ((tools (alist-get 'tools
                           (alist-get 'result
                                      (my/mcp-handle
                                       '((jsonrpc . "2.0") (id . 2)
                                         (method . "tools/list"))))))
         (names (mapcar (lambda (tool) (alist-get 'name tool)) tools)))
    (dolist (name '("search_notes" "get_node" "create_node" "append_daily"
                    "set_field" "set_type" "list_types" "list_views"
                    "query_nodes" "sync_library" "doctor"))
      (should (member name names)))
    ;; The whole listing must serialize: clients reject malformed schemas.
    (should (stringp (my/cli--json (list (cons 'tools tools)))))
    (seq-doseq (tool tools)
      (should (equal "object"
                     (alist-get 'type (alist-get 'inputSchema tool)))))))

(ert-deftest my/mcp-reports-unknown-methods-and-tools ()
  (should (= -32601
             (alist-get 'code
                        (alist-get 'error
                                   (my/mcp-handle '((jsonrpc . "2.0") (id . 3)
                                                    (method . "bogus")))))))
  (should (= -32602
             (alist-get 'code
                        (alist-get 'error
                                   (my/mcp-handle
                                    '((jsonrpc . "2.0") (id . 4)
                                      (method . "tools/call")
                                      (params . ((name . "nope"))))))))))

(ert-deftest my/mcp-tool-failures-are-results-not-protocol-errors ()
  (cl-letf (((symbol-function 'my/api-node)
             (lambda (_id) (user-error "No node with id x"))))
    (let ((result (alist-get 'result
                             (my/mcp-handle
                              '((jsonrpc . "2.0") (id . 5)
                                (method . "tools/call")
                                (params . ((name . "get_node")
                                           (arguments . ((id . "x"))))))))))
      (should (eq t (alist-get 'isError result)))
      (should (string-match-p "No node with id x"
                              (alist-get 'text
                                         (aref (alist-get 'content result) 0)))))))

;;; test-orgseq-cli.el ends here
