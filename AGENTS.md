# rsicar — agent instructions

Native R client for querying and downloading public data from Brazil's Rural
Environmental Registry System (SICAR).

Repository: https://github.com/kguidonimartins/rsicar

The project is currently in the planning and bootstrap stage. `PLAN.md` is the
source of truth for the intended API, architecture, delivery phases, and
acceptance criteria. Do not assume that planned files or commands already work;
check the tree first.

## Commands

Prefer the `Makefile` targets once the R package skeleton exists:

```bash
make install_deps   # install package dependencies without upgrading them
make document       # devtools::document()
make tests          # devtools::test() -> out-testthat.txt
make check          # devtools::check() -> out-check.txt
make format         # air format .
make examples       # devtools::run_examples() -> out-examples.txt
make render         # render README.Rmd
make site           # build the pkgdown site, when configured
make live-tests     # opt-in integration tests against SICAR
```

Equivalent one-liners:

```bash
Rscript --no-init-file -e "devtools::load_all()"
Rscript --no-init-file -e "devtools::test()"
Rscript --no-init-file -e "devtools::document()"
Rscript --no-init-file -e "devtools::check()"
```

During interactive development, use `devtools::load_all()` rather than
`library(rsicar)` so unexported helpers are available.

## Code style

- Match nearby code before introducing a new pattern.
- Use the base R pipe (`|>`), not the magrittr pipe (`%>%`).
- Use `\(...) ...` for a single-line anonymous function and
  `function() { ... }` otherwise.
- Keep internal helpers unexported and avoid creating standalone help topics for
  them unless the documentation is genuinely useful.
- Run `make format` after editing R code. This repository uses `air`, not
  `styler`.
- Keep optional OCR and test dependencies in `Suggests`; check for them at the
  point of use with an actionable error.
- Use two-space indentation in R and R Markdown files.
- Keep user-facing conditions in English and give them `rscicar_*` classes with
  useful context fields.

## File layout

| Code | Tests | Notes |
|------|-------|-------|
| `R/{name}.R` | `tests/testthat/test-{name}.R` | Mirror the source structure |
| `tests/testthat/fixtures/` | — | Sanitized, deterministic offline fixtures |
| `README.Rmd` | — | Edit this file; `README.md` is generated |
| `vignettes/` | — | Getting started and CAPTCHA solver guides |
| `ref/SICAR/` | — | Read-only upstream Python reference |

Do not place test output, downloaded ZIP files, or scratch data in `R/` or the
repository root.

## Testing

Tests use testthat edition 3 and live in `tests/testthat/`. Organize them as
file, then `test_that()`, then expectations.

```r
test_that("descriptive behavior", {
  result <- my_function(input)
  expect_equal(result, expected)
})
```

- Use `withr::local_tempfile()` and `withr::local_tempdir()` for cleanup.
- Prefer precise expectations over `expect_true()` and `expect_false()`.
- Snapshot complete errors and warnings with `expect_snapshot()`.
- Use `webfakes` and fixtures for normal HTTP tests. The default test suite must
  not require network access.
- Gate live tests behind `RSCICAR_RUN_LIVE_TESTS=true`. Keep them low-volume and
  never run them during ordinary checks or CRAN checks.
- Never add real sleeps to retry tests; inject waiting and randomness instead.
- Validate both successful ZIPs and failure cases such as HTML masquerading as
  a download, empty files, and truncated archives.

## Documentation

- Every exported function needs roxygen2 documentation, `@export`, and an
  example where sensible.
- Examples run by `R CMD check` must not access the SICAR service or require
  interactive CAPTCHA input.
- Wrap roxygen comments at 80 characters.
- Use `@family` tags consistently once families are established.
- After roxygen changes, run `make document`.
- When pkgdown is configured, add every new public topic to `_pkgdown.yml` and
  run `pkgdown::check_pkgdown()`.

## NEWS.md

- Add a bullet for every user-facing change; skip tiny documentation changes and
  internal refactors.
- Mention the affected function early in the bullet.
- Reference issues or pull requests as `(#123).` before the final period.
- Order bullets alphabetically by function name within a release section, with
  general bullets first.

## CI

CI is not configured yet. The planned matrix covers R release/devel on Linux,
macOS, and Windows. Ordinary CI must be offline and deterministic; live contract
tests belong in a low-frequency scheduled or manually triggered job.

## Domain notes

- The initial HTTPS request currently responds with `302`, sets required
  cookies, and points to HTTP. Bootstrap the cookie jar without following that
  redirect, then make subsequent requests directly over HTTPS.
- Treat that `302` as valid only during bootstrap. Validate status and content
  type separately for HTML, PNG, and ZIP responses.
- Never disable TLS certificate or hostname verification.
- CAPTCHA solvers implement `function(path) -> string`; normalize output and
  require exactly five alphanumeric characters.
- Keep `tesseract` and `magick` optional. Manual and user-supplied solvers must
  work without local OCR libraries.
- Stream downloads to a temporary file in the destination directory, validate
  the ZIP, and only then rename it to the final path.
- Keep country-wide downloads sequential by default, organize results under one
  directory per state, preserve successful downloads, and summarize failures.
- The accepted domains are the 27 Brazilian state abbreviations and the nine
  polygon themes documented in `PLAN.md` and the upstream reference.
- The upstream reference is pinned at commit
  `facffbf91a4998a2daa814a65d1d36ea99266f83`. Preserve its MIT attribution when
  porting derived behavior or code.

## What agents should not do

- Do not edit generated `README.md` directly; edit `README.Rmd` and run
  `make render`.
- Do not modify `ref/SICAR/` as part of the R port unless explicitly asked to
  update the reference snapshot.
- Do not commit secrets, `.env`, `.Renviron`, downloaded SICAR archives, or
  unredacted service responses.
- Do not add network-dependent tests to the default suite.
- Do not work around service failures by disabling TLS verification or bypassing
  CAPTCHA/access controls.
- Do not add optional system-heavy packages to `Imports` merely for one feature.
- Do not run `devtools::release()`, submit to CRAN, force-push, or amend published
  commits without an explicit maintainer request.
