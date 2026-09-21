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
* Fixed `sicar_download_state()` and `sicar_download_country()` backing off
  exponentially even for routine retries (a wrong CAPTCHA guess, an expired
  session), which needlessly slowed down automatic solving. Only failures
  that signal real server trouble (a 408/429/5xx or a dropped connection)
  now back off; everything else retries within a couple of seconds, matching
  the upstream Python client's behavior. Their `tries` default is now 25
  (was 3), also matching upstream: a CAPTCHA solver under 100% accuracy is
  expected to miss sometimes, so a generous, fast-retrying budget is what
  makes `sicar_solver_tesseract()` succeed automatically without help,
  rather than one-shot OCR accuracy alone.
* Improved `sicar_solver_tesseract()` accuracy by switching Tesseract's page
  segmentation mode from 7 (single text line) to 8 (single word); it remains
  experimental. On real, live SICAR CAPTCHAs (harder than the upstream
  reference's cached fixtures) its single-attempt accuracy is still low, so
  `sicar_download_state()`'s larger retry budget matters more than ever;
  prefer `sicar_solver_manual()` or a custom `sicar_solver_function()`
  (for example wrapping a paid CAPTCHA-solving API) where reliability
  matters.
* Renamed structured condition classes to the `rsicar_*` prefix.
* `sicar_download_state()`'s `polygon` argument now accepts a character
  vector to download several polygon types for a state in one call. All
  requested polygon types are validated upfront, before any download starts;
  the result is a character vector of paths named by polygon type when more
  than one is requested.
* Added console progress feedback to `sicar_download_state()` (and
  therefore `sicar_download_country()`): an attempt counter with an ETA
  while a CAPTCHA is being solved, and a byte-level progress bar with ETA
  for the ZIP transfer once a CAPTCHA succeeds. Both are silent in
  non-interactive sessions.
* Added a `manifest.json` written to `dest_dir` after every successful
  `sicar_download_state()` download, recording the state, polygon type,
  file size and MD5 checksum, download timestamp, CAPTCHA solver used, and
  attempts taken. Added `sicar_read_manifest()` to read it back as a data
  frame, and `sicar_download_status()` / `sicar_download_country_status()`
  to diagnose which polygon types are downloaded, missing, or corrupted
  (recorded but no longer present on disk at the recorded size) - for
  example, to see what is left to retry after a CAPTCHA solver exhausted
  its `tries` on some polygon type.
* `sicar_solver_manual()` now opens each CAPTCHA image automatically with
  the operating system's default viewer (macOS, Linux, and Windows) before
  prompting for the answer, instead of only printing its path. Opening is
  best-effort: if it fails (for example, a headless session with no GUI),
  the path is still printed so the image can be opened by hand.
