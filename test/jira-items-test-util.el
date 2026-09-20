;;; jira-items-test-util.el --- Shared helpers for jira-items tests -*- lexical-binding: t; coding: utf-8 -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jira-items)

(defun jira-test--issue (n summary &optional status)
  "Return a Jira issue alist numbered N with SUMMARY and STATUS."
  `((key . ,(format "TST-%d" n))
    (fields . ((summary . ,summary)
               (status . ((name . ,(or status "To Do"))))
               (priority . ((name . "High")))
               (issuetype . ((name . "Task")))
               (project . ((key . "TST")))))))

(defconst jira-test-summaries
  '("Æble ø å" "Pipe | and [brackets]" "Quote \"inside\" summary" "Plain"))

(defun jira-test-issues ()
  "Return issues built from `jira-test-summaries'."
  (let ((n 0))
    (mapcar (lambda (s) (jira-test--issue (cl-incf n) s)) jira-test-summaries)))

(defmacro jira-test-with-api (pages &rest body)
  "Run BODY with `jira-api-request' stubbed to serve search PAGES.
PAGES is an issue list.  The stub honours startAt/maxResults and records
each requested endpoint in the variable `endpoints' (bound for BODY)."
  (declare (indent 1))
  `(let ((endpoints nil)
         (all ,pages))
     (cl-letf (((symbol-function 'jira-api-request)
                (lambda (endpoint &optional _method)
                  (push endpoint endpoints)
                  (let* ((start (if (string-match "startAt=\\([0-9]+\\)" endpoint)
                                    (string-to-number (match-string 1 endpoint)) 0))
                         (size (if (string-match "maxResults=\\([0-9]+\\)" endpoint)
                                   (string-to-number (match-string 1 endpoint)) 50)))
                    `((total . ,(length all))
                      (issues . ,(seq-take (nthcdr start all) size)))))))
       ,@body)))

(defun jira-test-last-jql (endpoints)
  "Decode the JQL from the most recent of ENDPOINTS."
  (when (string-match "jql=\\([^&]*\\)" (car endpoints))
    (decode-coding-string (url-unhex-string (match-string 1 (car endpoints))) 'utf-8)))

(provide 'jira-items-test-util)

;;; jira-items-test-util.el ends here
