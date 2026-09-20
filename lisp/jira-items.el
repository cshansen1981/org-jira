;;; jira-items.el --- Retrieve and display Jira items assigned to you -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Retrieve Jira items assigned to the current user using Personal Access
;; Token (Bearer) authentication for Jira Server/Data Center, and display
;; or export them (buffer, Org file, CSV, Org tables).
;; Supports UTF-8 encoding for international characters (Danish: æ, ø, å, etc.)
;;
;; Modules:
;;   jira-items-config     options and shared state
;;   jira-items-api        HTTP transport, connection test
;;   jira-items-query      JQL search and pagination
;;   jira-items-format     formatting and grouping helpers
;;   jira-items-buffer     *Jira Items* buffer, mode and commands
;;   jira-items-export     export to Org / CSV files
;;   jira-items-org-table  insert items as Org tables

;;; Code:

(require 'jira-items-config)
(require 'jira-items-api)
(require 'jira-items-query)
(require 'jira-items-format)
(require 'jira-items-buffer)
(require 'jira-items-export)
(require 'jira-items-org-table)

;;;###autoload
(defun jira-items ()
  "Retrieve and display Jira items assigned to you."
  (interactive)
  (jira-retrieve-my-items))

;;;###autoload
(defun jira-open-items ()
  "Retrieve and display only open Jira items assigned to you.
Open items exclude those with status: Done, Closed, or Resolved."
  (interactive)
  (jira-retrieve-open-items))

;;;###autoload
(defun jira-items-by-status ()
  "Retrieve and display Jira items filtered by selected status."
  (interactive)
  (jira-retrieve-items-by-status))

;;;###autoload
(defun jira-org-table ()
  "Insert an Org table with open Jira items at point."
  (interactive)
  (jira-insert-org-table-open-items))

(provide 'jira-items)

;;; jira-items.el ends here
