;;; org-jira-org-table.el --- Insert Jira items as Org tables -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Insert Jira items at point as an Org table.

;;; Code:

(require 'org)
(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-query)

(defun org-jira-org-table--escape (string)
  "Escape STRING so it can be used inside an Org table cell.
Pipes become \\vert."
  (replace-regexp-in-string "|" "\\vert" string t t))

(defun org-jira-org-table-insert-open-items ()
  "Insert an Org table with open Jira items at point.
The table has one column titled \='Jira\=' containing item titles (key: summary)."
  (message "Retrieving open Jira items...")
  (unless jira-current-user-info
    (org-jira-api-test-connection))
  (let ((issues (org-jira-query-get-open-items)))
    (if issues
        (progn
          ;; Insert the table header
          (insert "| Jira |\n")
          (insert "|------|\n")
          ;; Insert each issue
          (dolist (issue issues)
            (let* ((key (alist-get 'key issue))
                   (summary (alist-get 'summary (alist-get 'fields issue)))
                   ;; Escape pipe characters in summary to avoid breaking the table
                   (escaped-summary (org-jira-org-table--escape summary))
                   (title (format "%s: %s" key escaped-summary)))
              (insert (format "| %s |\n" title))))
          ;; Align the table
          (when (fboundp 'org-table-align)
            (org-table-align))
          (message "Inserted %d open items as Org table" (length issues)))
      (message "No open items found"))))

(provide 'org-jira-org-table)

;;; org-jira-org-table.el ends here
