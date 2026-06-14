# vulpea-capf — development tasks
emacs := env_var_or_default("EMACS", "emacs")
src   := "vulpea-capf.el"
elpa := ".packages"
covfile := env_var_or_default("COVERAGE_FILE", "lcov.info")

# Elisp prelude: point package.el at the sandbox, add MELPA, initialize.
# Uses (quote ...) instead of ' so the whole form survives shell single-quoting.
setup := '(progn (setq package-user-dir (expand-file-name "' + elpa + '")) (require (quote package)) (add-to-list (quote package-archives) (quote ("melpa" . "https://melpa.org/packages/")) t) (package-initialize))'

# List available recipes.
default:
    @just --list

# Install dependencies (vulpea, package-lint) into the local sandbox.
deps:
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      --eval '(unless package-archive-contents (package-refresh-contents))' \
      --eval '(dolist (p (list (quote vulpea) (quote package-lint))) (unless (package-installed-p p) (package-install p)))'

# Byte-compile the package (prints warnings, does not fail on them).
compile: deps
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      -f batch-byte-compile {{src}}

# Documentation style check.
checkdoc:
    {{emacs}} -Q --batch \
      --eval '(checkdoc-file "{{src}}")'

# Full lint: checkdoc, package-lint, then byte-compile with warnings as errors.
lint: clean deps
    {{emacs}} -Q --batch --eval '(checkdoc-file "{{src}}")'
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      -l package-lint -f package-lint-batch-and-exit {{src}}
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      --eval '(setq byte-compile-error-on-warn t)' \
      -f batch-byte-compile {{src}}

# Run the ERT test suite (DB is stubbed; no sandbox notes needed).
# load-prefer-newer avoids loading a stale .elc over freshly edited source.
test: clean deps
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      --eval '(setq load-prefer-newer t)' \
      -L . -l ert -l test/vulpea-capf-test.el \
      -f ert-run-tests-batch-and-exit

# Line-coverage report via undercover. FORMAT: text (default) | lcov | simplecov
# | codecov | coveralls. text prints %% to the console; the file formats write to
# `covfile' (default lcov.info, override with COVERAGE_FILE=... or just covfile=PATH).
# undercover is self-installed.
coverage format="text": clean deps
    UNDERCOVER_FORCE=true {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      --eval '(unless (package-installed-p (quote undercover)) (package-refresh-contents) (package-install (quote undercover)))' \
      --eval '(require (quote undercover))' \
      --eval '(undercover "{{src}}" (:report-format (quote {{format}})) (:send-report nil){{ if format == "text" { "" } else { ' (:report-file "' + covfile + '")' } }})' \
      -L . -l ert -l test/vulpea-capf-test.el \
      -f ert-run-tests-batch-and-exit

# Everything CI should run.
ci: lint test

# Regenerate CHANGELOG.md from the conventional commit history.
changelog:
    git-cliff --bump --output CHANGELOG.md

# Remove build artifacts (keeps the dependency sandbox).
clean:
    rm -f *.elc
    rm -f {{covfile}}

# Remove build artifacts and the dependency sandbox.
clean-all: clean
    rm -rf {{elpa}}
