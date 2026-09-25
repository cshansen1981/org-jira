;;; org-jira-task.el --- Create Jira tasks from Org headings -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Create a Jira task under an Epic from the Org heading at point.
;;
;; The Epic is chosen from the table made by `org-jira-insert-epics'
;; (found by its #+NAME: in `jira-epics-file', not in the buffer the
;; command is invoked in).  The heading becomes the issue summary and
;; the entry body its description.  The key of the new issue is stored
;; in the heading's :KEY: property.

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
The result is an alist of (\"KEY: summary\" . \"KEY\"), without duplicates."
  (let (epics)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (format "^[ \t]*#\\+NAME:[ \t]*%s[ \t]*$"
                      (regexp-quote org-jira-org-table-epics-name))
              nil t)
        (forward-line 1)
        (while (looking-at "^[ \t]*|\\(.*\\)|[ \t]*$")
          (let ((cell (string-trim (match-string-no-properties 1))))
            (when (string-match "\\`\\([A-Z][A-Z0-9_]*-[0-9]+\\): " cell)
              (unless (assoc cell epics)
                (push (cons cell (match-string 1 cell)) epics))))
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

(defun org-jira-task-create-issue (epic-key summary &optional description)
  "Create a task titled SUMMARY under the Epic EPIC-KEY in Jira.
DESCRIPTION is optional.  The project is taken from EPIC-KEY.  Return
the response from Jira."
  (unless (string-match "\\`\\(.+\\)-[0-9]+\\'" epic-key)
    (user-error "Invalid Epic key %S" epic-key))
  (let ((project (match-string 1 epic-key)))
    (org-jira-api-request
     "/rest/api/2/issue" "POST"
     `((fields . ((project . ((key . ,project)))
                  (summary . ,summary)
                  (issuetype . ((name . ,jira-task-issue-type)))
                  (,(intern (org-jira-task--epic-link-field)) . ,epic-key)
                  ,@(when description `((description . ,description)))))))))

;;;###autoload
(defun org-jira-task-create ()
  "Create a Jira task under an Epic from the Org heading at point.
Point must be on a heading that has no :KEY: property yet.  Prompt for
the Epic among those listed in `jira-epics-file' by `org-jira-insert-epics'.
The heading is the summary and the entry body the description.  The
key of the created issue is written to the heading's :KEY: property."
  (interactive)
  (unless (and (derived-mode-p 'org-mode) (org-at-heading-p))
    (user-error "Point must be on an Org heading"))
  (let ((existing (org-entry-get nil "KEY")))
    (when existing
      (user-error "This heading already has the Jira key %s" existing)))
  (let ((summary (org-jira-task--heading-summary)))
    (when (string-empty-p summary)
      (user-error "The heading has no text to use as summary"))
    (let* ((epic (org-jira-task--read-epic))
           (response (org-jira-task-create-issue
                      epic summary (org-jira-task--body)))
           (key (alist-get 'key response)))
      (unless key
        (error "Jira did not return a key for the new task"))
      (org-entry-put nil "KEY" key)
      (message "Created %s under %s" key epic)
      key)))

(provide 'org-jira-task)

;;; org-jira-task.el ends here
