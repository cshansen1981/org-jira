;;; org-jira-test.el --- Offline tests for org-jira -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Tests that stub the HTTP layer.  Run with `make test'.

;;; Code:

(require 'org-jira-test-util)

;;; Query building and pagination

(ert-deftest org-jira-test-jql-assigned ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-all-assigned-items)
    (should (equal (org-jira-test-util-last-jql endpoints)
                   "assignee = currentUser() ORDER BY updated DESC"))))

(ert-deftest org-jira-test-jql-username ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-all-assigned-items "soren")
    (should (string-prefix-p "assignee = 'soren' " (org-jira-test-util-last-jql endpoints)))))

(ert-deftest org-jira-test-jql-open ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-open-items)
    (should (string-match-p "status NOT IN (Done, Closed, Resolved)"
                            (org-jira-test-util-last-jql endpoints)))))

(ert-deftest org-jira-test-jql-by-status ()
  (org-jira-test-util-with-api (org-jira-test-util-issues)
    (org-jira-query-get-items-by-status '("To Do" "Blocked"))
    (should (string-match-p "status IN ('To Do', 'Blocked')" (org-jira-test-util-last-jql endpoints)))
    (org-jira-query-get-items-by-status '("Done") t)
    (should (string-match-p "status NOT IN ('Done')" (org-jira-test-util-last-jql endpoints)))))

(ert-deftest org-jira-test-pagination-stitches-pages ()
  (let ((jira-max-results 3)
        (issues (cl-loop for i from 1 to 8 collect (org-jira-test-util--issue i "x"))))
    (org-jira-test-util-with-api issues
      (let ((result (org-jira-query-get-all-assigned-items)))
        (should (equal (mapcar (lambda (i) (alist-get 'key i)) result)
                       (mapcar (lambda (i) (alist-get 'key i)) issues)))
        ;; 1 count request + ceil(8/3) page requests
        (should (= (length endpoints) 4))))))

(ert-deftest org-jira-test-no-results ()
  (org-jira-test-util-with-api nil
    (should (null (org-jira-query-get-all-assigned-items)))))

(ert-deftest org-jira-test-url-encode-non-ascii ()
  (should (equal (org-jira-api-url-encode "æøå") "%C3%A6%C3%B8%C3%A5")))

(ert-deftest org-jira-test-jql-roundtrips-non-ascii ()
  (org-jira-test-util-with-api nil
    (org-jira-query-get-all-assigned-items "søren")
    (should (string-match-p "søren" (org-jira-test-util-last-jql endpoints)))))

;;; Formatting

(ert-deftest org-jira-test-format-issue-truncates ()
  (let* ((long (make-string 80 ?a))
         (line (org-jira-format-issue (org-jira-test-util--issue 1 long))))
    (should (string-suffix-p (concat (make-string 47 ?a) "...") line))
    (should (string-prefix-p "TST-1" line))))

(ert-deftest org-jira-test-format-issue-short-summary ()
  (should (string-suffix-p "Æble ø å" (org-jira-format-issue (org-jira-test-util--issue 1 "Æble ø å")))))

(ert-deftest org-jira-test-group-by ()
  (should (equal (org-jira-format-group-by (lambda (x) (mod x 2)) '(1 2 3 4 5))
                 '((1 5 3 1) (0 4 2)))))

;;; Org tables

(ert-deftest org-jira-test-org-escape ()
  (should (equal (org-jira-org-table--escape "a|b") "a\\vertb"))
  (should (equal (org-jira-org-table--escape "a[b]|c") "a[b]\\vertc"))
  (should (equal (org-jira-org-table--escape "a[b]|c" t) "a{b}\\vertc")))

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
    (should (string-match-p "TST-1: Æble ø å" text))
    (should (string-match-p "Pipe \\\\vert and \\[brackets\\]" text))
    ;; every data row is a single-column row: exactly two pipes
    (dolist (l (nthcdr 2 (split-string (string-trim text) "\n")))
      (should (= 2 (cl-count ?| l))))))

(ert-deftest org-jira-test-table-details ()
  (let ((text (org-jira-test--table #'org-jira-org-table-insert-with-details)))
    (should (string-match-p "| Key +| Summary +| Status +| Priority" text))
    (dolist (l (nthcdr 2 (split-string (string-trim text) "\n")))
      (should (= 5 (cl-count ?| l))))))

(ert-deftest org-jira-test-table-links ()
  (let ((jira-base-url "https://jira.example"))
    (let ((text (org-jira-test--table #'org-jira-org-table-insert-as-links)))
      (should (string-match-p "\\[\\[https://jira.example/browse/TST-2\\]\\[TST-2: Pipe \\\\vert and {brackets}\\]\\]" text)))))

(ert-deftest org-jira-test-table-by-status ()
  (cl-letf (((symbol-function 'completing-read-multiple) (lambda (&rest _) '("To Do")))
            ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
            ((symbol-function 'org-jira-query-get-items-by-status) (lambda (&rest _) (org-jira-test-util-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (org-jira-org-table-insert-by-status)
      (should (string-match-p "#\\+CAPTION: Jira Items (Including: To Do)" (buffer-string)))
      (should (string-match-p "| Jira +| Status" (buffer-string))))))

;;; Export

(defun org-jira-test--export (fn coding)
  "Call export FN with stubs and return the file's contents read as CODING."
  (let ((file (make-temp-file "jira-test"))
        (jira-base-url "https://jira.example"))
    (unwind-protect
        (cl-letf (((symbol-function 'org-jira-query-get-all-assigned-items) (lambda (&rest _) (org-jira-test-util-issues)))
                  ((symbol-function 'read-file-name) (lambda (&rest _) file)))
          (funcall fn)
          (with-temp-buffer
            (let ((coding-system-for-read coding))
              (insert-file-contents file))
            (buffer-string)))
      (delete-file file))))

(ert-deftest org-jira-test-export-org ()
  (let ((text (org-jira-test--export #'org-jira-export-to-org 'utf-8)))
    (should (string-prefix-p "#+TITLE: Jira Items" text))
    (should (string-match-p "^\\* TO_DO Æble ø å$" text))
    (should (string-match-p ":URL: https://jira.example/browse/TST-1" text))
    (should (= 4 (with-temp-buffer (insert text) (how-many "^  :KEY: " (point-min)))))))

(ert-deftest org-jira-test-export-csv ()
  (let ((text (org-jira-test--export #'org-jira-export-to-csv 'raw-text)))
    ;; UTF-8 BOM for Excel
    (should (string-prefix-p "\357\273\277Key,Summary" text))
    ;; embedded quotes doubled, Danish chars UTF-8 encoded
    (should (string-match-p "\"Quote \"\"inside\"\" summary\"" text))
    (should (string-match-p (regexp-quote (encode-coding-string "Æble ø å" 'utf-8)) text))))

(provide 'org-jira-test)

;;; org-jira-test.el ends here
