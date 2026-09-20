;;; jira-items-query.el --- JQL queries for jira-items -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Building and running JQL searches, including pagination.

;;; Code:

(require 'jira-items-config)
(require 'jira-items-api)

(defun jira-search-jql (jql &optional start-at max-results)
  "Search Jira using JQL query.
JQL is the query string.
START-AT is the starting index (default 0).
MAX-RESULTS is the maximum number of results (default `jira-max-results')."
  (let* ((encoded-jql (jira-url-encode jql))
         (start (or start-at 0))
         (max (or max-results jira-max-results))
         (endpoint (format "/rest/api/2/search?jql=%s&startAt=%d&maxResults=%d"
                           encoded-jql start max)))
    (jira-api-request endpoint)))

(defun jira-get-all-assigned-items-with-jql (jql)
  "Get all Jira items using a specific JQL query, following pagination."
  (let ((all-issues '())
        (start-at 0)
        (total nil))
    (message "Executing JQL: %s" jql)
    ;; First request to get total count
    (let ((response (jira-search-jql jql 0 1)))
      (when response
        (setq total (alist-get 'total response))
        (if (= total 0)
            (message "No issues found")
          (message "Found %d issues. Retrieving..." total)
          ;; Fetch all issues with pagination
          (while (< start-at total)
            (let ((batch-response (jira-search-jql jql start-at jira-max-results)))
              (when batch-response
                (let ((issues (alist-get 'issues batch-response)))
                  (setq all-issues (append all-issues issues))
                  (setq start-at (+ start-at (length issues)))
                  (message "Retrieved %d/%d issues..." (length all-issues) total))))))))
    all-issues))

(defun jira--assignee-clause (&optional username)
  "Return the JQL assignee clause for USERNAME, or the current user."
  (if username
      (format "assignee = '%s'" username)
    "assignee = currentUser()"))

(defun jira-get-all-assigned-items (&optional username)
  "Get all Jira items assigned to current user or USERNAME."
  (jira-get-all-assigned-items-with-jql
   (format "%s ORDER BY updated DESC" (jira--assignee-clause username))))

(defun jira-get-open-items (&optional username)
  "Get open Jira items assigned to current user or USERNAME.
Open items are those not in 'Done', 'Closed', or 'Resolved' status."
  (jira-get-all-assigned-items-with-jql
   (format "%s AND status NOT IN (Done, Closed, Resolved) ORDER BY priority DESC, updated DESC"
           (jira--assignee-clause username))))

(defun jira-get-items-by-status (status-list &optional exclude-p username)
  "Get Jira items with specific statuses.
STATUS-LIST is a list of status names.
If EXCLUDE-P is non-nil, exclude these statuses instead.
USERNAME if provided, otherwise current user."
  (let ((status-string (mapconcat (lambda (s) (format "'%s'" s)) status-list ", ")))
    (jira-get-all-assigned-items-with-jql
     (format "%s AND status %s (%s) ORDER BY priority DESC, updated DESC"
             (jira--assignee-clause username)
             (if exclude-p "NOT IN" "IN")
             status-string))))

(provide 'jira-items-query)

;;; jira-items-query.el ends here
