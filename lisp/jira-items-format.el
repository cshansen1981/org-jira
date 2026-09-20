;;; jira-items-format.el --- Issue formatting helpers -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Pure helpers for formatting and grouping issues.

;;; Code:

(defun jira-format-issue (issue)
  "Format a single ISSUE for display."
  (let* ((fields (alist-get 'fields issue))
         (key (alist-get 'key issue))
         (summary (alist-get 'summary fields))
         (status (alist-get 'name (alist-get 'status fields)))
         (priority (or (alist-get 'name (alist-get 'priority fields)) "None"))
         (issue-type (alist-get 'name (alist-get 'issuetype fields)))
         (project (alist-get 'key (alist-get 'project fields))))
    (format "%-12s %-10s %-8s %-8s %-6s %s"
            key status priority issue-type project
            (if (> (length summary) 50)
                (concat (substring summary 0 47) "...")
              summary))))

(defun jira-group-by (key-func list)
  "Group LIST by KEY-FUNC.
KEY-FUNC is a function that takes an element and returns its group key."
  (let ((groups '()))
    (dolist (item list)
      (let* ((key (funcall key-func item))
             (group (assoc key groups)))
        (if group
            (setcdr group (cons item (cdr group)))
          (push (cons key (list item)) groups))))
    (nreverse groups)))

(provide 'jira-items-format)

;;; jira-items-format.el ends here
