;;; org-jira-api-test.el --- Tests for the HTTP transport -*- lexical-binding: t; coding: utf-8 -*-

;;; Commentary:
;; Unit tests for the retry/keep-alive handling in `org-jira-api--retrieve'.
;; End-to-end HTTP behaviour is covered by test/org-jira-http-test.el
;; against the fake Jira server.

;;; Code:

(require 'org-jira-test-util)

(defmacro org-jira-api-test-with-retrieve (results &rest body)
  "Run BODY with `url-retrieve-synchronously' stubbed to return RESULTS.
RESULTS is a list consumed one value per call; the variable `calls' (a
list of (URL SILENT INHIBIT-COOKIES TIMEOUT) argument lists, most
recent first) and `keepalive-during-call' (the value of
`url-http-attempt-keepalives' as seen inside the stub) are bound for
BODY."
  (declare (indent 1))
  `(let ((remaining (copy-sequence ,results))
         calls
         keepalive-during-call)
     (cl-letf (((symbol-function 'url-retrieve-synchronously)
                (lambda (&rest args)
                  (push args calls)
                  (setq keepalive-during-call url-http-attempt-keepalives)
                  (pop remaining))))
       ,@body)))

(ert-deftest org-jira-api-test-retrieve-succeeds-first-try ()
  (let ((buf (generate-new-buffer " *ok*")))
    (unwind-protect
        (org-jira-api-test-with-retrieve (list buf)
          (should (eq (org-jira-api--retrieve "https://x/y") buf))
          (should (= (length calls) 1)))
      (kill-buffer buf))))

(ert-deftest org-jira-api-test-retrieve-retries-on-empty-response ()
  (let ((buf (generate-new-buffer " *ok*")))
    (unwind-protect
        (org-jira-api-test-with-retrieve (list nil buf)
          (should (eq (org-jira-api--retrieve "https://x/y") buf))
          (should (= (length calls) 2)))
      (kill-buffer buf))))

(ert-deftest org-jira-api-test-retrieve-honours-retry-count ()
  (let ((jira-request-retries 3)
        (buf (generate-new-buffer " *ok*")))
    (unwind-protect
        (org-jira-api-test-with-retrieve (list nil nil nil buf)
          (should (eq (org-jira-api--retrieve "https://x/y") buf))
          (should (= (length calls) 4)))
      (kill-buffer buf))))

(ert-deftest org-jira-api-test-retrieve-signals-after-exhausting-retries ()
  (let ((jira-request-retries 2))
    (org-jira-api-test-with-retrieve (list nil nil nil)
      (should-error (org-jira-api--retrieve "https://x/y"))
      (should (= (length calls) 3)))))

(ert-deftest org-jira-api-test-retrieve-zero-retries-tries-once ()
  (let ((jira-request-retries 0))
    (org-jira-api-test-with-retrieve (list nil)
      (should-error (org-jira-api--retrieve "https://x/y"))
      (should (= (length calls) 1)))))

(ert-deftest org-jira-api-test-retrieve-disables-keepalive ()
  (let ((url-http-attempt-keepalives t)
        (buf (generate-new-buffer " *ok*")))
    (unwind-protect
        (org-jira-api-test-with-retrieve (list buf)
          (org-jira-api--retrieve "https://x/y")
          (should (null keepalive-during-call))
          ;; the caller's own binding is restored afterwards
          (should (eq url-http-attempt-keepalives t)))
      (kill-buffer buf))))

(ert-deftest org-jira-api-test-retrieve-passes-configured-timeout ()
  (let ((jira-request-timeout 42)
        (buf (generate-new-buffer " *ok*")))
    (unwind-protect
        (org-jira-api-test-with-retrieve (list buf)
          (org-jira-api--retrieve "https://x/y")
          (should (equal (nth 3 (car calls)) 42)))
      (kill-buffer buf))))

(provide 'org-jira-api-test)

;;; org-jira-api-test.el ends here
