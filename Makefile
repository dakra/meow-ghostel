EMACS      ?= emacs
# Extra flags injected before every Emacs invocation (e.g. `-L /tmp/compat'
# in CI so older Emacs versions can find the compat library).
EMACSFLAGS ?=
export EMACSFLAGS

XDG_CACHE_HOME ?= $(HOME)/.cache
MELPAZOID_DIR  ?= $(XDG_CACHE_HOME)/melpazoid
MEOW_DIR       ?= $(XDG_CACHE_HOME)/meow
# Prefer a local ghostel checkout (which has its native module built, so the
# native ERT tests run too) when present; else fall back to a cache clone
# (elisp-only: the native tests self-skip).
GHOSTEL_DIR    ?= $(firstword $(wildcard $(HOME)/.emacs.d/lib/ghostel) $(XDG_CACHE_HOME)/ghostel)
LINT_ELPA_DIR  ?= $(XDG_CACHE_HOME)/meow-ghostel-lint-elpa
LINT_DEPS_STAMP := $(LINT_ELPA_DIR)/.deps-installed

LOAD_PATH = -L "$(MEOW_DIR)" -L "$(GHOSTEL_DIR)/lisp" -L .

.PHONY: all byte-compile test lint package-lint checkdoc docquotes melpazoid clean

all: byte-compile test lint

$(MEOW_DIR):
	git clone --depth 1 https://github.com/meow-edit/meow.git "$@"

$(GHOSTEL_DIR):
	git clone --depth 1 https://github.com/dakra/ghostel.git "$@"

meow-ghostel.elc: meow-ghostel.el | $(MEOW_DIR) $(GHOSTEL_DIR)
	$(EMACS) --batch $(EMACSFLAGS) -Q $(LOAD_PATH) \
		--eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile $<

byte-compile: meow-ghostel.elc

test: meow-ghostel.elc
	$(EMACS) --batch $(EMACSFLAGS) -Q $(LOAD_PATH) \
		-l ert -l test/meow-ghostel-test.el -f meow-ghostel-test-run

lint: byte-compile package-lint checkdoc docquotes

# `package-lint' needs three things present that aren't on any default load
# path: the linter itself, a resolvable `meow' (NonGNU ELPA), and a
# resolvable `ghostel' (installed from the checkout's main file).  Provision
# all of them into an isolated `package-user-dir' so `make package-lint'
# runs standalone.
$(LINT_DEPS_STAMP): | $(GHOSTEL_DIR)
	$(EMACS) --batch $(EMACSFLAGS) -Q \
		--eval "(setq package-user-dir \"$(LINT_ELPA_DIR)\")" \
		--eval "(package-initialize)" \
		--eval "(package-refresh-contents)" \
		--eval "(package-install 'package-lint)" \
		--eval "(package-install 'meow)" \
		--eval "(package-install-file (expand-file-name \"$(GHOSTEL_DIR)/lisp/ghostel.el\"))"
	@touch $@

package-lint: $(LINT_DEPS_STAMP) meow-ghostel.el
	$(EMACS) --batch $(EMACSFLAGS) -Q \
		--eval "(setq package-user-dir \"$(LINT_ELPA_DIR)\")" \
		--eval "(package-initialize)" \
		--eval "(require 'package-lint)" \
		-f package-lint-batch-and-exit \
		meow-ghostel.el

checkdoc: meow-ghostel.el
	$(EMACS) --batch $(EMACSFLAGS) -Q \
		--eval "(require 'checkdoc)" \
		--eval "(let ((sentence-end-double-space nil) \
		              (checkdoc-proper-noun-list nil) \
		              (checkdoc-verb-check-experimental-flag nil) \
		              (ok t)) \
		  (dolist (f '(\"meow-ghostel.el\")) \
		    (ignore-errors (kill-buffer \"*Warnings*\")) \
		    (let ((inhibit-message t)) \
		      (checkdoc-file f)) \
		    (when (get-buffer \"*Warnings*\") \
		      (setq ok nil) \
		      (with-current-buffer \"*Warnings*\" \
		        (message \"%s\" (buffer-string))))) \
		  (unless ok (kill-emacs 1)))"

# Mirrors melpazoid's "Only use back/front quotes to link to top-level
# elisp symbols" check, widened to also catch identifiers with
# underscores — env-var and macro-style names that melpazoid's stricter
# [A-Z]+ regex skips.
docquotes: meow-ghostel.el
	$(EMACS) --batch $(EMACSFLAGS) -Q \
		--eval "(let ((ok t)) \
		  (dolist (f '(\"meow-ghostel.el\")) \
		    (with-temp-buffer \
		      (insert-file-contents f) \
		      (setq case-fold-search nil) \
		      (goto-char (point-min)) \
		      (while (re-search-forward \"\`[A-Z_]+'\" nil t) \
		        (setq ok nil) \
		        (message \"%s:%d:%d: Only use back/front quotes to link to top-level elisp symbols (%s)\" \
		                 f (line-number-at-pos) \
		                 (1+ (- (match-beginning 0) (line-beginning-position))) \
		                 (match-string 0))))) \
		  (unless ok (kill-emacs 1)))"

melpazoid:
	@if [ ! -d "$(MELPAZOID_DIR)" ]; then \
		git clone https://github.com/riscy/melpazoid.git "$(MELPAZOID_DIR)"; \
	fi
	RECIPE='(meow-ghostel :fetcher github :repo "dakra/meow-ghostel")' \
		LOCAL_REPO=$(CURDIR) \
		make -C "$(MELPAZOID_DIR)"

clean:
	rm -f meow-ghostel.elc
