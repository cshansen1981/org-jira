;;; jira-items-org-table.el --- Insert Jira items as Org tables -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Commands that insert Jira items at point as Org tables.

;;; Code:

(require 'org)
(require 'jira-items-config)
(require 'jira-items-api)
(require 'jira-items-query)

(defun jira--org-escape (string &optional brackets)
  "Escape STRING so it can be used inside an Org table cell.
Pipes become \\vert.  If BRACKETS is non-nil, square brackets are
replaced by braces so the text is safe inside an Org link description."
  (replace-regexp-in-string
   (if brackets "[]|[]" "|")
   (lambda (x) (pcase x ("|" "\\vert") ("[" "{") ("]" "}")))
   string t t))

(defun jira-insert-org-table-open-items ()
  "Insert an Org table with open Jira items at point.
The table has one column titled 'Jira' containing item titles (key: summary)."
  (interactive)
  (message "Retrieving open Jira items...")
  (unless jira-current-user-info
    (jira-test-connection))
  (let ((issues (jira-get-open-items)))
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
                   (escaped-summary (jira--org-escape summary))
                   (title (format "%s: %s" key escaped-summary)))
              (insert (format "| %s |\n" title))))
          ;; Align the table
          (when (fboundp 'org-table-align)
            (org-table-align))
          (message "Inserted %d open items as Org table" (length issues)))
      (message "No open items found"))))

(defun jira-insert-org-table-with-details ()
  "Insert a detailed Org table with open Jira items at point.
The table includes columns for Key, Summary, Status, and Priority."
  (interactive)
  (message "Retrieving open Jira items...")
  (unless jira-current-user-info
    (jira-test-connection))
  (let ((issues (jira-get-open-items)))
    (if issues
        (progn
          ;; Insert the table header
          (insert "| Key | Summary | Status | Priority |\n")
          (insert "|-----+---------+--------+----------|\n")
          ;; Insert each issue
          (dolist (issue issues)
            (let* ((key (alist-get 'key issue))
                   (fields (alist-get 'fields issue))
                   (summary (alist-get 'summary fields))
                   ;; Escape pipe characters
                   (escaped-summary (jira--org-escape summary))
                   ;; Truncate summary if too long
                   (truncated-summary (if (> (length escaped-summary) 50)
                                          (concat (substring escaped-summary 0 47) "...")
                                        escaped-summary))
                   (status (alist-get 'name (alist-get 'status fields)))
                   (priority (or (alist-get 'name (alist-get 'priority fields)) "None")))
              (insert (format "| %s | %s | %s | %s |\n"
                              key truncated-summary status priority))))
          ;; Align the table
          (when (fboundp 'org-table-align)
            (org-table-align))
          (message "Inserted %d open items as detailed Org table" (length issues)))
      (message "No open items found"))))

(defun jira-insert-org-table-by-status ()
  "Insert an Org table with items grouped by status.
Prompts for which statuses to include or exclude."
  (interactive)
  (let* ((selected (completing-read-multiple "Select status(es): " jira-status-choices))
         (exclude (yes-or-no-p "Exclude these statuses? (No = include only these) ")))
    (message "Retrieving Jira items...")
    (unless jira-current-user-info
      (jira-test-connection))
    (let ((issues (jira-get-items-by-status selected exclude)))
      (if issues
          (progn
            ;; Insert title
            (insert (format "#+CAPTION: Jira Items (%s: %s)\n"
                            (if exclude "Excluding" "Including")
                            (mapconcat 'identity selected ", ")))
            ;; Insert the table header
            (insert "| Jira | Status |\n")
            (insert "|------+--------|\n")
            ;; Insert each issue
            (dolist (issue issues)
              (let* ((key (alist-get 'key issue))
                     (fields (alist-get 'fields issue))
                     (summary (alist-get 'summary fields))
                     (status (alist-get 'name (alist-get 'status fields)))
                     ;; Escape pipe characters
                     (escaped-summary (jira--org-escape summary))
                     (title (format "%s: %s" key escaped-summary)))
                (insert (format "| %s | %s |\n" title status))))
            ;; Align the table
            (when (fboundp 'org-table-align)
              (org-table-align))
            (message "Inserted %d items as Org table" (length issues)))
        (message "No items found with selected criteria")))))

(defun jira-insert-org-table-as-links ()
  "Insert an Org table with open Jira items as clickable links.
Each item becomes a link to the Jira issue."
  (interactive)
  (message "Retrieving open Jira items...")
  (unless jira-current-user-info
    (jira-test-connection))
  (let ((issues (jira-get-open-items)))
    (if issues
        (progn
          ;; Insert the table header
          (insert "| Jira |\n")
          (insert "|------|\n")
          ;; Insert each issue as a link
          (dolist (issue issues)
            (let* ((key (alist-get 'key issue))
                   (summary (alist-get 'summary (alist-get 'fields issue)))
                   ;; Escape pipe and bracket characters
                   (escaped-summary (jira--org-escape summary t))
                   (url (format "%s/browse/%s" jira-base-url key))
                   (link (format "[[%s][%s: %s]]" url key escaped-summary)))
              (insert (format "| %s |\n" link))))
          ;; Align the table
          (when (fboundp 'org-table-align)
            (org-table-align))
          (message "Inserted %d open items as Org table with links" (length issues)))
      (message "No open items found"))))

(provide 'jira-items-org-table)

;;; jira-items-org-table.el ends here
