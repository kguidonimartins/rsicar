test_that("selection misses are distinguished from recognition failures", {
  data <- data.frame(id = c("one", "two"), expected = c("aB12c", "AbCdE"))
  candidates <- data.frame(
    id = rep(data$id, each = 2L),
    method = rep(c("primary", "red"), 2L),
    value = c("wrong", "aB12c", "short", ""),
    confidence = c(60, 70, 10, 0),
    valid = c(TRUE, TRUE, TRUE, FALSE),
    elapsed_seconds = rep(0.1, 4L)
  )
  predictions <- rsicar:::.sicar_benchmark_predictions(data, candidates, 30)
  expect_identical(predictions$correct, c(FALSE, FALSE))
  expect_identical(predictions$selection_missed, c(TRUE, FALSE))
  summary <- rsicar:::.sicar_benchmark_summary(predictions, c(TRUE, FALSE))
  expect_identical(summary$protected_failures, 1L)
  expect_equal(summary$mean_seconds, 0.2)
  improved <- rsicar:::.sicar_benchmark_predictions(data, candidates, 10)
  expect_identical(improved$correct, c(TRUE, FALSE))
})

test_that("download success metrics include exhausted and failed downloads", {
  path <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(
      id = letters[1:4],
      attempts = c(1L, 3L, 5L, 6L),
      success = c(TRUE, TRUE, FALSE, TRUE)
    ),
    path,
    row.names = FALSE
  )
  result <- rsicar:::.sicar_benchmark_downloads(path)
  expect_identical(result$downloads, 4L)
  expect_identical(result$successes, 3L)
  expect_equal(result$success_first_attempt, 0.25)
  expect_equal(result$success_within_3, 0.5)
  expect_equal(result$success_within_5, 0.5)
  expect_equal(result$mean_attempts_all, 3.75)
})

test_that("duplicate image content cannot contaminate development and evaluation", {
  directory <- withr::local_tempdir()
  writeBin(as.raw(1), file.path(directory, "one.png"))
  file.copy(file.path(directory, "one.png"), file.path(directory, "two.png"))
  manifest <- file.path(directory, "manifest.csv")
  utils::write.csv(
    data.frame(
      id = c("one", "two"),
      path = c("one.png", "two.png"),
      expected = c("aB12c", "aB12c"),
      split = c("development", "evaluation"),
      protect = FALSE
    ),
    manifest,
    row.names = FALSE
  )
  expect_snapshot(error = TRUE, rsicar:::.sicar_captcha_manifest(manifest))
})

test_that("tuning never reads evaluation or unlabeled images", {
  directory <- withr::local_tempdir()
  for (i in 1:3) {
    writeBin(as.raw(i), file.path(directory, paste0(i, ".png")))
  }
  manifest <- file.path(directory, "manifest.csv")
  utils::write.csv(
    data.frame(
      id = c("train", "unlabeled", "heldout"),
      path = paste0(1:3, ".png"),
      expected = c("aB12c", "", "ZZZZZ"),
      split = c("development", "development", "evaluation"),
      protect = FALSE
    ),
    manifest,
    row.names = FALSE
  )
  calls <- character()
  local_mocked_bindings(
    .sicar_tesseract_requirements = function() NULL,
    .sicar_tesseract_environment = function() list(tesseract = "test"),
    .sicar_benchmark_candidates = function(data, config) {
      calls <<- c(calls, data$id)
      data.frame(
        id = "train",
        method = c("primary", "red"),
        value = c("aB12c", "aB12c"),
        confidence = c(60, 70),
        valid = TRUE,
        elapsed_seconds = 0.1
      )
    }
  )
  output <- file.path(directory, "results")
  summary <- suppressMessages(capture.output(
    result <- rsicar:::.sicar_benchmark_run(manifest, output)
  ))
  expect_identical(unique(calls), "train")
  expect_identical(unique(result$correct), 1L)
  lock <- jsonlite::read_json(
    file.path(output, "frozen-config.json"),
    simplifyVector = TRUE
  )
  expect_identical(
    lock$development_images_md5,
    unname(tools::md5sum(file.path(directory, "1.png")))
  )
  expect_identical(lock$configuration$margin, 30L)
  expect_identical(lock$configuration$psm, 7L)
  # The same image cannot be relabeled as evaluation in a later CSV.
  data <- utils::read.csv(manifest)
  data$split <- "evaluation"
  utils::write.csv(data, manifest, row.names = FALSE)
  expect_snapshot(
    error = TRUE,
    rsicar:::.sicar_benchmark_run(
      manifest,
      file.path(directory, "evaluation"),
      "evaluate",
      file.path(output, "frozen-config.json")
    )
  )
})

test_that("an empty label set cannot be scored as perfect accuracy", {
  directory <- withr::local_tempdir()
  writeBin(as.raw(1), file.path(directory, "one.png"))
  manifest <- file.path(directory, "manifest.csv")
  utils::write.csv(
    data.frame(
      id = "one",
      path = "one.png",
      expected = "",
      split = "evaluation",
      protect = FALSE
    ),
    manifest,
    row.names = FALSE
  )
  local_mocked_bindings(.sicar_tesseract_requirements = function() NULL)
  expect_snapshot(
    error = TRUE,
    rsicar:::.sicar_benchmark_run(
      manifest,
      file.path(directory, "results"),
      "evaluate"
    )
  )
})

test_that("evaluation uses exactly the frozen settings on independent images", {
  directory <- withr::local_tempdir()
  writeBin(as.raw(1), file.path(directory, "eval.png"))
  writeBin(as.raw(2), file.path(directory, "train.png"))
  manifest <- file.path(directory, "manifest.csv")
  utils::write.csv(
    data.frame(
      id = "heldout",
      path = "eval.png",
      expected = "aB12c",
      split = "evaluation",
      protect = FALSE
    ),
    manifest,
    row.names = FALSE
  )
  frozen <- file.path(directory, "frozen.json")
  jsonlite::write_json(
    list(
      configuration = rsicar:::.sicar_benchmark_config(8L, FALSE, 10L, 20),
      development_images_md5 = unname(tools::md5sum(file.path(
        directory,
        "train.png"
      )))
    ),
    frozen,
    auto_unbox = TRUE
  )
  configs <- list()
  local_mocked_bindings(
    .sicar_tesseract_requirements = function() NULL,
    .sicar_tesseract_environment = function() list(tesseract = "test"),
    .sicar_benchmark_candidates = function(data, config) {
      configs[[length(configs) + 1L]] <<- config
      data.frame(
        id = data$id,
        method = c("primary", "red"),
        value = c("aB12c", "ABCDE"),
        confidence = c(60, 20),
        valid = TRUE,
        elapsed_seconds = 0.1
      )
    }
  )
  output <- file.path(directory, "results")
  invisible(capture.output(
    result <- rsicar:::.sicar_benchmark_run(
      manifest,
      output,
      "evaluate",
      frozen
    )
  ))
  expect_length(configs, 1L)
  expect_equal(configs[[1]], list(psm = 8L, dictionaries = FALSE, border = 10L))
  expect_identical(result$correct, 1L)
  expect_equal(result$margin, 20)
  expect_identical(
    unname(tools::md5sum(file.path(output, "frozen-config.json"))),
    unname(tools::md5sum(frozen))
  )
})
