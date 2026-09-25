test_that("a valid candidate takes precedence over an incomplete reading", {
  candidates <- data.frame(
    method = c("primary", "red"),
    value = c("AB", "aB12c"),
    confidence = c(99, 5),
    valid = c(FALSE, TRUE)
  )
  choice <- rsicar:::.sicar_tesseract_select(candidates)
  expect_identical(candidates$value[choice$index], "aB12c")
  candidates <- candidates[2:1, ]
  expect_identical(rsicar:::.sicar_tesseract_select(candidates)$index, 1L)
})

test_that("switching valid readings requires a substantial confidence advantage", {
  candidates <- data.frame(
    method = c("primary", "red"),
    value = c("n3aoD", "nzaoD"),
    confidence = c(49, 57),
    valid = c(TRUE, TRUE)
  )
  expect_identical(rsicar:::.sicar_tesseract_select(candidates)$index, 1L)
  candidates$confidence <- c(36, 75)
  expect_identical(rsicar:::.sicar_tesseract_select(candidates)$index, 2L)
  expect_identical(
    rsicar:::.sicar_tesseract_select(candidates, margin = 40)$index,
    1L
  )
  candidates$value[] <- "aB12c"
  expect_identical(
    rsicar:::.sicar_tesseract_select(candidates)$reason,
    "agreement"
  )
})

test_that("invalid answers remain available for normal solver validation", {
  candidates <- data.frame(
    method = c("primary", "red"),
    value = c("AB", ""),
    confidence = c(0, 100),
    valid = c(FALSE, FALSE)
  )
  expect_identical(rsicar:::.sicar_tesseract_select(candidates)$index, 1L)
})

test_that("protected OCR fixtures do not regress in opt-in accuracy checks", {
  skip_on_cran()
  skip_if_not(
    identical(Sys.getenv("RSICAR_RUN_OCR_REGRESSION"), "true"),
    "set RSICAR_RUN_OCR_REGRESSION=true for version-dependent OCR accuracy checks"
  )
  skip_if_not_installed("magick")
  skip_if_not_installed("tesseract")

  data <- rsicar:::.sicar_captcha_manifest(test_path(
    "fixtures",
    "captchas",
    "manifest.csv"
  ))
  data <- data[data$protect, ]
  solver <- sicar_solver_tesseract()
  for (i in seq_len(nrow(data))) {
    expect_identical(
      solver$solve(data$path[i]),
      data$expected[i],
      info = data$id[i]
    )
  }
})
