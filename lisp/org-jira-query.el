;;; org-jira-query.el --- JQL queries for org-jira -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Building and running JQL searches, including pagination.

;;; Code:

(require 'org-jira-config)
(require 'org-jira-api)

(defun org-jira-query-search-jql (jql &optional start-at max-results)
  "Search Jira using JQL query.
JQL is the query string.
START-AT is the starting index (default 0).
MAX-RESULTS is the maximum number of results (default `jira-max-results')."
  (let* ((encoded-jql (org-jira-api-url-encode jql))
         (start (or start-at 0))
         (max (or max-results jira-max-results))
         (endpoint (format "/rest/api/2/search?jql=%s&startAt=%d&maxResults=%d"
                           encoded-jql start max)))
    (org-jira-api-request endpoint)))

(defun org-jira-query-get-issues-with-jql (jql)
  "Get all Jira issues matching JQL, following pagination."
  (let ((all-issues '())
        (start-at 0)
        (total nil))
    (message "Executing JQL: %s" jql)
    ;; First request to get total count
    (let ((response (org-jira-query-search-jql jql 0 1)))
      (when response
        (setq total (alist-get 'total response))
        (if (= total 0)
            (message "No issues found")
          (message "Found %d issues. Retrieving..." total)
          ;; Fetch all issues with pagination
          (while (< start-at total)
            (let ((batch-response (org-jira-query-search-jql jql start-at jira-max-results)))
              (when batch-response
                (let ((issues (alist-get 'issues batch-response)))
                  (setq all-issues (append all-issues issues))
                  (setq start-at (+ start-at (length issues)))
                  (message "Retrieved %d/%d issues..." (length all-issues) total))))))))
    all-issues))

(defun org-jira-query--assignee-clause (&optional username)
  "Return the JQL assignee clause for USERNAME, or the current user."
  (if username
      (format "assignee = '%s'" username)
    "assignee = currentUser()"))

(defun org-jira-query-get-open-items (&optional username)
  "Get open Jira items assigned to current user or USERNAME.
Open items are those not in 'Done', 'Closed', or 'Resolved' status."
  (org-jira-query-get-issues-with-jql
   (format "%s AND status NOT IN (Done, Closed, Resolved) ORDER BY priority DESC, updated DESC"
           (org-jira-query--assignee-clause username))))

(defun org-jira-query-get-epics (&optional projects)
  "Get open Epics in PROJECTS (default `jira-epic-projects').
PROJECTS is a list of project names or keys.  Open Epics are those not
in \='Done\=', \='Closed\=', or \='Resolved\=' status."
  (let ((projects (or projects jira-epic-projects)))
    (unless projects
      (user-error "No projects configured in `jira-epic-projects'"))
    (org-jira-query-get-issues-with-jql
     (format "project IN (%s) AND issuetype = Epic AND status NOT IN (Done, Closed, Resolved) ORDER BY project, key"
             (mapconcat (lambda (p) (format "'%s'" p)) projects ", ")))))

(provide 'org-jira-query)

;;; org-jira-query.el ends here
