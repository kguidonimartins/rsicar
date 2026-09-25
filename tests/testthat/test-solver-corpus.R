test_that("corpus preparation deduplicates and preserves labels and split assignments", {
  directory <- withr::local_tempdir()
  writeBin(as.raw(1), file.path(directory, "ABCDE.png"))
  file.copy(file.path(directory, "ABCDE.png"), file.path(directory, "copy.png"))
  initial <- rsicar:::.sicar_prepare_captcha_corpus(directory)
  expect_equal(nrow(initial), 1L)
  expect_identical(initial$expected, "")
  initial$expected <- "aB12c"
  initial$split <- "evaluation"
  utils::write.csv(
    initial,
    file.path(directory, "manifest.csv"),
    row.names = FALSE
  )
  writeBin(as.raw(2), file.path(directory, "new.png"))
  updated <- rsicar:::.sicar_prepare_captcha_corpus(directory)
  expect_equal(nrow(updated), 2L)
  expect_identical(updated$expected, c("aB12c", ""))
  expect_identical(updated$split[1], "evaluation")
  repeated <- rsicar:::.sicar_prepare_captcha_corpus(directory)
  expect_identical(repeated, updated)
})
