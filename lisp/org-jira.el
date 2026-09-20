;;; org-jira.el --- Jira integration for Org -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Integrates Jira Server/Data Center (Personal Access Token / Bearer
;; authentication) with Org.  Four commands are provided:
;;
;;   `org-jira-insert-org-table'   insert your open Jira items as an Org table
;;   `org-jira-insert-epics'       insert open Epics (`jira-epic-projects') as an Org table
;;   `org-jira-task-create'       create a Jira task under an Epic from the heading at point
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
;;   org-jira-task       create tasks under Epics

;;; Code:

(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-query)
(require 'org-jira-org-table)
(require 'org-jira-worklog)
(require 'org-jira-task)

;;;###autoload
(defun org-jira-insert-org-table ()
  "Insert an Org table with open Jira items at point."
  (interactive)
  (org-jira-org-table-insert-open-items))

;;;###autoload
(defun org-jira-insert-epics ()
  "Insert an Org table with open Epics of `jira-epic-projects' below point."
  (interactive)
  (org-jira-org-table-insert-epics))

(provide 'org-jira)

;;; org-jira.el ends here
