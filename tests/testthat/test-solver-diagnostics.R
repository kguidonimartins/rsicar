test_that("diagnostics save both candidates before answer validation", {
  directory <- withr::local_tempdir()
  path <- test_path("fixtures", "captchas", "current", "b2aSQ.png")
  local_mocked_bindings(
    .sicar_tesseract_requirements = function() NULL,
    .sicar_tesseract_engine = function() NULL,
    .sicar_tesseract_environment = function() {
      list(tesseract = "test", traineddata_md5 = "test")
    },
    .sicar_tesseract_candidates = function(...) {
      data.frame(
        method = c("primary", "red"),
        value = c("AB", ""),
        confidence = c(12, 0),
        elapsed_seconds = c(0.1, 0.2),
        valid = c(FALSE, FALSE)
      )
    }
  )
  solver <- sicar_solver_tesseract(diagnostics_dir = directory)
  expect_snapshot(error = TRUE, rsicar:::.sicar_solve(solver, path))
  records <- list.files(directory, pattern = "[.]json$", full.names = TRUE)
  expect_length(records, 1L)
  record <- jsonlite::read_json(records[1], simplifyVector = TRUE)
  expect_identical(record$candidates$value, c("AB", ""))
  expect_identical(record$candidates$selected, c(TRUE, FALSE))
  expect_identical(record$answer, "AB")
  expect_identical(record$environment$traineddata_md5, "test")
  expect_identical(
    unname(tools::md5sum(file.path(directory, record$image))),
    unname(tools::md5sum(path))
  )
  solver$solve(path)
  expect_length(list.files(directory, pattern = "[.]json$"), 2L)
})

test_that("diagnostics are off by default and write failures do not stop OCR", {
  directory <- withr::local_tempfile()
  writeLines("not a directory", directory)
  local_mocked_bindings(
    .sicar_tesseract_requirements = function() NULL,
    .sicar_tesseract_engine = function() NULL,
    .sicar_tesseract_environment = function() list(tesseract = "test"),
    .sicar_tesseract_candidates = function(...) {
      data.frame(
        method = c("primary", "red"),
        value = c("aB12c", "aB12c"),
        confidence = c(12, 0),
        elapsed_seconds = c(0.1, 0.2),
        valid = c(TRUE, TRUE)
      )
    }
  )
  solver <- sicar_solver_tesseract()
  expect_identical(solver$solve("unused.png"), "aB12c")
  solver <- sicar_solver_tesseract(diagnostics_dir = directory)
  expect_snapshot(solver$solve("unused.png"))
  expect_identical(readLines(directory), "not a directory")
})

test_that("invalid diagnostic destinations fail clearly", {
  expect_snapshot(error = TRUE, sicar_solver_tesseract(diagnostics_dir = ""))
})
