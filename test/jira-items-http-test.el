;;; jira-items-http-test.el --- HTTP-level tests against a fake Jira -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Starts test/fake_jira.py on an ephemeral port and exercises the real
;; `url-retrieve-synchronously' path: auth header, UTF-8 decoding, paging.

;;; Code:

(require 'jira-items-test-util)

(defconst jira-http-test--dir
  (file-name-directory (or load-file-name buffer-file-name)))

(defmacro jira-http-test-with-server (&rest body)
  "Run BODY with `jira-base-url' pointing at a fresh fake Jira server."
  (declare (indent 0))
  `(progn
     (skip-unless (executable-find "python3"))
     (let* ((port nil)
            (proc (make-process
                   :name "fake-jira" :noquery t :connection-type 'pipe
                   :command (list "python3"
                                  (expand-file-name "fake_jira.py" jira-http-test--dir)
                                  "test-token")
                   :filter (lambda (p out)
                             (when (string-match "PORT \\([0-9]+\\)" out)
                               (process-put p 'port (string-to-number (match-string 1 out))))))))
       (unwind-protect
           (progn
             (with-timeout (10 (error "Fake Jira did not start"))
               (while (not (setq port (process-get proc 'port)))
                 (accept-process-output proc 0.1)))
             (let ((jira-base-url (format "http://127.0.0.1:%d" port))
                   (jira-personal-access-token "test-token")
                   (jira-current-user-info nil))
               ,@body))
         (delete-process proc)))))

(ert-deftest jira-http-test-connection-decodes-utf8 ()
  (jira-http-test-with-server
    (let ((user (jira-test-connection)))
      (should (equal (alist-get 'displayName user) "Søren Åberg"))
      (should (equal jira-current-user-info user)))))

(ert-deftest jira-http-test-search-utf8-and-paging ()
  (jira-http-test-with-server
    (let* ((jira-max-results 2)
           (issues (jira-get-all-assigned-items))
           (summaries (mapcar (lambda (i) (alist-get 'summary (alist-get 'fields i))) issues)))
      (should (= (length issues) 5))
      (should (equal (car summaries) "Æble ø å"))
      (should (equal (nth 1 summaries) "Pipe | and [brackets]")))))

(ert-deftest jira-http-test-jql-reaches-server-encoded ()
  (jira-http-test-with-server
    (let ((resp (jira-search-jql "assignee = 'søren' ORDER BY updated DESC" 0 1)))
      (should (equal (alist-get 'jql resp) "assignee = 'søren' ORDER BY updated DESC")))))

(ert-deftest jira-http-test-buffer-is-cleaned-up ()
  (jira-http-test-with-server
    (let ((before (length (buffer-list))))
      (jira-api-request "/rest/api/2/myself")
      (should (= before (length (buffer-list)))))))

(ert-deftest jira-http-test-end-to-end-table ()
  (jira-http-test-with-server
    (with-temp-buffer
      (org-mode)
      (jira-insert-org-table-open-items)
      (should (string-match-p "TST-1: Æble ø å" (buffer-string)))
      (should (string-match-p "TST-2: Pipe \\\\vert and \\[brackets\\]" (buffer-string))))))

;;; HTTP errors

(ert-deftest jira-http-test-bad-token-signals-error ()
  (jira-http-test-with-server
    (let ((jira-personal-access-token "wrong"))
      (let ((err (should-error (jira-test-connection))))
        (should (string-match-p "HTTP 401" (error-message-string err)))
        (should (string-match-p "Unauthorized" (error-message-string err))))
      (should (null jira-current-user-info)))))

(ert-deftest jira-http-test-not-found-signals-error ()
  (jira-http-test-with-server
    (should-error (jira-api-request "/rest/api/2/nope"))))

(ert-deftest jira-http-test-error-does-not-leak-buffer ()
  (jira-http-test-with-server
    (let ((jira-personal-access-token "wrong")
          (before (length (buffer-list))))
      (ignore-errors (jira-api-request "/rest/api/2/myself"))
      (should (= before (length (buffer-list)))))))

(provide 'jira-items-http-test)

;;; jira-items-http-test.el ends here
