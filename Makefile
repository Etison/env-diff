# Project settings
PROJECT := env-diff
PACKAGE := envdiff
REPOSITORY := jacebrowning/env-diff

# Project paths
PACKAGES := $(PACKAGE) tests
CONFIG := $(wildcard *.py)
MODULES := $(wildcard $(PACKAGE)/*.py)

# Python settings
ifndef TRAVIS
	PYTHON_MAJOR ?= 3
	PYTHON_MINOR ?= 6
endif

# System paths
PLATFORM := $(shell python -c 'import sys; print(sys.platform)')
ifneq ($(findstring win32, $(PLATFORM)), )
	WINDOWS := true
	SYS_PYTHON_DIR := C:\\Python$(PYTHON_MAJOR)$(PYTHON_MINOR)
	SYS_PYTHON := $(SYS_PYTHON_DIR)\\python.exe
	# https://bugs.launchpad.net/virtualenv/+bug/449537
	export TCL_LIBRARY=$(SYS_PYTHON_DIR)\\tcl\\tcl8.5
else
	ifneq ($(findstring darwin, $(PLATFORM)), )
		MAC := true
	else
		LINUX := true
	endif
	SYS_PYTHON := python$(PYTHON_MAJOR)
	ifdef PYTHON_MINOR
		SYS_PYTHON := $(SYS_PYTHON).$(PYTHON_MINOR)
	endif
endif

# Virtual environment paths
ENV := .venv
ifneq ($(findstring win32, $(PLATFORM)), )
	BIN := $(ENV)/Scripts
	ACTIVATE := $(BIN)/activate.bat
	OPEN := cmd /c start
	PYTHON := $(BIN)/python.exe
	PIP := $(BIN)/pip.exe
else
	BIN := $(ENV)/bin
	ACTIVATE := . $(BIN)/activate
	ifneq ($(findstring cygwin, $(PLATFORM)), )
		OPEN := cygstart
	else
		OPEN := open
	endif
	PYTHON := $(BIN)/python
	PIP := $(BIN)/pip
endif

# MAIN TASKS ###################################################################

SNIFFER := pipenv run sniffer

.PHONY: all
all: install

.PHONY: ci
ci: check test ## Run all tasks that determine CI status

.PHONY: watch
watch: install .clean-test ## Continuously run all CI tasks when files chanage
	$(SNIFFER)

.PHONY: run ## Start the program
run: install
	$(PYTHON) $(PACKAGE)/__main__.py

# SYSTEM DEPENDENCIES ##########################################################

.PHONY: doctor
doctor:  ## Confirm system dependencies are available
	bin/verchew

# PROJECT DEPENDENCIES #########################################################

export PIPENV_SHELL_COMPAT=true
export PIPENV_VENV_IN_PROJECT=true

DEPENDENCIES := $(ENV)/.installed
METADATA := *.egg-info

.PHONY: install
install: $(METADATA) $(DEPENDENCIES)

$(METADATA): $(PIP) setup.py
	$(PYTHON) setup.py develop
	@ touch $@

$(DEPENDENCIES): $(PIP) Pipfile*
	pipenv install --dev --ignore-hashes
ifdef WINDOWS
	@ echo "Manually install pywin32: https://sourceforge.net/projects/pywin32/files/pywin32"
else ifdef MAC
	$(PIP) install pync MacFSEvents
else ifdef LINUX
	$(PIP) install pyinotify
endif
	@ touch $@

$(PIP):
	pipenv --python=$(SYS_PYTHON)

# CHECKS #######################################################################

PYLINT := pipenv run pylint
PYCODESTYLE := pipenv run pycodestyle
PYDOCSTYLE := pipenv run pydocstyle

.PHONY: check
check: pylint pycodestyle pydocstyle ## Run linters and static analysis

.PHONY: pylint
pylint: install
	$(PYLINT) $(PACKAGES) $(CONFIG) --rcfile=.pylint.ini

.PHONY: pycodestyle
pycodestyle: install
	$(PYCODESTYLE) $(PACKAGES) $(CONFIG) --config=.pycodestyle.ini

.PHONY: pydocstyle
pydocstyle: install
	$(PYDOCSTYLE) $(PACKAGES) $(CONFIG)

# TESTS ########################################################################

PYTEST := pipenv run py.test
COVERAGE := pipenv run coverage
COVERAGE_SPACE := pipenv run coverage.space

RANDOM_SEED ?= $(shell date +%s)
FAILURES := .cache/v/cache/lastfailed
REPORTS ?= xmlreport

PYTEST_CORE_OPTIONS := -ra -vv
PYTEST_COV_OPTIONS := --cov=$(PACKAGE) --no-cov-on-fail --cov-report=term-missing:skip-covered --cov-report=html
PYTEST_RANDOM_OPTIONS := --random --random-seed=$(RANDOM_SEED)

PYTEST_OPTIONS := $(PYTEST_CORE_OPTIONS) $(PYTEST_RANDOM_OPTIONS)
ifndef DISABLE_COVERAGE
PYTEST_OPTIONS += $(PYTEST_COV_OPTIONS)
endif
PYTEST_RURUN_OPTIONS := $(PYTEST_CORE_OPTIONS) --last-failed --exitfirst

.PHONY: test
test: test-all ## Run unit and integration tests

.PHONY: test-unit
test-unit: install
	@- mv $(FAILURES) $(FAILURES).bak
	$(PYTEST) $(PYTEST_OPTIONS) $(PACKAGE) --junitxml=$(REPORTS)/unit.xml
	@- mv $(FAILURES).bak $(FAILURES)
	$(COVERAGE_SPACE) $(REPOSITORY) unit

.PHONY: test-int
test-int: install
	@ if test -e $(FAILURES); then $(PYTEST) $(PYTEST_RURUN_OPTIONS) tests; fi
	@ rm -rf $(FAILURES)
	$(PYTEST) $(PYTEST_OPTIONS) tests --junitxml=$(REPORTS)/integration.xml
	$(COVERAGE_SPACE) $(REPOSITORY) integration

.PHONY: test-all
test-all: install
	@ if test -e $(FAILURES); then $(PYTEST) $(PYTEST_RURUN_OPTIONS) $(PACKAGES); fi
	@ rm -rf $(FAILURES)
	$(PYTEST) $(PYTEST_OPTIONS) $(PACKAGES) --junitxml=$(REPORTS)/overall.xml
	$(COVERAGE_SPACE) $(REPOSITORY) overall

.PHONY: read-coverage
read-coverage:
	$(OPEN) htmlcov/index.html

# DOCUMENTATION ################################################################

PYREVERSE := pipenv run pyreverse
MKDOCS := pipenv run mkdocs

MKDOCS_INDEX := site/index.html

.PHONY: doc
doc: uml mkdocs ## Generate documentation

.PHONY: uml
uml: install docs/*.png
docs/*.png: $(MODULES)
	$(PYREVERSE) $(PACKAGE) -p $(PACKAGE) -a 1 -f ALL -o png --ignore tests
	- mv -f classes_$(PACKAGE).png docs/classes.png
	- mv -f packages_$(PACKAGE).png docs/packages.png

.PHONY: mkdocs
mkdocs: install $(MKDOCS_INDEX)
$(MKDOCS_INDEX): mkdocs.yml docs/*.md
	ln -sf `realpath README.md --relative-to=docs` docs/index.md
	ln -sf `realpath CHANGELOG.md --relative-to=docs/about` docs/about/changelog.md
	ln -sf `realpath CONTRIBUTING.md --relative-to=docs/about` docs/about/contributing.md
	ln -sf `realpath LICENSE.md --relative-to=docs/about` docs/about/license.md
	$(MKDOCS) build --clean --strict

.PHONY: mkdocs-live
mkdocs-live: mkdocs
	eval "sleep 3; open http://127.0.0.1:8000" &
	$(MKDOCS) serve

# BUILD ########################################################################

PYINSTALLER := pipenv run pyinstaller
PYINSTALLER_MAKESPEC := pipenv run pyi-makespec

DIST_FILES := dist/*.tar.gz dist/*.whl
EXE_FILES := dist/$(PROJECT).*

.PHONY: dist
dist: install $(DIST_FILES)
$(DIST_FILES): $(MODULES) README.rst CHANGELOG.rst
	rm -f $(DIST_FILES)
	$(PYTHON) setup.py check --restructuredtext --strict --metadata
	$(PYTHON) setup.py sdist
	$(PYTHON) setup.py bdist_wheel

%.rst: %.md
	pandoc -f markdown_github -t rst -o $@ $<

.PHONY: exe
exe: install $(EXE_FILES)
$(EXE_FILES): $(MODULES) $(PROJECT).spec
	# For framework/shared support: https://github.com/yyuu/pyenv/wiki
	$(PYINSTALLER) $(PROJECT).spec --noconfirm --clean

$(PROJECT).spec:
	$(PYINSTALLER_MAKESPEC) $(PACKAGE)/__main__.py --onefile --windowed --name=$(PROJECT)

# RELEASE ######################################################################

TWINE := pipenv run twine

.PHONY: upload
upload: .git-no-changes dist ## Upload the current version to PyPI
	$(TWINE) upload dist/*.*
	$(OPEN) https://pypi.python.org/pypi/$(PROJECT)

.PHONY: .git-no-changes
.git-no-changes:
	@ if git diff --name-only --exit-code;        \
	then                                          \
		echo Git working copy is clean...;        \
	else                                          \
		echo ERROR: Git working copy is dirty!;   \
		echo Commit your changes and try again.;  \
		exit -1;                                  \
	fi;

# CLEANUP ######################################################################

.PHONY: clean
clean: .clean-dist .clean-test .clean-doc .clean-build ## Delete all generated and temporary files

.PHONY: clean-all
clean-all: clean .clean-env .clean-workspace

.PHONY: .clean-build
.clean-build:
	find $(PACKAGES) -name '*.pyc' -delete
	find $(PACKAGES) -name '__pycache__' -delete
	rm -rf *.egg-info

.PHONY: .clean-doc
.clean-doc:
	rm -rf README.rst docs/apidocs *.html docs/*.png site

.PHONY: .clean-test
.clean-test:
	rm -rf .cache .pytest .coverage htmlcov xmlreport

.PHONY: .clean-dist
.clean-dist:
	rm -rf *.spec dist build

.PHONY: .clean-env
.clean-env: clean
	rm -rf $(ENV)

.PHONY: .clean-workspace
.clean-workspace:
	rm -rf *.sublime-workspace

# HELP #########################################################################

.PHONY: help
help: all
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
