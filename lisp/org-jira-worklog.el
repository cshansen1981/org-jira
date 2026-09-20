;;; org-jira-worklog.el --- Log work on Jira issues -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Log time against a Jira issue.  Durations are given as HH:MM (the
;; format Org clocks use) and sent to Jira as `timeSpentSeconds'.
;;
;; The issue key is taken from, in order: the `jira-key' text property
;; (*Jira Items* buffer), the :KEY: property of the Org entry at point
;; (as written by `org-jira-export-to-org'), or a prompt.

;;; Code:

(require 'org)
(require 'org-jira-config)
(require 'org-jira-api)

(defun org-jira-worklog-hhmm-to-seconds (hhmm)
  "Convert the HH:MM string HHMM to a number of seconds.
Hours may exceed 24.  Signal a `user-error' if HHMM is malformed, has 60
or more minutes, or is zero."
  (unless (and (stringp hhmm)
               (string-match "\\`[ \t]*\\([0-9]+\\):\\([0-9]\\{1,2\\}\\)[ \t]*\\'" hhmm))
    (user-error "Invalid duration %S, expected HH:MM" hhmm))
  (let ((hours (string-to-number (match-string 1 hhmm)))
        (minutes (string-to-number (match-string 2 hhmm))))
    (when (>= minutes 60)
      (user-error "Invalid duration %S: minutes must be below 60" hhmm))
    (when (and (zerop hours) (zerop minutes))
      (user-error "Duration must be greater than zero"))
    (* 60 (+ (* 60 hours) minutes))))

(defun org-jira-worklog-format-started (&optional time)
  "Format TIME (default now) the way Jira expects a worklog start time.
For example \"2026-09-20T10:00:00.000+0200\"."
  (format-time-string "%Y-%m-%dT%H:%M:%S.000%z" time))

(defun org-jira-worklog-payload (hhmm &optional comment started)
  "Build the worklog request body for duration HHMM.
COMMENT is an optional string.  STARTED is a Jira timestamp string,
defaulting to now."
  (append `((timeSpentSeconds . ,(org-jira-worklog-hhmm-to-seconds hhmm))
            (started . ,(or started (org-jira-worklog-format-started))))
          (when (and comment (not (string-empty-p comment)))
            `((comment . ,comment)))))

(defun org-jira-worklog-add (issue-key hhmm &optional comment started)
  "Log HHMM (a HH:MM string) of work on ISSUE-KEY in Jira.
COMMENT is an optional description and STARTED an optional Jira start
timestamp (default now).  Return the created worklog."
  (unless (and (stringp issue-key) (not (string-empty-p issue-key)))
    (user-error "No issue key given"))
  (org-jira-api-request (format "/rest/api/2/issue/%s/worklog" (url-hexify-string issue-key))
                    "POST"
                    (org-jira-worklog-payload hhmm comment started)))

(defun org-jira-worklog--issue-key-at-point ()
  "Return the Jira issue key at point, or nil."
  (or (get-text-property (point) 'jira-key)
      (and (derived-mode-p 'org-mode)
           (org-entry-get nil "KEY" t))))

;;;###autoload
(defun org-jira-worklog-log-work (issue-key hhmm &optional comment)
  "Log HHMM (HH:MM) of work on ISSUE-KEY, with optional COMMENT.
Interactively, the issue key defaults to the one at point."
  (interactive
   (let* ((default (org-jira-worklog--issue-key-at-point))
          (key (read-string (if default
                                (format "Issue key (default %s): " default)
                              "Issue key: ")
                            nil nil default))
          (hhmm (read-string "Time spent (HH:MM): "))
          (comment (read-string "Comment (optional): ")))
     (list key hhmm comment)))
  (let ((seconds (org-jira-worklog-hhmm-to-seconds hhmm)))
    (org-jira-worklog-add issue-key hhmm comment)
    (message "Logged %s (%d min) on %s" hhmm (/ seconds 60) issue-key)))

(provide 'org-jira-worklog)

;;; org-jira-worklog.el ends here
