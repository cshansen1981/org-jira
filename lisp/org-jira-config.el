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

(defcustom jira-epic-projects '("Rezilient" "SITE")
  "Jira projects (names or keys) whose Epics are listed by
`org-jira-insert-epics'."
  :type '(repeat string)
  :group 'org-jira)

(defcustom jira-task-issue-type "Task"
  "Name of the Jira issue type used when creating tasks.
Change this if your instance names it differently (for example a
translated name)."
  :type 'string
  :group 'org-jira)

(defcustom jira-epics-file nil
  "Org file containing the Epics table inserted by `org-jira-insert-epics'.
`org-jira-task-create' reads the Epics available to choose from out of
this file rather than out of the buffer the command is invoked in."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'org-jira)

(defcustom jira-subtask-issue-type "Sub-task"
  "Name of the Jira issue type used when creating subtasks.
Change this if your instance names it differently (for example a
translated name, or without the hyphen)."
  :type 'string
  :group 'org-jira)

(defcustom jira-epic-link-field nil
  "Id of the Jira \"Epic Link\" custom field, e.g. \"customfield_10014\".
When nil the id is looked up once through the Jira field API."
  :type '(choice (const :tag "Discover automatically" nil) string)
  :group 'org-jira)

(defcustom jira-request-timeout 30
  "Seconds to wait for a Jira response before giving up on a request."
  :type 'integer
  :group 'org-jira)

(defcustom jira-request-retries 1
  "Number of times to silently retry a request that gets no response at all.
This does not apply to a response Jira actually sent, such as an HTTP
error status; it only covers the case where the connection produced no
response, for example because Emacs reused a keep-alive connection the
server had already closed."
  :type 'integer
  :group 'org-jira)

(defvar jira-current-user-info nil
  "Cached information about the current user.")

(provide 'org-jira-config)

;;; org-jira-config.el ends here
