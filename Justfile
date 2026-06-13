# vulpea-capf — development tasks
emacs := env_var_or_default("EMACS", "emacs")
src   := "vulpea-capf.el"
elpa := ".packages"

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
lint: deps
    {{emacs}} -Q --batch --eval '(checkdoc-file "{{src}}")'
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      -l package-lint -f package-lint-batch-and-exit {{src}}
    {{emacs}} -Q --batch \
      --eval '{{setup}}' \
      --eval '(setq byte-compile-error-on-warn t)' \
      -f batch-byte-compile {{src}}

# Everything CI should run.
ci: lint

# Regenerate CHANGELOG.md from the conventional commit history with version bumped.
changelog-bump:
    git-cliff --bump --output CHANGELOG.md

# Regenerate CHANGELOG.md from the conventional commit history.
changelog:
    git-cliff --output CHANGELOG.md

# Remove build artifacts (keeps the dependency sandbox).
clean:
    rm -f *.elc

# Remove build artifacts and the dependency sandbox.
clean-all: clean
    rm -rf {{elpa}}
