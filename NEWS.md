# rsicar 0.0.0.9000

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
* Fixed CAPTCHA solvers uppercasing their answer before submitting it to
  SICAR. The service is case-sensitive, so every correctly solved CAPTCHA was
  being rejected; solver output is now only trimmed, not upper-cased.
* Fixed CAPTCHA temporary-file cleanup and retry handling for non-ZIP responses
  returned after a rejected CAPTCHA.
* Fixed `sicar_client()`'s `timeout` bounding the whole download instead of
  just connection setup and stalled transfers, which could cut off large ZIP
  downloads before they finished; it is now applied as libcurl's
  `connecttimeout` and `low_speed_time`.
* Fixed `sicar_download_country()` not validating `client` and `dest_dir`
  before starting, unlike `sicar_download_state()`.
* Fixed `sicar_download_state()` treating an unexpected `302` response (an
  expired session) as a permanent failure; it is now retried and forces a
  fresh session bootstrap before the next attempt.
* Improved `sicar_solver_tesseract()` accuracy by switching Tesseract's page
  segmentation mode from 7 (single text line) to 8 (single word); it remains
  experimental and can still confuse visually similar characters.
* Renamed structured condition classes to the `rsicar_*` prefix.
