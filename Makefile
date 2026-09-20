EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch -L lisp -L test

.PHONY: test compile clean
test:
	$(BATCH) -l ert -l test/org-jira-test.el -l test/org-jira-http-test.el -l test/org-jira-worklog-test.el \
	  -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) -f batch-byte-compile lisp/*.el

clean:
	rm -f lisp/*.elc test/*.elc
