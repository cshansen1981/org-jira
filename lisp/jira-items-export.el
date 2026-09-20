;;; jira-items-export.el --- Export Jira items to files -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Export assigned Jira items to an Org file or a CSV file.

;;; Code:

(require 'jira-items-config)
(require 'jira-items-query)

(defun jira-export-to-org ()
  "Export Jira items to an Org mode file."
  (interactive)
  (let ((issues (jira-get-all-assigned-items))
        (filename (read-file-name "Export to Org file: " nil "jira-items.org"))
        (coding-system-for-write 'utf-8))  ; Ensure UTF-8 encoding for output
    (with-temp-file filename
      ;; Set buffer encoding
      (set-buffer-file-coding-system 'utf-8)
      (insert "#+TITLE: Jira Items\n")
      (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))

      (dolist (issue issues)
        (let* ((fields (alist-get 'fields issue))
               (key (alist-get 'key issue))
               (summary (alist-get 'summary fields))
               (status (alist-get 'name (alist-get 'status fields)))
               (priority (or (alist-get 'name (alist-get 'priority fields)) "None"))
               (url (format "%s/browse/%s" jira-base-url key)))
          (insert (format "* %s %s\n"
                          (upcase (replace-regexp-in-string " " "_" status))
                          summary))
          (insert "  :PROPERTIES:\n")
          (insert (format "  :KEY: %s\n" key))
          (insert (format "  :PRIORITY: %s\n" priority))
          (insert (format "  :URL: %s\n" url))
          (insert "  :END:\n\n"))))
    (message "Exported %d items to %s" (length issues) filename)))

(defun jira-export-to-csv ()
  "Export Jira items to a CSV file."
  (interactive)
  (let ((issues (jira-get-all-assigned-items))
        (filename (read-file-name "Export to CSV file: " nil "jira-items.csv"))
        (coding-system-for-write 'utf-8-with-signature))  ; UTF-8 with BOM for Excel compatibility
    (with-temp-file filename
      ;; Set buffer encoding
      (set-buffer-file-coding-system 'utf-8-with-signature)
      (insert "Key,Summary,Status,Priority,Type,Project,URL\n")
      (dolist (issue issues)
        (let* ((fields (alist-get 'fields issue))
               (key (alist-get 'key issue))
               (summary (replace-regexp-in-string "\"" "\"\""
                                                  (alist-get 'summary fields)))
               (status (alist-get 'name (alist-get 'status fields)))
               (priority (or (alist-get 'name (alist-get 'priority fields)) "None"))
               (issue-type (alist-get 'name (alist-get 'issuetype fields)))
               (project (alist-get 'key (alist-get 'project fields)))
               (url (format "%s/browse/%s" jira-base-url key)))
          (insert (format "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n"
                          key summary status priority issue-type project url)))))
    (message "Exported %d items to %s (UTF-8 encoded)" (length issues) filename)))

(provide 'jira-items-export)

;;; jira-items-export.el ends here
