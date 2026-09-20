;;; org-jira-org-table.el --- Insert Jira items as Org tables -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Insert Jira issues below point as an Org table.

;;; Code:

(require 'org)
(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-query)

(defconst org-jira-org-table-epics-name "jira-epics"
  "The #+NAME: given to tables of Epics, so they can be found again.")

(defun org-jira-org-table--escape (string)
  "Escape STRING so it can be used inside an Org table cell.
Pipes become \\vert."
  (replace-regexp-in-string "|" "\\vert" string t t))

(defun org-jira-org-table-insert-issues (issues description &optional name)
  "Insert ISSUES as a one-column Org table below point.
Each row reads \"KEY: summary\".  DESCRIPTION names the kind of issue
for the echo-area message.  If NAME is non-nil the table is preceded by
a #+NAME: line.  If point is not at the start of a line, the table
starts on the next line."
  (if (null issues)
      (message "No %s found" description)
    (unless (bolp)
      (end-of-line)
      (insert "\n"))
    (when name
      (insert (format "#+NAME: %s\n" name)))
    (let ((start (point)))
      (insert "| Jira |\n")
      (insert "|------|\n")
      (dolist (issue issues)
        (let ((key (alist-get 'key issue))
              (summary (alist-get 'summary (alist-get 'fields issue))))
          (insert (format "| %s: %s |\n" key (org-jira-org-table--escape summary)))))
      (save-excursion
        (goto-char start)
        (org-table-align)))
    (message "Inserted %d %s as Org table" (length issues) description)))

(defun org-jira-org-table--insert-fetched (description fetch-function &optional name)
  "Fetch issues with FETCH-FUNCTION and insert them as an Org table below point.
DESCRIPTION names the kind of issue, for messages.  NAME is an optional
#+NAME: for the table."
  (message "Retrieving %s..." description)
  (unless jira-current-user-info
    (org-jira-api-test-connection))
  (org-jira-org-table-insert-issues (funcall fetch-function) description name))

(defun org-jira-org-table-insert-open-items ()
  "Insert an Org table with your open Jira items below point.
The table has one column titled \='Jira\=' containing item titles (key: summary)."
  (org-jira-org-table--insert-fetched "open items" #'org-jira-query-get-open-items))

(defun org-jira-org-table-insert-epics ()
  "Insert an Org table with open Epics of `jira-epic-projects' below point.
The table is named `org-jira-org-table-epics-name' so that
`org-jira-task-create' can find it.  Rows are shaped like those of
`org-jira-org-table-insert-open-items'."
  (org-jira-org-table--insert-fetched
   "epics" #'org-jira-query-get-epics org-jira-org-table-epics-name))

(provide 'org-jira-org-table)

;;; org-jira-org-table.el ends here
