# rsicar (development version)

* Added the initial domain API with state and polygon constants, validation,
  structured conditions, clients, and user-defined CAPTCHA solvers.
* Added `sicar_release_dates()` with lazy HTTPS bootstrap, persistent cookies,
  response validation, and defensive HTML date parsing.
* Added `sicar_solver_tesseract()` as an optional, experimental CAPTCHA solver;
  manual and user-defined solvers remain available without OCR dependencies.
* Added `sicar_download_state()` and `sicar_download_country()` with ZIP
  validation, safe temporary files, resumable existing outputs, and per-state
  failure reporting.
* Added bounded exponential backoff with jitter for retryable download failures;
  permanent validation and solver errors now stop immediately.
* Added Portuguese README/vignettes, pkgdown configuration, cross-platform CI,
  and opt-in live contract tests.
