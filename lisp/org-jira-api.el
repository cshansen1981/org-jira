;;; org-jira-api.el --- Jira REST API transport -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Low-level HTTP access to Jira Server/Data Center using Bearer (PAT)
;; authentication.  UTF-8 is used throughout (Danish: æ, ø, å, etc.).

;;; Code:

(require 'url)
(require 'json)
(require 'org-jira-config)

(defun org-jira-api-make-headers ()
  "Create headers for Jira API requests."
  `(("Authorization" . ,(concat "Bearer " jira-personal-access-token))
    ("Accept" . "application/json")
    ("Content-Type" . "application/json")))

(defun org-jira-api-url-encode (string)
  "URL encode STRING with proper UTF-8 encoding."
  (url-hexify-string (encode-coding-string string 'utf-8)))

(defun org-jira-api--error-summary (body)
  "Return a short description of the error response BODY."
  (let ((messages (ignore-errors
                    (alist-get 'errorMessages
                               (let ((json-object-type 'alist)
                                     (json-array-type 'list)
                                     (json-key-type 'symbol))
                                 (json-read-from-string body))))))
    (if messages
        (mapconcat #'identity messages "; ")
      (string-trim (substring body 0 (min 200 (length body)))))))

(defun org-jira-api-request (endpoint &optional method data)
  "Make a synchronous request to Jira API ENDPOINT using METHOD (default GET).
DATA, if non-nil, is a Lisp object (usually an alist) sent as a UTF-8
encoded JSON request body.
Return the parsed JSON response as an alist, or nil if it cannot be parsed.
Signal an error if the server answers with an HTTP status of 400 or above."
  (let* ((url-request-method (or method "GET"))
         (url-request-extra-headers (org-jira-api-make-headers))
         (url-request-data (and data (encode-coding-string (json-encode data) 'utf-8)))
         (url (concat jira-base-url endpoint))
         (response-buffer (url-retrieve-synchronously url t t 10)))
    (unless response-buffer
      (error "Failed to retrieve data from %s" url))
    (unwind-protect
        (let* ((status (buffer-local-value 'url-http-response-status response-buffer))
               (body (with-current-buffer response-buffer
                      ;; The buffer holds raw bytes.  Skip the HTTP headers
                      ;; and decode only the body.
                      (goto-char (point-min))
                      (unless (re-search-forward "\r?\n\r?\n" nil t)
                        (error "Malformed HTTP response from %s" url))
                      (decode-coding-string
                       (buffer-substring-no-properties (point) (point-max))
                       'utf-8))))
          (when (and (integerp status) (>= status 400))
            (error "Jira returned HTTP %d for %s: %s"
                   status endpoint (org-jira-api--error-summary body)))
          (let ((json-object-type 'alist)
                (json-array-type 'list)
                (json-key-type 'symbol)
                (json-false nil))
            (condition-case err
                (json-read-from-string body)
              (error
               (message "Error parsing JSON: %s" err)
               (message "Response: %s" body)
               nil))))
      (kill-buffer response-buffer))))

(defun org-jira-api-test-connection ()
  "Test the connection to Jira and retrieve user information."
  (interactive)
  (message "Testing Jira connection...")
  (let ((user-info (org-jira-api-request "/rest/api/2/myself")))
    (if user-info
        (progn
          (setq jira-current-user-info user-info)
          (message "✓ Connected as: %s (%s)"
                   (alist-get 'displayName user-info)
                   (alist-get 'name user-info))
          user-info)
      (error "✗ Failed to connect to Jira. Check your URL and token"))))

(provide 'org-jira-api)

;;; org-jira-api.el ends here
