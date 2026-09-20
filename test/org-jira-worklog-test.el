;;; org-jira-worklog-test.el --- Tests for worklog logging -*- lexical-binding: t; coding: utf-8 -*-

;;; Code:

(require 'org-jira-test-util)
(require 'org-jira-http-test)

(ert-deftest org-jira-worklog-test-hhmm-to-seconds ()
  (should (= (org-jira-worklog-hhmm-to-seconds "01:30") 5400))
  (should (= (org-jira-worklog-hhmm-to-seconds "1:30") 5400))
  (should (= (org-jira-worklog-hhmm-to-seconds "0:45") 2700))
  (should (= (org-jira-worklog-hhmm-to-seconds "0:05") 300))
  (should (= (org-jira-worklog-hhmm-to-seconds "2:00") 7200))
  (should (= (org-jira-worklog-hhmm-to-seconds " 8:00 ") 28800))
  (should (= (org-jira-worklog-hhmm-to-seconds "26:15") 94500)))

(ert-deftest org-jira-worklog-test-hhmm-invalid ()
  (dolist (bad '("" "1" "1:2:3" "abc" "1:60" "1.5" "-1:00" "0:00" "00:00" nil))
    (should-error (org-jira-worklog-hhmm-to-seconds bad) :type 'user-error)))

(ert-deftest org-jira-worklog-test-started-format ()
  (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9:]\\{8\\}\\.000[+-][0-9]\\{4\\}\\'"
                          (org-jira-worklog-format-started)))
  (unwind-protect
      (progn
        (set-time-zone-rule "UTC")
        (should (equal (org-jira-worklog-format-started (encode-time 0 0 10 20 9 2026 t))
                       "2026-09-20T10:00:00.000+0000")))
    (set-time-zone-rule nil)))

(ert-deftest org-jira-worklog-test-payload ()
  (let ((p (org-jira-worklog-payload "1:30" "Fixed æøå" "2026-01-01T09:00:00.000+0100")))
    (should (= (alist-get 'timeSpentSeconds p) 5400))
    (should (equal (alist-get 'comment p) "Fixed æøå"))
    (should (equal (alist-get 'started p) "2026-01-01T09:00:00.000+0100")))
  (should-not (assq 'comment (org-jira-worklog-payload "1:00" "")))
  (should-not (assq 'comment (org-jira-worklog-payload "1:00"))))

(ert-deftest org-jira-worklog-test-add-posts-to-worklog-endpoint ()
  (let (args)
    (cl-letf (((symbol-function 'org-jira-api-request)
               (lambda (&rest a) (setq args a) '((id . "1")))))
      (org-jira-worklog-add "TST-1" "0:15" "hi" "2026-01-01T09:00:00.000+0100"))
    (should (equal (nth 0 args) "/rest/api/2/issue/TST-1/worklog"))
    (should (equal (nth 1 args) "POST"))
    (should (= (alist-get 'timeSpentSeconds (nth 2 args)) 900))))

(ert-deftest org-jira-worklog-test-invalid-input-makes-no-request ()
  (cl-letf (((symbol-function 'org-jira-api-request)
             (lambda (&rest _) (error "should not be called"))))
    (should-error (org-jira-worklog-add "TST-1" "bogus") :type 'user-error)
    (should-error (org-jira-worklog-add "" "1:00") :type 'user-error)
    (should-error (org-jira-worklog-add nil "1:00") :type 'user-error)))

(ert-deftest org-jira-worklog-test-key-from-org-property ()
  (with-temp-buffer
    (org-mode)
    (insert "* TO_DO Something\n  :PROPERTIES:\n  :KEY: TST-9\n  :END:\nbody\n")
    (goto-char (point-max))
    (should (equal (org-jira-worklog--issue-key-at-point) "TST-9"))))

(ert-deftest org-jira-worklog-test-key-from-text-property ()
  (with-temp-buffer
    (insert (propertize "row" 'jira-key "TST-3"))
    (goto-char 1)
    (should (equal (org-jira-worklog--issue-key-at-point) "TST-3"))))

(ert-deftest org-jira-worklog-test-interactive-command ()
  (let (args)
    (cl-letf (((symbol-function 'org-jira-worklog-add) (lambda (&rest a) (setq args a))))
      (org-jira-worklog-log-work "TST-1" "1:30" "note"))
    (should (equal args '("TST-1" "1:30" "note")))))

(ert-deftest org-jira-worklog-test-http-post-body-and-utf8 ()
  (org-jira-http-test-with-server
    (let* ((resp (org-jira-worklog-add "TST-1" "1:30" "Æble ø å" "2026-01-01T09:00:00.000+0100"))
           (got (alist-get 'received resp)))
      (should (equal (alist-get 'issueKey resp) "TST-1"))
      (should (= (alist-get 'timeSpentSeconds got) 5400))
      (should (equal (alist-get 'comment got) "Æble ø å"))
      (should (equal (alist-get 'started got) "2026-01-01T09:00:00.000+0100")))))

(ert-deftest org-jira-worklog-test-http-bad-token ()
  (org-jira-http-test-with-server
    (let ((jira-personal-access-token "wrong"))
      (should-error (org-jira-worklog-add "TST-1" "1:00")))))

(provide 'org-jira-worklog-test)

;;; org-jira-worklog-test.el ends here
