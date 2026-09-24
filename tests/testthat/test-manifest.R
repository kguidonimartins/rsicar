.fake_zip_attempt <- function() {
  function(client, state, polygon, dest_dir) {
    fixture <- file.path(dest_dir, paste0(state, "_", polygon, "-tmp.zip"))
    source <- tempfile(fileext = ".txt")
    writeLines("fixture", source)
    utils::zip(fixture, source, flags = "-q")
    fixture
  }
}

test_that("sicar_read_manifest returns an empty frame when there is no manifest", {
  destination <- withr::local_tempdir()

  manifest <- sicar_read_manifest(destination)

  expect_s3_class(manifest, "data.frame")
  expect_identical(nrow(manifest), 0L)
  expect_true(all(
    c(
      "state",
      "polygon",
      "file",
      "size_bytes",
      "md5",
      "downloaded_at",
      "solver",
      "attempts",
      "tries",
      "overwrite",
      "rsicar_version",
      "status"
    ) %in%
      names(manifest)
  ))
})

test_that("sicar_read_manifest and sicar_download_status validate dest_dir", {
  expect_error(
    sicar_read_manifest(NA_character_),
    class = "rsicar_invalid_argument"
  )
  expect_error(
    sicar_download_status(NA_character_),
    class = "rsicar_invalid_argument"
  )
})

test_that("a successful download records a complete manifest entry", {
  client <- sicar_client(solver = sicar_solver_function(function(path) "ABCDE"))
  destination <- withr::local_tempdir()

  result <- sicar_download_state(
    client,
    "PA",
    "apps",
    destination,
    tries = 3,
    attempt_download = .fake_zip_attempt()
  )

  manifest <- sicar_read_manifest(destination)
  expect_identical(nrow(manifest), 1L)
  expect_identical(manifest$state, "PA")
  expect_identical(manifest$polygon, "APPS")
  expect_identical(manifest$file, "PA_APPS.zip")
  expect_identical(manifest$size_bytes, as.numeric(file.info(result)$size))
  expect_identical(manifest$md5, unname(tools::md5sum(result)))
  expect_identical(manifest$solver, "function")
  expect_identical(manifest$attempts, 1)
  expect_identical(manifest$tries, 3)
  expect_false(manifest$overwrite)
  expect_identical(
    manifest$rsicar_version,
    as.character(utils::packageVersion("rsicar"))
  )
  expect_identical(manifest$status, "success")
  expect_match(
    manifest$downloaded_at,
    "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$"
  )
})

test_that("multiple polygons each get their own manifest entry", {
  client <- sicar_client()
  destination <- withr::local_tempdir()

  sicar_download_state(
    client,
    "PA",
    c("apps", "reserva_legal"),
    destination,
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )

  manifest <- sicar_read_manifest(destination)
  expect_setequal(manifest$polygon, c("APPS", "RESERVA_LEGAL"))
})

test_that("sicar_download_status reports downloaded and missing polygons", {
  client <- sicar_client()
  destination <- withr::local_tempdir()

  sicar_download_state(
    client,
    "PA",
    "apps",
    destination,
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )

  status <- sicar_download_status(destination, c("APPS", "RESERVA_LEGAL"))
  expect_identical(status$status[status$polygon == "APPS"], "downloaded")
  expect_identical(status$status[status$polygon == "RESERVA_LEGAL"], "missing")
})

test_that("sicar_download_status reports corrupted when a recorded file is gone", {
  client <- sicar_client()
  destination <- withr::local_tempdir()

  result <- sicar_download_state(
    client,
    "PA",
    "apps",
    destination,
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )
  unlink(result)

  status <- sicar_download_status(destination, "APPS")
  expect_identical(status$status, "corrupted")
})

test_that("a partial failure across polygons still leaves a diagnosable manifest", {
  client <- sicar_client()
  destination <- withr::local_tempdir()
  fake_attempt <- function(client, state, polygon, dest_dir) {
    if (polygon == "RESERVA_LEGAL") {
      rlang::abort(
        "CAPTCHA solver failed",
        class = "rsicar_download_error",
        retryable = FALSE
      )
    }
    fixture <- file.path(dest_dir, paste0(state, "_", polygon, "-tmp.zip"))
    source <- tempfile(fileext = ".txt")
    writeLines("fixture", source)
    utils::zip(fixture, source, flags = "-q")
    fixture
  }

  expect_error(
    sicar_download_state(
      client,
      "PA",
      c("apps", "reserva_legal"),
      destination,
      tries = 1,
      attempt_download = fake_attempt
    ),
    class = "rsicar_download_error"
  )

  status <- sicar_download_status(destination, c("APPS", "RESERVA_LEGAL"))
  expect_identical(status$status[status$polygon == "APPS"], "downloaded")
  expect_identical(status$status[status$polygon == "RESERVA_LEGAL"], "missing")
})

test_that("reusing an existing archive backfills a manifest entry without attempts", {
  client <- sicar_client()
  destination <- withr::local_tempdir()

  sicar_download_state(
    client,
    "PA",
    "apps",
    destination,
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )
  unlink(file.path(destination, "manifest.json"))
  expect_false(file.exists(file.path(destination, "manifest.json")))

  sicar_download_state(
    client,
    "PA",
    "apps",
    destination,
    overwrite = FALSE,
    tries = 1,
    attempt_download = function(...) stop("should not be called")
  )

  manifest <- sicar_read_manifest(destination)
  expect_identical(nrow(manifest), 1L)
  expect_true(is.na(manifest$attempts))
})

test_that("sicar_download_country_status aggregates one manifest per state", {
  destination <- withr::local_tempdir()
  client <- sicar_client()

  sicar_download_state(
    client,
    "PA",
    "apps",
    file.path(destination, "PA"),
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )

  status <- sicar_download_country_status(
    destination,
    polygon = "APPS",
    state = c("PA", "AC")
  )

  expect_identical(nrow(status), 2L)
  expect_identical(status$status[status$state == "PA"], "downloaded")
  expect_identical(status$status[status$state == "AC"], "missing")
})

test_that("a corrupted manifest is reported with its path", {
  destination <- withr::local_tempdir()
  writeLines("{not json", file.path(destination, "manifest.json"))

  error <- rlang::catch_cnd(sicar_read_manifest(destination))

  expect_s3_class(error, "rsicar_manifest_error")
  expect_identical(error$path, file.path(destination, "manifest.json"))
})

test_that("a manifest without a downloads field reads as empty", {
  destination <- withr::local_tempdir()
  writeLines('{"schema_version": 1}', file.path(destination, "manifest.json"))

  expect_identical(nrow(sicar_read_manifest(destination)), 0L)
})

test_that("overwriting a download replaces its manifest entry", {
  client <- sicar_client(solver = sicar_solver_function(function(path) "ABCDE"))
  destination <- withr::local_tempdir()
  sicar_download_state(
    client,
    "PA",
    "APPS",
    destination,
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )

  sicar_download_state(
    client,
    "PA",
    "APPS",
    destination,
    overwrite = TRUE,
    tries = 1,
    attempt_download = .fake_zip_attempt()
  )

  manifest <- sicar_read_manifest(destination)
  expect_identical(nrow(manifest), 1L)
  expect_true(manifest$overwrite)
})

test_that("reusing a recorded archive keeps its manifest entry", {
  client <- sicar_client(solver = sicar_solver_function(function(path) "ABCDE"))
  destination <- withr::local_tempdir()
  sicar_download_state(
    client,
    "PA",
    "APPS",
    destination,
    tries = 2,
    attempt_download = .fake_zip_attempt()
  )
  before <- sicar_read_manifest(destination)

  sicar_download_state(
    client,
    "PA",
    "APPS",
    destination,
    tries = 5,
    attempt_download = function(...) stop("should not be called")
  )

  expect_identical(sicar_read_manifest(destination), before)
})

test_that("sicar_download_country_status validates dest_dir", {
  expect_error(
    sicar_download_country_status(NA_character_),
    class = "rsicar_invalid_argument"
  )
})
