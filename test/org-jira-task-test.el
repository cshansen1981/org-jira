;;; org-jira-task-test.el --- Tests for creating tasks under Epics -*- lexical-binding: t; coding: utf-8 -*-

;;; Code:

(require 'org-jira-test-util)
(require 'org-jira-http-test)

(defconst org-jira-task-test--epics-table
  "#+NAME: jira-epics
| Jira                 |
|----------------------|
| SITE-1: Første epic  |
| REZ-22: Pipe \\vert x |
")

(defmacro org-jira-task-test-with-buffer (text &rest body)
  "Run BODY in an Org buffer containing TEXT, point at the buffer start."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert ,text)
     (goto-char (point-min))
     (let ((org-jira-task--epic-link-field-cache nil)
           (jira-epic-link-field "customfield_10014")
           (jira-task-issue-type "Task"))
       ,@body)))

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
  (org-jira-task-test-with-buffer "| Jira |\n|---|\n| SITE-5: not an epic |\n"
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
  (org-jira-task-test-with-buffer org-jira-task-test--epics-table
    (let (offered)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt coll &rest _) (setq offered coll) (car coll))))
        (should (equal (org-jira-task--read-epic) "SITE-1"))
        (should (equal offered '("SITE-1: Første epic" "REZ-22: Pipe \\vert x")))))))

(ert-deftest org-jira-task-test-read-epic-without-table ()
  (org-jira-task-test-with-buffer "nothing here\n"
    (should-error (org-jira-task--read-epic) :type 'user-error)))

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
        (should (equal (alist-get 'customfield_10014 fields) "SITE-1"))
        (should (equal (alist-get 'description fields) "Desc"))))))

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

;;; The command

(defun org-jira-task-test--goto (text)
  "Move point onto the line starting with TEXT."
  (goto-char (point-min))
  (search-forward text)
  (beginning-of-line))

(defconst org-jira-task-test--doc
  (concat org-jira-task-test--epics-table
          "\n* TODO Write tests :work:\nSome details\nmore\n** Child\n"))

(ert-deftest org-jira-task-test-command-happy-path ()
  (org-jira-task-test-with-buffer org-jira-task-test--doc
    (org-jira-task-test--goto "* TODO Write")
    (org-jira-task-test-with-api '((key . "SITE-42"))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_p coll &rest _) (car coll))))
        (should (equal (org-jira-task-create) "SITE-42")))
      (let ((fields (alist-get 'fields (nth 2 (car calls)))))
        (should (equal (alist-get 'summary fields) "Write tests"))
        (should (equal (alist-get 'description fields) "Some details\nmore"))
        (should (equal (alist-get 'customfield_10014 fields) "SITE-1")))
      (should (equal (org-entry-get nil "KEY") "SITE-42"))
      ;; the property lives in the drawer of that heading, not the child
      (org-jira-task-test--goto "** Child")
      (should-not (org-entry-get nil "KEY")))))

(ert-deftest org-jira-task-test-command-requires-heading ()
  (org-jira-task-test-with-buffer org-jira-task-test--doc
    (org-jira-task-test--goto "* TODO Write")
    (forward-line 1)                    ; body text, not a heading
    (org-jira-task-test-with-api '((key . "X-1"))
      (should-error (org-jira-task-create) :type 'user-error)
      (should (null calls)))))

(ert-deftest org-jira-task-test-command-refuses-existing-key ()
  (org-jira-task-test-with-buffer
      (concat org-jira-task-test--epics-table
              "\n* Task\n:PROPERTIES:\n:KEY: SITE-5\n:END:\n")
    (org-jira-task-test--goto "* Task")
    (org-jira-task-test-with-api '((key . "X-1"))
      (should-error (org-jira-task-create) :type 'user-error)
      (should (null calls)))))

(ert-deftest org-jira-task-test-command-without-epics-table ()
  (org-jira-task-test-with-buffer "* Task\n"
    (org-jira-task-test-with-api '((key . "X-1"))
      (should-error (org-jira-task-create) :type 'user-error)
      (should (null calls)))))

(ert-deftest org-jira-task-test-command-no-key-in-response-writes-nothing ()
  (org-jira-task-test-with-buffer org-jira-task-test--doc
    (org-jira-task-test--goto "* TODO Write")
    (org-jira-task-test-with-api '((id . "1"))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_p coll &rest _) (car coll))))
        (should-error (org-jira-task-create)))
      (should-not (org-entry-get nil "KEY")))))

(ert-deftest org-jira-task-test-command-not-in-org-mode ()
  (with-temp-buffer
    (insert "* Task\n")
    (goto-char (point-min))
    (should-error (org-jira-task-create) :type 'user-error)))

;;; HTTP

(ert-deftest org-jira-task-http-test-end-to-end ()
  (org-jira-http-test-with-server
    (org-jira-task-test-with-buffer org-jira-task-test--doc
      (let ((jira-epic-link-field nil))   ; force discovery through /field
        (org-jira-task-test--goto "* TODO Write")
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_p coll &rest _) (car coll))))
          (should (equal (org-jira-task-create) "TST-99")))
        (should (equal (org-entry-get nil "KEY") "TST-99"))))))

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

(provide 'org-jira-task-test)

;;; org-jira-task-test.el ends here
