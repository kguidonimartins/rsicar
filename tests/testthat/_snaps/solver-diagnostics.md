# diagnostics save both candidates before answer validation

    Code
      rsicar:::.sicar_solve(solver, path)
    Condition
      Error in `.sicar_abort()`:
      ! A CAPTCHA solver must return exactly five alphanumeric characters.

# diagnostics are off by default and write failures do not stop OCR

    Code
      solver$solve("unused.png")
    Condition
      Warning:
      CAPTCHA diagnostics could not be saved; solving will continue.
      Caused by error in `doTryCatch()`:
      ! Diagnostic destination is not a directory.
    Output
      [1] "aB12c"

# invalid diagnostic destinations fail clearly

    Code
      sicar_solver_tesseract(diagnostics_dir = "")
    Condition
      Error in `.sicar_abort()`:
      ! `diagnostics_dir` must be NULL or one non-empty directory path.
