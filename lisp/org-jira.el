;;; org-jira.el --- Jira integration for Org -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Integrates Jira Server/Data Center (Personal Access Token / Bearer
;; authentication) with Org.  Two commands are provided:
;;
;;   `org-jira-insert-org-table'   insert your open Jira items as an Org table
;;   `org-jira-worklog-log-work'   log HH:MM of work on an issue
;;
;; Supports UTF-8 encoding for international characters (Danish: æ, ø, å, etc.)
;;
;; Modules:
;;   org-jira-config     options and shared state
;;   org-jira-api        HTTP transport, connection test
;;   org-jira-query      JQL search and pagination
;;   org-jira-org-table  insert items as Org tables
;;   org-jira-worklog    log work (HH:MM) on issues

;;; Code:

(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-query)
(require 'org-jira-org-table)
(require 'org-jira-worklog)

;;;###autoload
(defun org-jira-insert-org-table ()
  "Insert an Org table with open Jira items at point."
  (interactive)
  (org-jira-org-table-insert-open-items))

(provide 'org-jira)

;;; org-jira.el ends here
