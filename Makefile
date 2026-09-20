EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch -L lisp -L test

.PHONY: test compile clean
test:
	$(BATCH) -l ert -l test/jira-items-test.el -l test/jira-items-http-test.el \
	  -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) -f batch-byte-compile lisp/*.el

clean:
	rm -f lisp/*.elc test/*.elc
