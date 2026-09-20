;;; jira-items-test.el --- Offline tests for jira-items -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Tests that stub the HTTP layer.  Run with `make test'.

;;; Code:

(require 'jira-items-test-util)

;;; Query building and pagination

(ert-deftest jira-test-jql-assigned ()
  (jira-test-with-api (jira-test-issues)
    (jira-get-all-assigned-items)
    (should (equal (jira-test-last-jql endpoints)
                   "assignee = currentUser() ORDER BY updated DESC"))))

(ert-deftest jira-test-jql-username ()
  (jira-test-with-api (jira-test-issues)
    (jira-get-all-assigned-items "soren")
    (should (string-prefix-p "assignee = 'soren' " (jira-test-last-jql endpoints)))))

(ert-deftest jira-test-jql-open ()
  (jira-test-with-api (jira-test-issues)
    (jira-get-open-items)
    (should (string-match-p "status NOT IN (Done, Closed, Resolved)"
                            (jira-test-last-jql endpoints)))))

(ert-deftest jira-test-jql-by-status ()
  (jira-test-with-api (jira-test-issues)
    (jira-get-items-by-status '("To Do" "Blocked"))
    (should (string-match-p "status IN ('To Do', 'Blocked')" (jira-test-last-jql endpoints)))
    (jira-get-items-by-status '("Done") t)
    (should (string-match-p "status NOT IN ('Done')" (jira-test-last-jql endpoints)))))

(ert-deftest jira-test-pagination-stitches-pages ()
  (let ((jira-max-results 3)
        (issues (cl-loop for i from 1 to 8 collect (jira-test--issue i "x"))))
    (jira-test-with-api issues
      (let ((result (jira-get-all-assigned-items)))
        (should (equal (mapcar (lambda (i) (alist-get 'key i)) result)
                       (mapcar (lambda (i) (alist-get 'key i)) issues)))
        ;; 1 count request + ceil(8/3) page requests
        (should (= (length endpoints) 4))))))

(ert-deftest jira-test-no-results ()
  (jira-test-with-api nil
    (should (null (jira-get-all-assigned-items)))))

(ert-deftest jira-test-url-encode-non-ascii ()
  (should (equal (jira-url-encode "æøå") "%C3%A6%C3%B8%C3%A5")))

(ert-deftest jira-test-jql-roundtrips-non-ascii ()
  (jira-test-with-api nil
    (jira-get-all-assigned-items "søren")
    (should (string-match-p "søren" (jira-test-last-jql endpoints)))))

;;; Formatting

(ert-deftest jira-test-format-issue-truncates ()
  (let* ((long (make-string 80 ?a))
         (line (jira-format-issue (jira-test--issue 1 long))))
    (should (string-suffix-p (concat (make-string 47 ?a) "...") line))
    (should (string-prefix-p "TST-1" line))))

(ert-deftest jira-test-format-issue-short-summary ()
  (should (string-suffix-p "Æble ø å" (jira-format-issue (jira-test--issue 1 "Æble ø å")))))

(ert-deftest jira-test-group-by ()
  (should (equal (jira-group-by (lambda (x) (mod x 2)) '(1 2 3 4 5))
                 '((1 5 3 1) (0 4 2)))))

;;; Org tables

(ert-deftest jira-test-org-escape ()
  (should (equal (jira--org-escape "a|b") "a\\vertb"))
  (should (equal (jira--org-escape "a[b]|c") "a[b]\\vertc"))
  (should (equal (jira--org-escape "a[b]|c" t) "a{b}\\vertc")))

(defun jira-test--table (fn)
  "Run table-inserting command FN over test issues and return the buffer text."
  (cl-letf (((symbol-function 'jira-get-open-items) (lambda (&rest _) (jira-test-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (funcall fn)
      (buffer-string))))

(ert-deftest jira-test-table-open-items ()
  (let ((text (jira-test--table #'jira-insert-org-table-open-items)))
    (should (string-match-p "TST-1: Æble ø å" text))
    (should (string-match-p "Pipe \\\\vert and \\[brackets\\]" text))
    ;; every data row is a single-column row: exactly two pipes
    (dolist (l (nthcdr 2 (split-string (string-trim text) "\n")))
      (should (= 2 (cl-count ?| l))))))

(ert-deftest jira-test-table-details ()
  (let ((text (jira-test--table #'jira-insert-org-table-with-details)))
    (should (string-match-p "| Key +| Summary +| Status +| Priority" text))
    (dolist (l (nthcdr 2 (split-string (string-trim text) "\n")))
      (should (= 5 (cl-count ?| l))))))

(ert-deftest jira-test-table-links ()
  (let ((jira-base-url "https://jira.example"))
    (let ((text (jira-test--table #'jira-insert-org-table-as-links)))
      (should (string-match-p "\\[\\[https://jira.example/browse/TST-2\\]\\[TST-2: Pipe \\\\vert and {brackets}\\]\\]" text)))))

(ert-deftest jira-test-table-by-status ()
  (cl-letf (((symbol-function 'completing-read-multiple) (lambda (&rest _) '("To Do")))
            ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
            ((symbol-function 'jira-get-items-by-status) (lambda (&rest _) (jira-test-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (with-temp-buffer
      (org-mode)
      (jira-insert-org-table-by-status)
      (should (string-match-p "#\\+CAPTION: Jira Items (Including: To Do)" (buffer-string)))
      (should (string-match-p "| Jira +| Status" (buffer-string))))))

;;; Export

(defun jira-test--export (fn coding)
  "Call export FN with stubs and return the file's contents read as CODING."
  (let ((file (make-temp-file "jira-test"))
        (jira-base-url "https://jira.example"))
    (unwind-protect
        (cl-letf (((symbol-function 'jira-get-all-assigned-items) (lambda (&rest _) (jira-test-issues)))
                  ((symbol-function 'read-file-name) (lambda (&rest _) file)))
          (funcall fn)
          (with-temp-buffer
            (let ((coding-system-for-read coding))
              (insert-file-contents file))
            (buffer-string)))
      (delete-file file))))

(ert-deftest jira-test-export-org ()
  (let ((text (jira-test--export #'jira-export-to-org 'utf-8)))
    (should (string-prefix-p "#+TITLE: Jira Items" text))
    (should (string-match-p "^\\* TO_DO Æble ø å$" text))
    (should (string-match-p ":URL: https://jira.example/browse/TST-1" text))
    (should (= 4 (with-temp-buffer (insert text) (how-many "^  :KEY: " (point-min)))))))

(ert-deftest jira-test-export-csv ()
  (let ((text (jira-test--export #'jira-export-to-csv 'raw-text)))
    ;; UTF-8 BOM for Excel
    (should (string-prefix-p "\357\273\277Key,Summary" text))
    ;; embedded quotes doubled, Danish chars UTF-8 encoded
    (should (string-match-p "\"Quote \"\"inside\"\" summary\"" text))
    (should (string-match-p (regexp-quote (encode-coding-string "Æble ø å" 'utf-8)) text))))

(provide 'jira-items-test)

;;; jira-items-test.el ends here
