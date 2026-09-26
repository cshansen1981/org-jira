;;; org-jira-test.el --- Offline tests for org-jira -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Tests that stub the HTTP layer.  Run with `make test'.

;;; Code:

(require 'org-jira-test-util)

;;; Query building and pagination

(ert-deftest org-jira-test-jql-username ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-open-items "soren")
    (should (string-prefix-p "assignee = 'soren' " (org-jira-test-util-last-jql endpoints)))))

(ert-deftest org-jira-test-jql-open ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-open-items)
    (should (string-match-p "status NOT IN (Done, Closed, Resolved)"
                            (org-jira-test-util-last-jql endpoints)))))

(ert-deftest org-jira-test-pagination-stitches-pages ()
  (let ((jira-max-results 3)
        (issues (cl-loop for i from 1 to 8 collect (org-jira-test-util--issue i "x"))))
    (org-jira-test-util-with-api issues
      (let ((result (org-jira-query-get-open-items)))
        (should (equal (mapcar (lambda (i) (alist-get 'key i)) result)
                       (mapcar (lambda (i) (alist-get 'key i)) issues)))
        ;; 1 count request + ceil(8/3) page requests
        (should (= (length endpoints) 4))))))

(ert-deftest org-jira-test-no-results ()
  (org-jira-test-util-with-api nil
    (should (null (org-jira-query-get-open-items)))))

(ert-deftest org-jira-test-url-encode-non-ascii ()
  (should (equal (org-jira-api-url-encode "æøå") "%C3%A6%C3%B8%C3%A5")))

(ert-deftest org-jira-test-jql-roundtrips-non-ascii ()
  (org-jira-test-util-with-api nil
    (org-jira-query-get-open-items "søren")
    (should (string-match-p "søren" (org-jira-test-util-last-jql endpoints)))))

;;; Formatting

;;; Org tables

(ert-deftest org-jira-test-org-escape ()
  (should (equal (org-jira-org-table--escape "a|b") "a\\vertb"))
  (should (equal (org-jira-org-table--escape "a[b]|c") "a[b]\\vertc")))

(defun org-jira-test--table (fn)
  "Run table-inserting command FN over test issues and return the buffer text."
  (cl-letf (((symbol-function 'org-jira-query-get-open-items) (lambda (&rest _) (org-jira-test-util-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (funcall fn)
      (buffer-string))))

(ert-deftest org-jira-test-table-open-items ()
  (let ((text (org-jira-test--table #'org-jira-org-table-insert-open-items)))
    (should (string-prefix-p "#+NAME: JiraItems\n| Key   | Title " text))
    (should (string-match-p "| TST-1 | Æble ø å " text))
    (should (string-match-p "| TST-2 | Pipe \\\\vert and \\[brackets\\] " text))
    ;; every data row is a two-column row: exactly three pipes
    (dolist (l (nthcdr 3 (split-string (string-trim text) "\n")))
      (should (= 3 (cl-count ?| l))))))

;;; Export

;;; Epics

(ert-deftest org-jira-test-epics-jql-default-projects ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-epics)
    (let ((jql (org-jira-test-util-last-jql endpoints)))
      (should (string-match-p "project IN ('Rezilient', 'SITE')" jql))
      (should (string-match-p "issuetype = Epic" jql))
      (should (string-match-p "status NOT IN (Done, Closed, Resolved)" jql))
      (should-not (string-match-p "assignee" jql)))))

(ert-deftest org-jira-test-epics-jql-custom-projects ()
  (org-jira-test-util-with-api nil
    (let ((jira-epic-projects '("ABC")))
      (org-jira-query-get-epics))
    (should (string-match-p "project IN ('ABC')" (org-jira-test-util-last-jql endpoints)))
    (org-jira-query-get-epics '("X" "Y"))
    (should (string-match-p "project IN ('X', 'Y')" (org-jira-test-util-last-jql endpoints)))))

(ert-deftest org-jira-test-epics-no-projects ()
  (let ((jira-epic-projects nil))
    (should-error (org-jira-query-get-epics) :type 'user-error)))

(ert-deftest org-jira-test-epics-table-same-columns-as-open-items ()
  (cl-letf (((symbol-function 'org-jira-query-get-epics) (lambda (&rest _) (org-jira-test-util-issues)))
            ((symbol-function 'org-jira-query-get-open-items) (lambda (&rest _) (org-jira-test-util-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (let ((epics (with-temp-buffer (org-mode) (org-jira-insert-epics) (buffer-string)))
          (open (with-temp-buffer (org-mode) (org-jira-insert-org-table) (buffer-string))))
      (should (equal (string-remove-prefix "#+NAME: jira-epics\n" epics)
                     (string-remove-prefix "#+NAME: JiraItems\n" open)))
      (should (string-match-p "| TST-1 | Æble ø å" epics))
      (should (string-match-p "Pipe \\\\vert and \\[brackets\\]" epics)))))

(ert-deftest org-jira-test-table-inserted-below-point ()
  (cl-letf (((symbol-function 'org-jira-query-get-epics) (lambda (&rest _) (org-jira-test-util-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (insert "* Heading\nsome text here\nafter")
      (goto-char (point-min))
      (search-forward "text")
      (org-jira-insert-epics)
      (let ((text (buffer-string)))
        ;; the line point was on is intact, the table follows it, then the rest
        (should (string-match-p "\\`\\* Heading\nsome text here\n#\\+NAME: jira-epics\n| Key +| Title +|\n" text))
        (should (string-suffix-p "|\n\nafter" text))))))

(ert-deftest org-jira-test-table-at-line-start ()
  (cl-letf (((symbol-function 'org-jira-query-get-epics) (lambda (&rest _) (org-jira-test-util-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (insert "before\n")
      (org-jira-insert-epics)
      (should (string-prefix-p "before\n#+NAME: jira-epics\n| Key" (buffer-string))))))

(ert-deftest org-jira-test-no-epics-inserts-nothing ()
  (cl-letf (((symbol-function 'org-jira-query-get-epics) (lambda (&rest _) nil))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (insert "keep")
      (org-jira-insert-epics)
      (should (equal (buffer-string) "keep")))))

(provide 'org-jira-test)

;;; org-jira-test.el ends here
