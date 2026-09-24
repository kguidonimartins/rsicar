.DEFAULT_GOAL := help

R := Rscript --no-init-file
PKGNAME := $(shell sed -n "s/^Package: *\([^ ]*\)/\1/p" DESCRIPTION 2>/dev/null)
PKGVERS := $(shell sed -n "s/^Version: *\([^ ]*\)/\1/p" DESCRIPTION 2>/dev/null)

.PHONY: help require-package install_deps document format tests test examples build \
	check check-fast check-cran coverage coverage-report install quick-install clean render site \
	live-tests all

require-package:
	@test -f DESCRIPTION || { echo "DESCRIPTION not found; create the package skeleton first."; exit 1; }
	@test -n "$(PKGNAME)" && test -n "$(PKGVERS)" || { echo "DESCRIPTION must define Package and Version."; exit 1; }

install_deps: require-package ## install package dependencies
	$(R) -e 'if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes", repos = "https://cloud.r-project.org")' \
		-e 'remotes::install_deps(dependencies = TRUE, upgrade = "never")'

document: require-package ## refresh package documentation
	$(R) -e "devtools::document()"

format: ## format R, R Markdown, and Quarto files with air
	air format R/*.R tests/*.R tests/testthat/*.R data-raw/*.R tools/*.R README.Rmd vignettes/*.Rmd

tests: require-package ## run the offline test suite
	$(R) -e "Sys.setenv(TESTTHAT_MAX_FAILS = Inf); devtools::test()" 2>&1 | tee out-testthat.txt

test: tests ## alias for the offline test suite

examples: require-package document ## run package examples, excluding dontrun examples
	$(R) -e "devtools::run_examples(run_donttest = TRUE)" 2>&1 | tee out-examples.txt

build: require-package document ## build the source package
	$(R) -e "devtools::build()"

check: require-package ## run R CMD check through devtools
	$(R) -e "devtools::check(cran = TRUE)" 2>&1 | tee out-check.txt

check-fast: require-package ## run a fast development check without the large catalog
	$(R) tools/check-fast.R 2>&1 | tee out-check-fast.txt

check-cran: require-package ## run a CRAN-like check without a PDF manual
	$(R) -e "Sys.setenv('_R_CHECK_SYSTEM_CLOCK_' = 0); devtools::check(cran = TRUE, args = '--no-manual')" 2>&1 | tee out-check-cran.txt

coverage: require-package ## measure offline test coverage with covr
	NOT_CRAN=true $(R) -e 'cov <- covr::package_coverage(); print(cov)' 2>&1 | tee out-coverage.txt

coverage-report: require-package ## open an interactive covr HTML report
	NOT_CRAN=true $(R) -e 'covr::report(covr::package_coverage(), browse = TRUE)'

install: install_deps build ## install the built source package
	cd .. && R CMD INSTALL $(PKGNAME)_$(PKGVERS).tar.gz

quick-install: build ## build and install without installing dependencies
	cd .. && R CMD INSTALL $(PKGNAME)_$(PKGVERS).tar.gz

clean: require-package ## remove this package's build and check artifacts
	cd .. && $(RM) -r "$(PKGNAME)_$(PKGVERS).tar.gz" "$(PKGNAME).Rcheck"

README.md: README.Rmd
	$(R) -e "rmarkdown::render('$<')"

render: require-package ## render README.Rmd
	@test -f README.Rmd || { echo "README.Rmd not found."; exit 1; }
	$(R) -e "rmarkdown::render('README.Rmd')"

site: require-package ## build the pkgdown site
	@test -f _pkgdown.yml || { echo "_pkgdown.yml not found; pkgdown is not configured."; exit 1; }
	$(R) -e "pkgdown::build_site()"

live-tests: require-package ## run opt-in, low-volume SICAR contract tests
	$(R) -e "Sys.setenv(RSICAR_RUN_LIVE_TESTS = 'true'); devtools::test(filter = 'live')" 2>&1 | tee out-live-tests.txt

all: install tests check ## install dependencies, build, install, test, and check

help: ## show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
