;;; org-jira-test-util.el --- Shared helpers for org-jira tests -*- lexical-binding: t; coding: utf-8 -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org-jira)

(defun org-jira-test-util--issue (n summary &optional status)
  "Return a Jira issue alist numbered N with SUMMARY and STATUS."
  `((key . ,(format "TST-%d" n))
    (fields . ((summary . ,summary)
               (status . ((name . ,(or status "To Do"))))
               (priority . ((name . "High")))
               (issuetype . ((name . "Task")))
               (project . ((key . "TST")))))))

(defconst jira-test-summaries
  '("Æble ø å" "Pipe | and [brackets]" "Quote \"inside\" summary" "Plain"))

(defun org-jira-test-util-issues ()
  "Return issues built from `jira-test-summaries'."
  (let ((n 0))
    (mapcar (lambda (s) (org-jira-test-util--issue (cl-incf n) s)) jira-test-summaries)))

(defmacro org-jira-test-util-with-api (pages &rest body)
  "Run BODY with `org-jira-api-request' stubbed to serve search PAGES.
PAGES is an issue list.  The stub honours startAt/maxResults and records
each requested endpoint in the variable `endpoints' (bound for BODY)."
  (declare (indent 1))
  `(let ((endpoints nil)
         (all ,pages))
     (cl-letf (((symbol-function 'org-jira-api-request)
                (lambda (endpoint &optional _method)
                  (push endpoint endpoints)
                  (let* ((start (if (string-match "startAt=\\([0-9]+\\)" endpoint)
                                    (string-to-number (match-string 1 endpoint)) 0))
                         (size (if (string-match "maxResults=\\([0-9]+\\)" endpoint)
                                   (string-to-number (match-string 1 endpoint)) 50)))
                    `((total . ,(length all))
                      (issues . ,(seq-take (nthcdr start all) size)))))))
       ,@body)))

(defun org-jira-test-util-last-jql (endpoints)
  "Decode the JQL from the most recent of ENDPOINTS."
  (when (string-match "jql=\\([^&]*\\)" (car endpoints))
    (decode-coding-string (url-unhex-string (match-string 1 (car endpoints))) 'utf-8)))

(provide 'org-jira-test-util)

;;; org-jira-test-util.el ends here
