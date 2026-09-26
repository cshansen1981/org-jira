;;; org-jira-task.el --- Create Jira tasks from Org headings -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Create a Jira task, or subtask, from the Org heading at point.
;;
;; If an ancestor heading already has a :KEY: property, a subtask is
;; created under that issue.  Otherwise a task is created under an
;; Epic chosen from the table made by `org-jira-insert-epics' (found
;; by its #+NAME: in `jira-epics-file', not in the buffer the command
;; is invoked in).  Either way, the heading becomes the issue summary
;; and the entry body its description, and the issue is assigned to
;; the current Jira user.  The key of the new issue is stored in the
;; heading's :KEY: property.

;;; Code:

(require 'org)
(require 'org-jira-config)
(require 'org-jira-api)
(require 'org-jira-org-table)

(defvar org-jira-task--epic-link-field-cache nil
  "Epic Link field id discovered from Jira, see `jira-epic-link-field'.")

(defun org-jira-task--epic-link-field ()
  "Return the id of the Epic Link custom field.
Use `jira-epic-link-field' if set, otherwise discover (and cache) it."
  (or jira-epic-link-field
      org-jira-task--epic-link-field-cache
      (setq org-jira-task--epic-link-field-cache
            (let ((field (seq-find
                          (lambda (f)
                            (or (equal (alist-get 'custom (alist-get 'schema f))
                                       "com.pyxis.greenhopper.jira:gh-epic-link")
                                (equal (alist-get 'name f) "Epic Link")))
                          (org-jira-api-request "/rest/api/2/field"))))
              (or (and field (alist-get 'id field))
                  (user-error "Could not find the Epic Link field; set `jira-epic-link-field'"))))))

(defun org-jira-task--epics-in-buffer ()
  "Return the Epics listed in the tables named `org-jira-org-table-epics-name'.
The tables have a Key and a Title column.  The result is an alist of
(\"KEY: title\" . \"KEY\"), without duplicates.  Rows whose first
cell is not a Jira key (the header, rules) are skipped."
  (let (epics)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (format "^[ \t]*#\\+NAME:[ \t]*%s[ \t]*$"
                      (regexp-quote org-jira-org-table-epics-name))
              nil t)
        (forward-line 1)
        (while (looking-at "^[ \t]*|\\(.*\\)|[ \t]*$")
          (let* ((cells (mapcar #'string-trim
                                (split-string (match-string-no-properties 1) "|")))
                 (key (car cells))
                 (title (or (cadr cells) "")))
            (when (string-match-p "\\`[A-Z][A-Z0-9_]*-[0-9]+\\'" key)
              (let ((label (format "%s: %s" key title)))
                (unless (assoc label epics)
                  (push (cons label key) epics)))))
          (forward-line 1))))
    (nreverse epics)))

(defun org-jira-task--epics-file ()
  "Return the expanded, existing path of `jira-epics-file'.
Signal a `user-error' if the option is unset or names a file that does
not exist."
  (unless jira-epics-file
    (user-error "Set `jira-epics-file' to the Org file that has your Epics table"))
  (let ((file (expand-file-name jira-epics-file)))
    (unless (file-exists-p file)
      (user-error "Epics file %s does not exist; run `org-jira-insert-epics' there first" file))
    file))

(defun org-jira-task--epics ()
  "Return the Epics listed in `jira-epics-file'.
See `org-jira-task--epics-in-buffer' for the shape of the result.
Signal a `user-error' if `jira-epics-file' is unset, the file does not
exist, or it has no Epics table."
  (let* ((file (org-jira-task--epics-file))
         (epics (with-current-buffer (find-file-noselect file)
                  (save-excursion
                    (save-restriction
                      (widen)
                      (org-jira-task--epics-in-buffer))))))
    (unless epics
      (user-error "No Epics table named %s in %s; run `org-jira-insert-epics' there first"
                  org-jira-org-table-epics-name file))
    epics))

(defun org-jira-task--read-epic ()
  "Prompt for one of the Epics in `jira-epics-file' and return its key."
  (let ((epics (org-jira-task--epics)))
    (cdr (assoc (completing-read "Epic: " (mapcar #'car epics) nil t) epics))))

(defun org-jira-task--parent-key ()
  "Return the Jira key of the nearest ancestor heading that has one.
Walk upward through the outline, checking each ancestor's own :KEY:
property (not its inherited value), stopping at the first one set.
The heading at point itself is not considered.  Return nil if no
ancestor has a :KEY:."
  (save-excursion
    (org-back-to-heading t)
    (let (key)
      (while (and (not key) (org-up-heading-safe))
        (setq key (org-entry-get nil "KEY")))
      key)))

(defun org-jira-task--heading-summary ()
  "Return the heading text at point without TODO keyword, priority and tags."
  (string-trim (substring-no-properties (org-get-heading t t t t))))

(defun org-jira-task--body ()
  "Return the body of the entry at point, or nil if it is empty.
Property drawers, planning lines and sub-headings are excluded."
  (save-excursion
    (org-back-to-heading t)
    (org-end-of-meta-data t)
    ;; With no body, the end of the metadata is already the next heading.
    (unless (org-at-heading-p)
      (let* ((beg (point))
             (end (progn (outline-next-heading) (point)))
             (body (string-trim (buffer-substring-no-properties beg end))))
        (unless (string-empty-p body) body)))))

(defconst org-jira-task-empty-body-description "."
  "Description sent to Jira when the Org entry has no body.
Some Jira instances require a non-empty description; an empty entry
body would otherwise send none at all.")

(defun org-jira-task--current-username ()
  "Return the Jira username of the currently authenticated user.
Test the connection first (populating `jira-current-user-info') if
that has not already been done."
  (unless jira-current-user-info
    (org-jira-api-test-connection))
  (or (alist-get 'name jira-current-user-info)
      (user-error "Could not determine the current Jira user")))

(defun org-jira-task--project-key (issue-key)
  "Return the project part of ISSUE-KEY, e.g. \"SITE\" from \"SITE-12\"."
  (unless (string-match "\\`\\(.+\\)-[0-9]+\\'" issue-key)
    (user-error "Invalid Jira key %S" issue-key))
  (match-string 1 issue-key))

(defun org-jira-task--base-fields (project-key issue-type summary description)
  "Return the Jira issue-creation fields common to tasks and subtasks.
PROJECT-KEY and ISSUE-TYPE name the project and issue type; SUMMARY is
the issue summary and DESCRIPTION is optional.  The issue is assigned
to the current Jira user."
  `((project . ((key . ,project-key)))
    (summary . ,summary)
    (issuetype . ((name . ,issue-type)))
    (assignee . ((name . ,(org-jira-task--current-username))))
    ,@(when description `((description . ,description)))))

(defun org-jira-task-create-issue (epic-key summary &optional description)
  "Create a task titled SUMMARY under the Epic EPIC-KEY in Jira.
DESCRIPTION is optional.  The project and issue type come from
EPIC-KEY and `jira-task-issue-type'.  The issue is assigned to the
current Jira user.  Return the response from Jira."
  (let ((project (org-jira-task--project-key epic-key)))
    (org-jira-api-request
     "/rest/api/2/issue" "POST"
     `((fields . (,@(org-jira-task--base-fields project jira-task-issue-type summary description)
                  (,(intern (org-jira-task--epic-link-field)) . ,epic-key)))))))

(defun org-jira-task-create-subtask-issue (parent-key summary &optional description)
  "Create a subtask titled SUMMARY under the issue PARENT-KEY in Jira.
DESCRIPTION is optional.  The project comes from PARENT-KEY and the
issue type from `jira-subtask-issue-type'.  The issue is assigned to
the current Jira user.  Return the response from Jira."
  (let ((project (org-jira-task--project-key parent-key)))
    (org-jira-api-request
     "/rest/api/2/issue" "POST"
     `((fields . (,@(org-jira-task--base-fields project jira-subtask-issue-type summary description)
                  (parent . ((key . ,parent-key)))))))))

(defun org-jira-task--finish (response what)
  "Store the key from Jira RESPONSE in the :KEY: property at point.
WHAT names the kind of issue, for the error when RESPONSE has no key.
Return the key."
  (let ((key (alist-get 'key response)))
    (unless key
      (error "Jira did not return a key for the new %s" what))
    (org-entry-put nil "KEY" key)
    key))

;;;###autoload
(defun org-jira-task-create ()
  "Create a Jira task, or subtask, from the Org heading at point.
Point must be on a heading that has no :KEY: property yet.  If an
ancestor heading has one (see `org-jira-task--parent-key'), a subtask
is created under that issue.  Otherwise, prompt for the Epic among
those listed in `jira-epics-file' by `org-jira-insert-epics' and
create a task under it.  Either way, the heading is the summary and
the entry body the description; if the entry has no body,
`org-jira-task-empty-body-description' is sent instead, since Jira may
require a non-empty description.  The issue is assigned to the
current Jira user.  The key of the created issue is written to the
heading's :KEY: property."
  (interactive)
  (unless (and (derived-mode-p 'org-mode) (org-at-heading-p))
    (user-error "Point must be on an Org heading"))
  (let ((existing (org-entry-get nil "KEY")))
    (when existing
      (user-error "This heading already has the Jira key %s" existing)))
  (let ((summary (org-jira-task--heading-summary)))
    (when (string-empty-p summary)
      (user-error "The heading has no text to use as summary"))
    (let ((description (or (org-jira-task--body) org-jira-task-empty-body-description))
          (parent (org-jira-task--parent-key)))
      (if parent
          (let ((key (org-jira-task--finish
                      (org-jira-task-create-subtask-issue parent summary description)
                      "subtask")))
            (message "Created %s as a subtask of %s" key parent)
            key)
        (let* ((epic (org-jira-task--read-epic))
               (key (org-jira-task--finish
                     (org-jira-task-create-issue epic summary description)
                     "task")))
          (message "Created %s under %s" key epic)
          key)))))

(provide 'org-jira-task)

;;; org-jira-task.el ends here
