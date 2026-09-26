;;; org-jira-task-test.el --- Tests for creating tasks under Epics -*- lexical-binding: t; coding: utf-8 -*-

;;; Code:

(require 'org-jira-test-util)
(require 'org-jira-http-test)

(defconst org-jira-task-test--epics-table
  "#+NAME: jira-epics
| Key    | Title         |
|--------+---------------|
| SITE-1 | Første epic   |
| REZ-22 | Pipe \\vert x |
")

(defmacro org-jira-task-test-with-buffer (text &rest body)
  "Run BODY in an Org buffer containing TEXT, point at the buffer start.
`jira-current-user-info' is pre-populated so that BODY does not
trigger a connection test unless it rebinds it to nil itself."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert ,text)
     (goto-char (point-min))
     (let ((org-jira-task--epic-link-field-cache nil)
           (jira-epic-link-field "customfield_10014")
           (jira-task-issue-type "Task")
           (jira-subtask-issue-type "Sub-task")
           (jira-current-user-info '((name . "csh") (displayName . "Christoffer Hansen"))))
       ,@body)))

(defmacro org-jira-task-test-with-epics-file (content &rest body)
  "Run BODY with `jira-epics-file' bound to a temp file holding CONTENT.
The file (and any buffer visiting it) is removed afterwards."
  (declare (indent 1))
  `(let* ((create-lockfiles nil)
          (file (make-temp-file "org-jira-epics-test" nil ".org" ,content))
          (jira-epics-file file))
     (unwind-protect
         (progn ,@body)
       (let ((buf (find-buffer-visiting file)))
         (when buf (kill-buffer buf)))
       (ignore-errors (delete-file file)))))

(defmacro org-jira-task-test-with-api (response &rest body)
  "Run BODY with `org-jira-api-request' stubbed to return RESPONSE.
Each call's argument list is pushed on the variable `calls'."
  (declare (indent 1))
  `(let (calls)
     (cl-letf (((symbol-function 'org-jira-api-request)
                (lambda (&rest args) (push args calls) ,response)))
       ,@body)))

;;; Epics table

(ert-deftest org-jira-task-test-epics-in-buffer ()
  (org-jira-task-test-with-buffer (concat "text\n" org-jira-task-test--epics-table)
    (should (equal (org-jira-task--epics-in-buffer)
                   '(("SITE-1: Første epic" . "SITE-1")
                     ("REZ-22: Pipe \\vert x" . "REZ-22"))))))

(ert-deftest org-jira-task-test-epics-ignores-unnamed-tables ()
  (org-jira-task-test-with-buffer "| Key | Title |\n|---+---|\n| SITE-5 | not an epic |\n"
    (should (null (org-jira-task--epics-in-buffer)))))

(ert-deftest org-jira-task-test-epics-deduplicates-tables ()
  (org-jira-task-test-with-buffer (concat org-jira-task-test--epics-table "\n"
                                          org-jira-task-test--epics-table)
    (should (= 2 (length (org-jira-task--epics-in-buffer))))))

(ert-deftest org-jira-task-test-epics-round-trip-from-inserted-table ()
  (cl-letf (((symbol-function 'org-jira-query-get-epics)
             (lambda (&rest _) (org-jira-test-util-issues)))
            (jira-current-user-info '((displayName . "x"))))
    (org-jira-task-test-with-buffer ""
      (org-jira-insert-epics)
      (should (equal (mapcar #'cdr (org-jira-task--epics-in-buffer))
                     '("TST-1" "TST-2" "TST-3" "TST-4"))))))

(ert-deftest org-jira-task-test-read-epic-offers-only-named-table ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (let (offered)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt coll &rest _) (setq offered coll) (car coll))))
        (should (equal (org-jira-task--read-epic) "SITE-1"))
        (should (equal offered '("SITE-1: Første epic" "REZ-22: Pipe \\vert x")))))))

;;; Finding the parent issue

(ert-deftest org-jira-task-test-parent-key-no-ancestor ()
  (org-jira-task-test-with-buffer "* Task\n"
    (org-jira-task-test--goto "* Task")
    (should (null (org-jira-task--parent-key)))))

(ert-deftest org-jira-task-test-parent-key-immediate-parent ()
  (org-jira-task-test-with-buffer
      "* Parent\n:PROPERTIES:\n:KEY: SITE-9\n:END:\n** Child\n"
    (org-jira-task-test--goto "** Child")
    (should (equal (org-jira-task--parent-key) "SITE-9"))))

(ert-deftest org-jira-task-test-parent-key-walks-up-past-parent-without-key ()
  (org-jira-task-test-with-buffer
      "* Grandparent\n:PROPERTIES:\n:KEY: SITE-9\n:END:\n** Parent\n*** Child\n"
    (org-jira-task-test--goto "*** Child")
    (should (equal (org-jira-task--parent-key) "SITE-9"))))

(ert-deftest org-jira-task-test-parent-key-ignores-siblings ()
  (org-jira-task-test-with-buffer
      "* Parent\n** Sibling\n:PROPERTIES:\n:KEY: X-1\n:END:\n** Child\n"
    (org-jira-task-test--goto "** Child")
    (should (null (org-jira-task--parent-key)))))

(ert-deftest org-jira-task-test-parent-key-ignores-own-property ()
  (org-jira-task-test-with-buffer
      "* Parent\n:PROPERTIES:\n:KEY: SITE-9\n:END:\n** Child\n:PROPERTIES:\n:KEY: SITE-10\n:END:\n"
    (org-jira-task-test--goto "** Child")
    (should (equal (org-jira-task--parent-key) "SITE-9"))))

;;; Project key

(ert-deftest org-jira-task-test-project-key ()
  (should (equal (org-jira-task--project-key "SITE-12") "SITE"))
  (should (equal (org-jira-task--project-key "MY_P-7") "MY_P")))

(ert-deftest org-jira-task-test-project-key-invalid ()
  (should-error (org-jira-task--project-key "nonsense") :type 'user-error))

;;; Reading Epics from `jira-epics-file'

(ert-deftest org-jira-task-test-epics-file-unset ()
  (let ((jira-epics-file nil))
    (should-error (org-jira-task--epics) :type 'user-error)))

(ert-deftest org-jira-task-test-epics-file-does-not-exist ()
  (let ((jira-epics-file (expand-file-name "no-such-file.org" temporary-file-directory)))
    (should-error (org-jira-task--epics) :type 'user-error)))

(ert-deftest org-jira-task-test-epics-file-without-table ()
  (org-jira-task-test-with-epics-file "nothing here\n"
    (should-error (org-jira-task--epics) :type 'user-error)))

(ert-deftest org-jira-task-test-epics-file-reads-table ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (should (equal (org-jira-task--epics)
                   '(("SITE-1: Første epic" . "SITE-1")
                     ("REZ-22: Pipe \\vert x" . "REZ-22"))))))

(ert-deftest org-jira-task-test-epics-file-does-not-look-at-current-buffer ()
  ;; the current buffer has an Epics table of its own; it must be ignored
  (org-jira-task-test-with-epics-file "no table here\n"
    (org-jira-task-test-with-buffer org-jira-task-test--epics-table
      (should-error (org-jira-task--epics) :type 'user-error))))

(ert-deftest org-jira-task-test-epics-file-reflects-unsaved-buffer-edits ()
  ;; reading works off the live buffer, no save required
  (org-jira-task-test-with-epics-file ""
    (with-current-buffer (find-file-noselect jira-epics-file)
      (goto-char (point-max))
      (insert org-jira-task-test--epics-table))
    (should (equal (mapcar #'cdr (org-jira-task--epics)) '("SITE-1" "REZ-22")))))

;;; Heading and body

(ert-deftest org-jira-task-test-heading-summary ()
  (org-jira-task-test-with-buffer "* TODO [#A] Fix æøå bug :tag1:tag2:\n"
    (should (equal (org-jira-task--heading-summary) "Fix æøå bug"))))

(ert-deftest org-jira-task-test-body ()
  (org-jira-task-test-with-buffer
      "* TODO Task\nSCHEDULED: <2026-09-20 Sun>\n:PROPERTIES:\n:KEY: X\n:END:\nLine one\n\nLine two\n** Sub\nsub body\n* Next\n"
    (should (equal (org-jira-task--body) "Line one\n\nLine two"))))

(ert-deftest org-jira-task-test-body-empty ()
  (org-jira-task-test-with-buffer "* Task\n* Next\nbody\n"
    (should (null (org-jira-task--body))))
  (org-jira-task-test-with-buffer "* Task\n:PROPERTIES:\n:A: b\n:END:\n"
    (should (null (org-jira-task--body)))))

;;; Epic Link field

(ert-deftest org-jira-task-test-field-explicit ()
  (org-jira-task-test-with-buffer ""
    (org-jira-task-test-with-api nil
      (should (equal (org-jira-task--epic-link-field) "customfield_10014"))
      (should (null calls)))))

(ert-deftest org-jira-task-test-field-discovered-and-cached ()
  (org-jira-task-test-with-buffer ""
    (let ((jira-epic-link-field nil))
      (org-jira-task-test-with-api
          '(((id . "summary") (name . "Summary"))
            ((id . "customfield_777") (name . "Epic Link")))
        (should (equal (org-jira-task--epic-link-field) "customfield_777"))
        (should (equal (org-jira-task--epic-link-field) "customfield_777"))
        (should (= (length calls) 1))))))

(ert-deftest org-jira-task-test-field-not-found ()
  (org-jira-task-test-with-buffer ""
    (let ((jira-epic-link-field nil))
      (org-jira-task-test-with-api '(((id . "summary") (name . "Summary")))
        (should-error (org-jira-task--epic-link-field) :type 'user-error)))))

;;; Creating the issue

(ert-deftest org-jira-task-test-create-issue-payload ()
  (org-jira-task-test-with-buffer ""
    (org-jira-task-test-with-api '((key . "SITE-7"))
      (org-jira-task-create-issue "SITE-1" "Sum æ" "Desc")
      (let* ((call (car calls))
             (fields (alist-get 'fields (nth 2 call))))
        (should (equal (nth 0 call) "/rest/api/2/issue"))
        (should (equal (nth 1 call) "POST"))
        (should (equal (alist-get 'key (alist-get 'project fields)) "SITE"))
        (should (equal (alist-get 'summary fields) "Sum æ"))
        (should (equal (alist-get 'name (alist-get 'issuetype fields)) "Task"))
        (should (equal (alist-get 'name (alist-get 'assignee fields)) "csh"))
        (should (equal (alist-get 'customfield_10014 fields) "SITE-1"))
        (should (equal (alist-get 'description fields) "Desc"))))))

(ert-deftest org-jira-task-test-create-issue-tests-connection-when-username-unset ()
  (org-jira-task-test-with-buffer ""
    (let ((jira-current-user-info nil)
          calls)
      (cl-letf (((symbol-function 'org-jira-api-request)
                 (lambda (endpoint &optional method data)
                   (push (list endpoint method data) calls)
                   (if (equal endpoint "/rest/api/2/myself")
                       '((name . "csh") (displayName . "Christoffer Hansen"))
                     '((key . "SITE-7"))))))
        (org-jira-task-create-issue "SITE-1" "Sum")
        ;; the connection is tested (and cached) before the issue is created
        (should (equal (mapcar #'car (reverse calls))
                       '("/rest/api/2/myself" "/rest/api/2/issue")))
        (should (equal jira-current-user-info '((name . "csh") (displayName . "Christoffer Hansen"))))
        (should (equal (alist-get 'name (alist-get 'assignee (alist-get 'fields (nth 2 (car calls)))))
                       "csh"))))))

(ert-deftest org-jira-task-test-create-issue-no-username-errors ()
  (org-jira-task-test-with-buffer ""
    (let ((jira-current-user-info '((displayName . "No name key"))))
      (should-error (org-jira-task-create-issue "SITE-1" "Sum") :type 'user-error))))

(ert-deftest org-jira-task-test-create-issue-without-description ()
  (org-jira-task-test-with-buffer ""
    (org-jira-task-test-with-api '((key . "SITE-7"))
      (org-jira-task-create-issue "SITE-1" "Sum")
      (should-not (assq 'description (alist-get 'fields (nth 2 (car calls))))))))

(ert-deftest org-jira-task-test-create-issue-custom-type-and-project-with-underscore ()
  (org-jira-task-test-with-buffer ""
    (let ((jira-task-issue-type "Opgave"))
      (org-jira-task-test-with-api '((key . "MY_P-7"))
        (org-jira-task-create-issue "MY_P-1" "Sum")
        (let ((fields (alist-get 'fields (nth 2 (car calls)))))
          (should (equal (alist-get 'name (alist-get 'issuetype fields)) "Opgave"))
          (should (equal (alist-get 'key (alist-get 'project fields)) "MY_P")))))))

(ert-deftest org-jira-task-test-create-issue-bad-epic-key ()
  (should-error (org-jira-task-create-issue "nonsense" "Sum") :type 'user-error))

;;; Creating a subtask

(ert-deftest org-jira-task-test-create-subtask-issue-payload ()
  (org-jira-task-test-with-buffer ""
    (org-jira-task-test-with-api '((key . "SITE-8"))
      (org-jira-task-create-subtask-issue "SITE-7" "Sub æ" "Desc")
      (let* ((call (car calls))
             (fields (alist-get 'fields (nth 2 call))))
        (should (equal (nth 0 call) "/rest/api/2/issue"))
        (should (equal (nth 1 call) "POST"))
        (should (equal (alist-get 'key (alist-get 'project fields)) "SITE"))
        (should (equal (alist-get 'summary fields) "Sub æ"))
        (should (equal (alist-get 'name (alist-get 'issuetype fields)) "Sub-task"))
        (should (equal (alist-get 'name (alist-get 'assignee fields)) "csh"))
        (should (equal (alist-get 'key (alist-get 'parent fields)) "SITE-7"))
        (should (equal (alist-get 'description fields) "Desc"))
        ;; subtasks are not linked to an Epic directly, unlike tasks
        (should-not (assq 'customfield_10014 fields))))))

(ert-deftest org-jira-task-test-create-subtask-issue-without-description ()
  (org-jira-task-test-with-buffer ""
    (org-jira-task-test-with-api '((key . "SITE-8"))
      (org-jira-task-create-subtask-issue "SITE-7" "Sub")
      (should-not (assq 'description (alist-get 'fields (nth 2 (car calls))))))))

(ert-deftest org-jira-task-test-create-subtask-issue-custom-type ()
  (org-jira-task-test-with-buffer ""
    (let ((jira-subtask-issue-type "Delopgave"))
      (org-jira-task-test-with-api '((key . "SITE-8"))
        (org-jira-task-create-subtask-issue "SITE-7" "Sub")
        (should (equal (alist-get 'name (alist-get 'issuetype (alist-get 'fields (nth 2 (car calls)))))
                       "Delopgave"))))))

(ert-deftest org-jira-task-test-create-subtask-issue-bad-parent-key ()
  (should-error (org-jira-task-create-subtask-issue "nonsense" "Sub") :type 'user-error))

;;; The command

(defun org-jira-task-test--goto (text)
  "Move point onto the line starting with TEXT."
  (goto-char (point-min))
  (search-forward text)
  (beginning-of-line))

(defconst org-jira-task-test--doc
  "* TODO Write tests :work:\nSome details\nmore\n** Child\n")

(ert-deftest org-jira-task-test-command-happy-path ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (org-jira-task-test-with-buffer org-jira-task-test--doc
      (org-jira-task-test--goto "* TODO Write")
      (org-jira-task-test-with-api '((key . "SITE-42"))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_p coll &rest _) (car coll))))
          (should (equal (org-jira-task-create) "SITE-42")))
        (let ((fields (alist-get 'fields (nth 2 (car calls)))))
          (should (equal (alist-get 'summary fields) "Write tests"))
          (should (equal (alist-get 'description fields) "Some details\nmore"))
          (should (equal (alist-get 'customfield_10014 fields) "SITE-1"))
          (should (equal (alist-get 'name (alist-get 'assignee fields)) "csh")))
        (should (equal (org-entry-get nil "KEY") "SITE-42"))
        ;; the property lives in the drawer of that heading, not the child
        (org-jira-task-test--goto "** Child")
        (should-not (org-entry-get nil "KEY"))))))

(ert-deftest org-jira-task-test-command-empty-body-sends-placeholder-description ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (org-jira-task-test-with-buffer "* Task with no body\n** Child\n"
      (org-jira-task-test--goto "* Task")
      (org-jira-task-test-with-api '((key . "SITE-42"))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_p coll &rest _) (car coll))))
          (org-jira-task-create))
        (should (equal (alist-get 'description (alist-get 'fields (nth 2 (car calls))))
                       org-jira-task-empty-body-description))))))

(ert-deftest org-jira-task-test-command-creates-subtask-when-parent-has-key ()
  ;; no epics file is set up, proving the subtask path never consults it
  (org-jira-task-test-with-buffer
      "* Parent\n:PROPERTIES:\n:KEY: SITE-7\n:END:\n** Child task\nSome body\n"
    (let ((jira-epics-file nil))
      (org-jira-task-test--goto "** Child")
      (org-jira-task-test-with-api '((key . "SITE-8"))
        (should (equal (org-jira-task-create) "SITE-8"))
        (let ((fields (alist-get 'fields (nth 2 (car calls)))))
          (should (equal (alist-get 'summary fields) "Child task"))
          (should (equal (alist-get 'description fields) "Some body"))
          (should (equal (alist-get 'key (alist-get 'parent fields)) "SITE-7"))
          (should (equal (alist-get 'name (alist-get 'issuetype fields)) "Sub-task"))
          (should (equal (alist-get 'name (alist-get 'assignee fields)) "csh")))
        (should (equal (org-entry-get nil "KEY") "SITE-8"))))))

(ert-deftest org-jira-task-test-command-requires-heading ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (org-jira-task-test-with-buffer org-jira-task-test--doc
      (org-jira-task-test--goto "* TODO Write")
      (forward-line 1)                  ; body text, not a heading
      (org-jira-task-test-with-api '((key . "X-1"))
        (should-error (org-jira-task-create) :type 'user-error)
        (should (null calls))))))

(ert-deftest org-jira-task-test-command-refuses-existing-key ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (org-jira-task-test-with-buffer "* Task\n:PROPERTIES:\n:KEY: SITE-5\n:END:\n"
      (org-jira-task-test--goto "* Task")
      (org-jira-task-test-with-api '((key . "X-1"))
        (should-error (org-jira-task-create) :type 'user-error)
        (should (null calls))))))

(ert-deftest org-jira-task-test-command-epics-file-unset ()
  (let ((jira-epics-file nil))
    (org-jira-task-test-with-buffer "* Task\n"
      (org-jira-task-test-with-api '((key . "X-1"))
        (should-error (org-jira-task-create) :type 'user-error)
        (should (null calls))))))

(ert-deftest org-jira-task-test-command-no-key-in-response-writes-nothing ()
  (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
    (org-jira-task-test-with-buffer org-jira-task-test--doc
      (org-jira-task-test--goto "* TODO Write")
      (org-jira-task-test-with-api '((id . "1"))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_p coll &rest _) (car coll))))
          (should-error (org-jira-task-create)))
        (should-not (org-entry-get nil "KEY"))))))

(ert-deftest org-jira-task-test-command-not-in-org-mode ()
  (with-temp-buffer
    (insert "* Task\n")
    (goto-char (point-min))
    (should-error (org-jira-task-create) :type 'user-error)))

;;; HTTP

(ert-deftest org-jira-task-http-test-end-to-end ()
  (org-jira-http-test-with-server
    (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
      (org-jira-task-test-with-buffer org-jira-task-test--doc
        (let ((jira-epic-link-field nil))   ; force discovery through /field
          (org-jira-task-test--goto "* TODO Write")
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_p coll &rest _) (car coll))))
            (should (equal (org-jira-task-create) "TST-99")))
          (should (equal (org-entry-get nil "KEY") "TST-99")))))))

(ert-deftest org-jira-task-http-test-empty-body-against-server-requiring-description ()
  ;; the fake server rejects a blank description with HTTP 400, matching
  ;; a real Jira instance whose create screen requires one
  (org-jira-http-test-with-server
    (org-jira-task-test-with-epics-file org-jira-task-test--epics-table
      (org-jira-task-test-with-buffer "* Task with no body\n"
        (let ((jira-epic-link-field nil))
          (org-jira-task-test--goto "* Task")
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_p coll &rest _) (car coll))))
            (should (equal (org-jira-task-create) "TST-99")))
          (should (equal (org-entry-get nil "KEY") "TST-99")))))))

(ert-deftest org-jira-task-http-test-body-reaches-server-as-utf8 ()
  (org-jira-http-test-with-server
    (org-jira-task-test-with-buffer ""
      (let* ((jira-epic-link-field nil)
             (resp (org-jira-task-create-issue "SITE-1" "Æble ø å" "Beskrivelse æøå"))
             (fields (alist-get 'fields (alist-get 'received resp))))
        (should (equal (alist-get 'summary fields) "Æble ø å"))
        (should (equal (alist-get 'description fields) "Beskrivelse æøå"))
        (should (equal (alist-get 'customfield_10777 fields) "SITE-1"))
        (should (equal (alist-get 'key (alist-get 'project fields)) "SITE"))))))

(ert-deftest org-jira-task-http-test-subtask-end-to-end ()
  ;; no jira-epic-link-field / discovery override needed: a subtask
  ;; never looks up the Epic Link field at all
  (org-jira-http-test-with-server
    (org-jira-task-test-with-buffer
        "* Parent\n:PROPERTIES:\n:KEY: SITE-7\n:END:\n** Child task\nSome body\n"
      (org-jira-task-test--goto "** Child")
      (should (equal (org-jira-task-create) "TST-99"))
      (should (equal (org-entry-get nil "KEY") "TST-99")))))

(ert-deftest org-jira-task-http-test-subtask-body-reaches-server ()
  (org-jira-http-test-with-server
    (org-jira-task-test-with-buffer ""
      (let* ((resp (org-jira-task-create-subtask-issue "SITE-1" "Sub æ" "Beskrivelse æøå"))
             (fields (alist-get 'fields (alist-get 'received resp))))
        (should (equal (alist-get 'summary fields) "Sub æ"))
        (should (equal (alist-get 'description fields) "Beskrivelse æøå"))
        (should (equal (alist-get 'key (alist-get 'parent fields)) "SITE-1"))
        (should (equal (alist-get 'name (alist-get 'issuetype fields)) "Sub-task"))
        (should (equal (alist-get 'key (alist-get 'project fields)) "SITE"))))))

(ert-deftest org-jira-task-http-test-assignee-discovered-via-myself ()
  ;; with no cached user, org-jira-task-create-issue must test the real
  ;; connection first and use the resulting username as the assignee
  (org-jira-http-test-with-server
    (org-jira-task-test-with-buffer ""
      (let* ((jira-epic-link-field nil)
             (jira-current-user-info nil)
             (resp (org-jira-task-create-issue "SITE-1" "Sum" "Desc"))
             (fields (alist-get 'fields (alist-get 'received resp))))
        (should (equal (alist-get 'name (alist-get 'assignee fields)) "soren"))
        (should (equal jira-current-user-info
                       '((displayName . "Søren Åberg") (name . "soren"))))))))

(provide 'org-jira-task-test)

;;; org-jira-task-test.el ends here
