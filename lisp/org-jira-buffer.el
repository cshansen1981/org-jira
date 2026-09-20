;;; org-jira-buffer.el --- Buffer UI for org-jira -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; The *Jira Items* buffer: major mode, keymap, rendering and the
;; interactive retrieve commands that populate it.

;;; Code:

(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-query)
(require 'org-jira-format)
(require 'org-jira-export)
(require 'org-jira-worklog)

(define-derived-mode org-jira-buffer-mode special-mode "Jira-Items"
  "Major mode for displaying Jira items.
\\{org-jira-buffer-mode-map}"
  (setq truncate-lines t)
  (setq buffer-read-only t))

(define-key org-jira-buffer-mode-map (kbd "RET") 'org-jira-buffer-open-issue-at-point)
(define-key org-jira-buffer-mode-map (kbd "o") 'org-jira-buffer-open-issue-at-point)
(define-key org-jira-buffer-mode-map (kbd "r") 'org-jira-buffer-refresh)
(define-key org-jira-buffer-mode-map (kbd "e") 'org-jira-export-to-org)
(define-key org-jira-buffer-mode-map (kbd "E") 'org-jira-export-to-csv)
(define-key org-jira-buffer-mode-map (kbd "g") 'org-jira-buffer-refresh)
(define-key org-jira-buffer-mode-map (kbd "a") 'org-jira-buffer-retrieve-my-items)
(define-key org-jira-buffer-mode-map (kbd "O") 'org-jira-buffer-retrieve-open-items)
(define-key org-jira-buffer-mode-map (kbd "s") 'org-jira-buffer-retrieve-items-by-status)
(define-key org-jira-buffer-mode-map (kbd "w") 'org-jira-worklog-log-work)
(define-key org-jira-buffer-mode-map (kbd "q") 'quit-window)

(defun org-jira-buffer-display (issues)
  "Display ISSUES in a buffer."
  (let ((buffer (get-buffer-create org-jira-buffer)))
    (with-current-buffer buffer
      ;; Set UTF-8 encoding for the buffer
      (set-buffer-multibyte t)
      (set-buffer-file-coding-system 'utf-8)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-jira-buffer-mode)

        ;; Header
        (insert "═══ Jira Items ═══\n\n")
        (insert (format "Total items: %d\n" (length issues)))
        (insert (format "URL: %s\n" jira-base-url))
        (insert (format "User: %s\n\n"
                        (or (and jira-current-user-info
                                 (alist-get 'displayName jira-current-user-info))
                            "Unknown")))

        ;; Summary by status
        (let ((status-groups (org-jira-format-group-by
                              (lambda (issue)
                                (alist-get 'name
                                           (alist-get 'status
                                                      (alist-get 'fields issue))))
                              issues)))
          (insert "By Status:\n")
          (dolist (group status-groups)
            (insert (format "  %s: %d\n" (car group) (length (cdr group)))))
          (insert "\n"))

        ;; Column headers
        (insert (propertize
                 (format "%-12s %-10s %-8s %-8s %-6s %s\n"
                         "Key" "Status" "Priority" "Type" "Project" "Summary")
                 'face 'bold))
        (insert (make-string 90 ?─) "\n")

        ;; Issues
        (dolist (issue issues)
          (let ((key (alist-get 'key issue)))
            (insert (propertize (org-jira-format-issue issue)
                                'jira-issue issue
                                'jira-key key))
            (insert "\n")))

        ;; Footer
        (insert "\n" (make-string 90 ?─) "\n")
        (insert "Commands: RET/o: Open | O: Open items | a: All items | s: Filter by status | r: Refresh\n")
        (insert "         e: Export to Org | E: Export to CSV | w: Log work | q: Quit\n")))

    (switch-to-buffer buffer)
    (goto-char (point-min))
    (forward-line 10))) ; Skip header lines

(defun org-jira-buffer-retrieve-my-items ()
  "Retrieve and display all Jira items assigned to you."
  (interactive)
  (condition-case err
      (progn
        (unless jira-current-user-info
          (org-jira-api-test-connection))
        (let ((issues (org-jira-query-get-all-assigned-items)))
          (if issues
              (org-jira-buffer-display issues)
            (message "No issues found assigned to you"))))
    (error (message "Error: %s" (error-message-string err)))))

(defun org-jira-buffer-retrieve-open-items ()
  "Retrieve and display only open Jira items assigned to you."
  (interactive)
  (condition-case err
      (progn
        (unless jira-current-user-info
          (org-jira-api-test-connection))
        (let ((issues (org-jira-query-get-open-items)))
          (if issues
              (progn
                (org-jira-buffer-display issues)
                (with-current-buffer org-jira-buffer
                  (goto-char (point-min))
                  (let ((inhibit-read-only t))
                    (insert "═══ Open Jira Items (Excluding Done/Closed/Resolved) ═══\n\n")
                    (forward-line 2)
                    (delete-region (point) (progn (forward-line 1) (point))))))
            (message "No open issues found assigned to you"))))
    (error (message "Error: %s" (error-message-string err)))))

(defun org-jira-buffer-retrieve-items-by-status ()
  "Retrieve Jira items filtered by status."
  (interactive)
  (let* ((selected (completing-read-multiple "Select status(es): " jira-status-choices))
         (exclude (yes-or-no-p "Exclude these statuses? (No = include only these) ")))
    (condition-case err
        (progn
          (unless jira-current-user-info
            (org-jira-api-test-connection))
          (let ((issues (org-jira-query-get-items-by-status selected exclude)))
            (if issues
                (progn
                  (org-jira-buffer-display issues)
                  (with-current-buffer org-jira-buffer
                    (goto-char (point-min))
                    (let ((inhibit-read-only t))
                      (insert (format "═══ Jira Items (%s: %s) ═══\n\n"
                                      (if exclude "Excluding" "Including")
                                      (mapconcat 'identity selected ", ")))
                      (forward-line 2)
                      (delete-region (point) (progn (forward-line 1) (point))))))
              (message "No issues found with selected criteria"))))
      (error (message "Error: %s" (error-message-string err))))))

(defun org-jira-buffer-open-issue-at-point ()
  "Open the Jira issue at point in a web browser."
  (interactive)
  (let ((key (get-text-property (point) 'jira-key)))
    (if key
        (browse-url (format "%s/browse/%s" jira-base-url key))
      (message "No issue at point"))))

(defun org-jira-buffer-refresh ()
  "Refresh the Jira items display."
  (interactive)
  (org-jira-buffer-retrieve-my-items))

(provide 'org-jira-buffer)

;;; org-jira-buffer.el ends here
