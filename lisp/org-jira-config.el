;;; org-jira-config.el --- Configuration for org-jira -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Customization group, user options and shared state for org-jira.

;;; Code:

(defgroup org-jira nil
  "Jira items retrieval configuration."
  :group 'tools)

(defcustom jira-base-url "https://jira.yourcompany.com"
  "Base URL for your Jira instance (no trailing slash)."
  :type 'string
  :group 'org-jira)

(defcustom jira-personal-access-token "your-PAT-here"
  "Personal Access Token from your Jira profile."
  :type 'string
  :group 'org-jira)

(defcustom jira-max-results 100
  "Maximum number of results to fetch per request."
  :type 'integer
  :group 'org-jira)

(defvar jira-current-user-info nil
  "Cached information about the current user.")

(provide 'org-jira-config)

;;; org-jira-config.el ends here
