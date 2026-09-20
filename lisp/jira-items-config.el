;;; jira-items-config.el --- Configuration for jira-items -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Customization group, user options and shared state for jira-items.

;;; Code:

(defgroup jira-items nil
  "Jira items retrieval configuration."
  :group 'tools)

(defcustom jira-base-url "https://jira.yourcompany.com"
  "Base URL for your Jira instance (no trailing slash)."
  :type 'string
  :group 'jira-items)

(defcustom jira-personal-access-token "your-PAT-here"
  "Personal Access Token from your Jira profile."
  :type 'string
  :group 'jira-items)

(defcustom jira-max-results 100
  "Maximum number of results to fetch per request."
  :type 'integer
  :group 'jira-items)

(defcustom jira-status-choices
  '("To Do" "In Progress" "In Review" "Testing" "Done" "Closed" "Resolved" "Open" "Blocked")
  "Status names offered when filtering by status."
  :type '(repeat string)
  :group 'jira-items)

(defvar jira-current-user-info nil
  "Cached information about the current user.")

(defvar jira-items-buffer "*Jira Items*"
  "Buffer name for displaying Jira items.")

(provide 'jira-items-config)

;;; jira-items-config.el ends here
