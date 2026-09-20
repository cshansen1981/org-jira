;;; jira-items-buffer.el --- Buffer UI for jira-items -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; The *Jira Items* buffer: major mode, keymap, rendering and the
;; interactive retrieve commands that populate it.

;;; Code:

(require 'jira-items-config)
(require 'jira-items-api)
(require 'jira-items-query)
(require 'jira-items-format)
(require 'jira-items-export)

(define-derived-mode jira-items-mode special-mode "Jira-Items"
  "Major mode for displaying Jira items.
\\{jira-items-mode-map}"
  (setq truncate-lines t)
  (setq buffer-read-only t))

(define-key jira-items-mode-map (kbd "RET") 'jira-open-issue-at-point)
(define-key jira-items-mode-map (kbd "o") 'jira-open-issue-at-point)
(define-key jira-items-mode-map (kbd "r") 'jira-refresh)
(define-key jira-items-mode-map (kbd "e") 'jira-export-to-org)
(define-key jira-items-mode-map (kbd "E") 'jira-export-to-csv)
(define-key jira-items-mode-map (kbd "g") 'jira-refresh)
(define-key jira-items-mode-map (kbd "a") 'jira-retrieve-my-items)
(define-key jira-items-mode-map (kbd "O") 'jira-retrieve-open-items)
(define-key jira-items-mode-map (kbd "s") 'jira-retrieve-items-by-status)
(define-key jira-items-mode-map (kbd "q") 'quit-window)

(defun jira-display-items (issues)
  "Display ISSUES in a buffer."
  (let ((buffer (get-buffer-create jira-items-buffer)))
    (with-current-buffer buffer
      ;; Set UTF-8 encoding for the buffer
      (set-buffer-multibyte t)
      (set-buffer-file-coding-system 'utf-8)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (jira-items-mode)

        ;; Header
        (insert "═══ Jira Items ═══\n\n")
        (insert (format "Total items: %d\n" (length issues)))
        (insert (format "URL: %s\n" jira-base-url))
        (insert (format "User: %s\n\n"
                        (or (and jira-current-user-info
                                 (alist-get 'displayName jira-current-user-info))
                            "Unknown")))

        ;; Summary by status
        (let ((status-groups (jira-group-by
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
            (insert (propertize (jira-format-issue issue)
                                'jira-issue issue
                                'jira-key key))
            (insert "\n")))

        ;; Footer
        (insert "\n" (make-string 90 ?─) "\n")
        (insert "Commands: RET/o: Open | O: Open items | a: All items | s: Filter by status | r: Refresh\n")
        (insert "         e: Export to Org | E: Export to CSV | q: Quit\n")))

    (switch-to-buffer buffer)
    (goto-char (point-min))
    (forward-line 10))) ; Skip header lines

(defun jira-retrieve-my-items ()
  "Retrieve and display all Jira items assigned to you."
  (interactive)
  (condition-case err
      (progn
        (unless jira-current-user-info
          (jira-test-connection))
        (let ((issues (jira-get-all-assigned-items)))
          (if issues
              (jira-display-items issues)
            (message "No issues found assigned to you"))))
    (error (message "Error: %s" (error-message-string err)))))

(defun jira-retrieve-open-items ()
  "Retrieve and display only open Jira items assigned to you."
  (interactive)
  (condition-case err
      (progn
        (unless jira-current-user-info
          (jira-test-connection))
        (let ((issues (jira-get-open-items)))
          (if issues
              (progn
                (jira-display-items issues)
                (with-current-buffer jira-items-buffer
                  (goto-char (point-min))
                  (let ((inhibit-read-only t))
                    (insert "═══ Open Jira Items (Excluding Done/Closed/Resolved) ═══\n\n")
                    (forward-line 2)
                    (delete-region (point) (progn (forward-line 1) (point))))))
            (message "No open issues found assigned to you"))))
    (error (message "Error: %s" (error-message-string err)))))

(defun jira-retrieve-items-by-status ()
  "Retrieve Jira items filtered by status."
  (interactive)
  (let* ((selected (completing-read-multiple "Select status(es): " jira-status-choices))
         (exclude (yes-or-no-p "Exclude these statuses? (No = include only these) ")))
    (condition-case err
        (progn
          (unless jira-current-user-info
            (jira-test-connection))
          (let ((issues (jira-get-items-by-status selected exclude)))
            (if issues
                (progn
                  (jira-display-items issues)
                  (with-current-buffer jira-items-buffer
                    (goto-char (point-min))
                    (let ((inhibit-read-only t))
                      (insert (format "═══ Jira Items (%s: %s) ═══\n\n"
                                      (if exclude "Excluding" "Including")
                                      (mapconcat 'identity selected ", ")))
                      (forward-line 2)
                      (delete-region (point) (progn (forward-line 1) (point))))))
              (message "No issues found with selected criteria"))))
      (error (message "Error: %s" (error-message-string err))))))

(defun jira-open-issue-at-point ()
  "Open the Jira issue at point in a web browser."
  (interactive)
  (let ((key (get-text-property (point) 'jira-key)))
    (if key
        (browse-url (format "%s/browse/%s" jira-base-url key))
      (message "No issue at point"))))

(defun jira-refresh ()
  "Refresh the Jira items display."
  (interactive)
  (jira-retrieve-my-items))

(provide 'jira-items-buffer)

;;; jira-items-buffer.el ends here
