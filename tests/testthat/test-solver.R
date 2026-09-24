test_that("custom solvers are normalized", {
  solver <- sicar_solver_function(function(path) " ab1c2 ")

  expect_s3_class(solver, "sicar_solver")
  expect_identical(rsicar:::.sicar_solve(solver, "captcha.png"), "ab1c2")
})

test_that("custom solvers preserve case, because SICAR CAPTCHAs are case-sensitive", {
  solver <- sicar_solver_function(function(path) "aB1cD")

  expect_identical(rsicar:::.sicar_solve(solver, "captcha.png"), "aB1cD")
})

test_that("custom solvers reject invalid output", {
  solver <- sicar_solver_function(function(path) "too-long")

  expect_error(
    rsicar:::.sicar_solve(solver, "captcha.png"),
    class = "rsicar_solver_error"
  )
})

test_that("manual solvers fail clearly in non-interactive sessions", {
  solver <- sicar_solver_manual()

  expect_error(
    rsicar:::.sicar_solve(solver, "captcha.png"),
    class = "rsicar_solver_error"
  )
})

test_that(".sicar_open_file dispatches to the right opener per platform", {
  calls <- list()
  fake_system2 <- function(command, args, ...) {
    calls[[length(calls) + 1L]] <<- list(command = command, args = args)
    0L
  }

  expect_true(rsicar:::.sicar_open_file(
    "captcha.png",
    sysname = "Darwin",
    system2 = fake_system2
  ))
  expect_identical(calls[[1]]$command, "open")

  expect_true(rsicar:::.sicar_open_file(
    "captcha.png",
    sysname = "Linux",
    system2 = fake_system2
  ))
  expect_identical(calls[[2]]$command, "xdg-open")

  windows_calls <- character()
  expect_true(rsicar:::.sicar_open_file(
    "captcha.png",
    sysname = "Windows",
    windows_open = function(path) windows_calls <<- c(windows_calls, path)
  ))
  expect_identical(windows_calls, "captcha.png")
})

test_that(".sicar_open_file swallows opener failures instead of erroring", {
  expect_false(rsicar:::.sicar_open_file(
    "captcha.png",
    sysname = "Darwin",
    system2 = function(...) stop("command not found")
  ))
  expect_false(rsicar:::.sicar_open_file(
    "captcha.png",
    sysname = "Linux",
    system2 = function(...) 127L
  ))
  expect_false(rsicar:::.sicar_open_file(
    "captcha.png",
    sysname = "Windows",
    windows_open = function(path) stop("no GUI available")
  ))
})

test_that("tesseract solver checks optional dependencies", {
  skip_if_not(
    requireNamespace("magick", quietly = TRUE) &&
      requireNamespace("tesseract", quietly = TRUE),
    "optional OCR packages are not installed"
  )

  solver <- sicar_solver_tesseract()

  expect_s3_class(solver, "sicar_solver")
  expect_identical(solver$name, "tesseract")
})

test_that("custom solvers must return one non-missing character value", {
  for (value in list(NA_character_, c("ABCDE", "FGHIJ"), 12345, NULL)) {
    solver <- sicar_solver_function(function(path) value)
    expect_error(
      rsicar:::.sicar_solve(solver, "captcha.png"),
      "must return one non-missing character value",
      class = "rsicar_solver_error"
    )
  }
})

test_that("function solvers require a function", {
  expect_error(
    sicar_solver_function("ABCDE"),
    class = "rsicar_invalid_argument"
  )
})

test_that("tesseract solver preprocesses and reads a CAPTCHA image", {
  skip_on_cran()
  skip_if_not_installed("magick")
  skip_if_not_installed("tesseract")

  path <- withr::local_tempfile(fileext = ".png")
  magick::image_blank(160, 50, color = "white") |>
    magick::image_annotate("AB12C", size = 32, gravity = "center") |>
    magick::image_write(path, format = "png")

  preprocessed <- rsicar:::.sicar_tesseract_preprocess(path)
  expect_s3_class(preprocessed, "magick-image")

  recognized <- sicar_solver_tesseract()$solve(path)
  expect_type(recognized, "character")
  expect_match(recognized, "^[A-Za-z0-9]*$")
})
