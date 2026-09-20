;;; jira-items-api.el --- Jira REST API transport -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Low-level HTTP access to Jira Server/Data Center using Bearer (PAT)
;; authentication.  UTF-8 is used throughout (Danish: æ, ø, å, etc.).

;;; Code:

(require 'url)
(require 'json)
(require 'jira-items-config)

(defun jira-make-headers ()
  "Create headers for Jira API requests."
  `(("Authorization" . ,(concat "Bearer " jira-personal-access-token))
    ("Accept" . "application/json")
    ("Content-Type" . "application/json")))

(defun jira-url-encode (string)
  "URL encode STRING with proper UTF-8 encoding."
  (url-hexify-string (encode-coding-string string 'utf-8)))

(defun jira-api-request (endpoint &optional method)
  "Make a synchronous request to Jira API ENDPOINT using METHOD (default GET)."
  (let* ((url-request-method (or method "GET"))
         (url-request-extra-headers (jira-make-headers))
         (url-request-coding-system 'utf-8)  ; Ensure UTF-8 encoding
         (url (concat jira-base-url endpoint))
         (response-buffer (url-retrieve-synchronously url t t 10)))
    (if response-buffer
        (with-current-buffer response-buffer
          ;; Set buffer encoding to UTF-8
          (set-buffer-multibyte t)
          (decode-coding-region (point-min) (point-max) 'utf-8)
          (goto-char (point-min))
          ;; Skip HTTP headers
          (re-search-forward "^$" nil t)
          (forward-char)
          (let ((json-object-type 'alist)
                (json-array-type 'list)
                (json-key-type 'symbol)
                (json-false nil)
                (json-encoding 'utf-8))  ; Ensure JSON is parsed as UTF-8
            (condition-case err
                (json-read)
              (error
               (message "Error parsing JSON: %s" err)
               (message "Response: %s" (buffer-substring-no-properties (point) (point-max)))
               nil))))
      (error "Failed to retrieve data from %s" url))))

(defun jira-test-connection ()
  "Test the connection to Jira and retrieve user information."
  (interactive)
  (message "Testing Jira connection...")
  (let ((user-info (jira-api-request "/rest/api/2/myself")))
    (if user-info
        (progn
          (setq jira-current-user-info user-info)
          (message "✓ Connected as: %s (%s)"
                   (alist-get 'displayName user-info)
                   (alist-get 'name user-info))
          user-info)
      (error "✗ Failed to connect to Jira. Check your URL and token"))))

(provide 'jira-items-api)

;;; jira-items-api.el ends here
