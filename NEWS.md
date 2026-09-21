# rsicar (development version)

* Added the initial domain API with state and polygon constants, validation,
  structured conditions, clients, and user-defined CAPTCHA solvers.
* Added `sicar_release_dates()` with lazy HTTPS bootstrap, persistent cookies,
  response validation, and defensive HTML date parsing.
* Added `sicar_solver_tesseract()` as an optional, experimental CAPTCHA solver;
  manual and user-defined solvers remain available without OCR dependencies.
