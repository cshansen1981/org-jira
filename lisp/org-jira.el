;;; org-jira.el --- Retrieve and display Jira items assigned to you -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Retrieve Jira items assigned to the current user using Personal Access
;; Token (Bearer) authentication for Jira Server/Data Center, and display
;; or export them (buffer, Org file, CSV, Org tables).
;; Supports UTF-8 encoding for international characters (Danish: æ, ø, å, etc.)
;;
;; Modules:
;;   org-jira-config     options and shared state
;;   org-jira-api        HTTP transport, connection test
;;   org-jira-query      JQL search and pagination
;;   org-jira-format     formatting and grouping helpers
;;   org-jira-buffer     *Jira Items* buffer, mode and commands
;;   org-jira-export     export to Org / CSV files
;;   org-jira-org-table  insert items as Org tables
;;   org-jira-worklog    log work (HH:MM) on issues

;;; Code:

(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-query)
(require 'org-jira-format)
(require 'org-jira-buffer)
(require 'org-jira-export)
(require 'org-jira-org-table)
(require 'org-jira-worklog)

;;;###autoload
(defun org-jira ()
  "Retrieve and display Jira items assigned to you."
  (interactive)
  (org-jira-buffer-retrieve-my-items))

;;;###autoload
(defun org-jira-open ()
  "Retrieve and display only open Jira items assigned to you.
Open items exclude those with status: Done, Closed, or Resolved."
  (interactive)
  (org-jira-buffer-retrieve-open-items))

;;;###autoload
(defun org-jira-by-status ()
  "Retrieve and display Jira items filtered by selected status."
  (interactive)
  (org-jira-buffer-retrieve-items-by-status))

;;;###autoload
(defun org-jira-insert-org-table ()
  "Insert an Org table with open Jira items at point."
  (interactive)
  (org-jira-org-table-insert-open-items))

(provide 'org-jira)

;;; org-jira.el ends here
