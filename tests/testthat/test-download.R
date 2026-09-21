test_that("download URLs encode the state, polygon, and CAPTCHA", {
  client <- sicar_client()

  expect_identical(
    rsicar:::.sicar_download_url(client, "PA", "APPS", "A B12"),
    paste0(
      client$urls$download_base,
      "?idEstado=PA&tipoBase=APPS&ReCaptcha=A%20B12"
    )
  )
})

test_that("valid ZIPs are accepted and bad files are rejected", {
  zip_path <- tempfile(fileext = ".zip")
  fixture <- tempfile(fileext = ".txt")
  writeLines("fixture", fixture)
  utils::zip(zip_path, files = fixture, flags = "-q")

  expect_invisible(rsicar:::.sicar_validate_zip(zip_path))

  bad_path <- tempfile(fileext = ".zip")
  writeLines("not a zip", bad_path)
  expect_error(
    rsicar:::.sicar_validate_zip(bad_path),
    class = "rsicar_download_error"
  )
})

test_that("sicar_download_country validates client and dest_dir", {
  expect_error(
    sicar_download_country("not-a-client", "apps", tempfile()),
    class = "rsicar_invalid_argument"
  )
  expect_error(
    sicar_download_country(sicar_client(), "apps", dest_dir = NA_character_),
    class = "rsicar_invalid_argument"
  )
})

test_that("country downloads preserve one result row per state", {
  client <- sicar_client()
  calls <- character()
  fake_download <- function(
    client,
    state,
    polygon,
    dest_dir,
    overwrite,
    tries,
    wait,
    random
  ) {
    calls <<- c(calls, state)
    if (state == "PA") {
      stop("simulated failure")
    }
    file.path(dest_dir, paste0(state, "_", polygon, ".zip"))
  }
  expect_warning(
    sicar_download_country(
      client,
      "apps",
      tempfile(),
      tries = 1,
      download_state = fake_download
    ),
    class = "rsicar_download_warning"
  )
  calls <- character()
  result <- suppressWarnings(
    sicar_download_country(
      client,
      "apps",
      tempfile(),
      tries = 1,
      download_state = fake_download
    )
  )

  expect_length(calls, 27)
  expect_length(result$state, 27)
  expect_identical(result$status[result$state == "PA"], "failed")
})

test_that("server-signal failures back off exponentially without real sleep", {
  client <- sicar_client()
  client$state$bootstrapped <- TRUE
  destination <- withr::local_tempdir()
  attempts <- 0L
  delays <- numeric()
  fake_attempt <- function(client, state, polygon, dest_dir) {
    attempts <<- attempts + 1L
    if (attempts == 1L) {
      rlang::abort(
        "temporary service failure",
        class = "rsicar_download_error",
        retryable = TRUE,
        slow_retry = TRUE
      )
    }
    fixture <- file.path(dest_dir, "temporary.zip")
    source <- tempfile(fileext = ".txt")
    writeLines("fixture", source)
    utils::zip(fixture, source, flags = "-q")
    fixture
  }

  result <- sicar_download_state(
    client,
    "PA",
    "APPS",
    destination,
    tries = 2,
    wait = function(seconds) delays <<- c(delays, seconds),
    random = function() 0.25,
    attempt_download = fake_attempt
  )

  expect_true(file.exists(result))
  expect_identical(attempts, 2L)
  expect_identical(delays, 1.25)
})

test_that("routine retries (e.g. a wrong CAPTCHA guess) use a short flat delay", {
  client <- sicar_client()
  client$state$bootstrapped <- TRUE
  destination <- withr::local_tempdir()
  attempts <- 0L
  delays <- numeric()
  fake_attempt <- function(client, state, polygon, dest_dir) {
    attempts <<- attempts + 1L
    if (attempts == 1L) {
      # No `slow_retry` flag: this is what a rejected CAPTCHA or an expired
      # session looks like, not a server-overload signal.
      rlang::abort(
        "CAPTCHA rejected",
        class = "rsicar_download_error",
        retryable = TRUE
      )
    }
    fixture <- file.path(dest_dir, "temporary.zip")
    source <- tempfile(fileext = ".txt")
    writeLines("fixture", source)
    utils::zip(fixture, source, flags = "-q")
    fixture
  }

  result <- sicar_download_state(
    client,
    "PA",
    "APPS",
    destination,
    tries = 2,
    wait = function(seconds) delays <<- c(delays, seconds),
    random = function() 0.25,
    attempt_download = fake_attempt
  )

  expect_true(file.exists(result))
  expect_identical(attempts, 2L)
  # max(0, min(2, 0.25 * 2)) = 0.5, versus 1.25 on the exponential path.
  expect_identical(delays, 0.5)
})

test_that("multiple polygons are validated upfront before any download starts", {
  client <- sicar_client()
  attempts <- character()
  fake_attempt <- function(client, state, polygon, dest_dir) {
    attempts <<- c(attempts, polygon)
    stop("should not be called")
  }

  expect_error(
    sicar_download_state(
      client,
      "PA",
      c("APPS", "unknown"),
      withr::local_tempdir(),
      attempt_download = fake_attempt
    ),
    class = "rsicar_invalid_argument"
  )
  expect_length(attempts, 0L)
})

test_that("state downloads accept a polygon vector and return a named path vector", {
  client <- sicar_client()
  destination <- withr::local_tempdir()
  calls <- character()
  fake_attempt <- function(client, state, polygon, dest_dir) {
    calls <<- c(calls, polygon)
    fixture <- file.path(dest_dir, paste0(state, "_", polygon, "-tmp.zip"))
    source <- tempfile(fileext = ".txt")
    writeLines("fixture", source)
    utils::zip(fixture, source, flags = "-q")
    fixture
  }

  result <- sicar_download_state(
    client,
    "PA",
    c("apps", "reserva_legal"),
    destination,
    tries = 1,
    attempt_download = fake_attempt
  )

  expect_identical(calls, c("APPS", "RESERVA_LEGAL"))
  expect_identical(names(result), c("APPS", "RESERVA_LEGAL"))
  expect_identical(basename(result[["APPS"]]), "PA_APPS.zip")
  expect_identical(basename(result[["RESERVA_LEGAL"]]), "PA_RESERVA_LEGAL.zip")
  expect_true(all(file.exists(result)))
})

test_that("non-retryable download failures stop immediately", {
  client <- sicar_client()
  client$state$bootstrapped <- TRUE
  attempts <- 0L
  fake_attempt <- function(client, state, polygon, dest_dir) {
    attempts <<- attempts + 1L
    rlang::abort(
      "invalid archive",
      class = "rsicar_download_error",
      retryable = FALSE
    )
  }

  expect_error(
    sicar_download_state(
      client,
      "PA",
      "APPS",
      withr::local_tempdir(),
      tries = 5,
      wait = function(seconds) stop("wait should not be called"),
      attempt_download = fake_attempt
    ),
    class = "rsicar_download_error"
  )
  expect_identical(attempts, 1L)
})

test_that("an unexpected 302 forces a fresh bootstrap and is retried", {
  zip_path <- tempfile(fileext = ".zip")
  fixture <- tempfile(fileext = ".txt")
  writeLines("fixture", fixture)
  utils::zip(zip_path, files = fixture, flags = "-q")
  zip_body <- readBin(zip_path, what = "raw", n = file.info(zip_path)$size)

  client <- sicar_client(solver = sicar_solver_function(function(path) "ABCDE"))
  client$urls$index <- "https://example.test/index"
  client$urls$recaptcha <- "https://example.test/captcha"
  client$urls$download_base <- "https://example.test/download"

  index_calls <- 0L
  captcha_calls <- 0L
  mock <- function(req) {
    if (grepl("/index$", req$url)) {
      index_calls <<- index_calls + 1L
      return(httr2::response(
        status_code = 302,
        url = req$url,
        headers = list(`set-cookie` = "session=valid; Path=/")
      ))
    }
    if (grepl("/captcha", req$url)) {
      captcha_calls <<- captcha_calls + 1L
      if (captcha_calls == 1L) {
        # Simulate a session that expired between bootstrap and the
        # first real request: SICAR redirects instead of serving a PNG.
        return(httr2::response(
          status_code = 302,
          url = req$url,
          headers = list(location = "http://example.test/index")
        ))
      }
      return(httr2::response(
        status_code = 200,
        url = req$url,
        headers = list(`content-type` = "image/png"),
        body = charToRaw("not really an image")
      ))
    }
    httr2::response(
      status_code = 200,
      url = req$url,
      headers = list(`content-type` = "application/zip"),
      body = zip_body
    )
  }
  httr2::local_mocked_responses(mock)

  destination <- withr::local_tempdir()
  result <- sicar_download_state(
    client,
    state = "pa",
    polygon = "apps",
    dest_dir = destination,
    tries = 2,
    wait = function(seconds) NULL
  )

  expect_true(file.exists(result))
  expect_identical(captcha_calls, 2L)
  expect_identical(index_calls, 2L)
  expect_identical(client$state$bootstrapped, TRUE)
})

test_that("state downloads validate and atomically rename a ZIP", {
  zip_path <- tempfile(fileext = ".zip")
  fixture <- tempfile(fileext = ".txt")
  writeLines("fixture", fixture)
  utils::zip(zip_path, files = fixture, flags = "-q")
  zip_body <- readBin(zip_path, what = "raw", n = file.info(zip_path)$size)

  client <- sicar_client(
    solver = sicar_solver_function(function(path) {
      expect_identical(file.exists(path), TRUE)
      "ABCDE"
    })
  )
  client$urls$index <- "https://example.test/index"
  client$urls$recaptcha <- "https://example.test/captcha"
  client$urls$download_base <- "https://example.test/download"
  mock <- function(req) {
    if (grepl("/index$", req$url)) {
      return(httr2::response(
        status_code = 302,
        url = req$url,
        headers = list(`set-cookie` = "session=valid; Path=/")
      ))
    }
    if (grepl("/captcha", req$url)) {
      return(httr2::response(
        status_code = 200,
        url = req$url,
        headers = list(`content-type` = "image/png"),
        body = charToRaw("not really an image")
      ))
    }
    httr2::response(
      status_code = 200,
      url = req$url,
      headers = list(`content-type` = "application/zip"),
      body = zip_body
    )
  }
  httr2::local_mocked_responses(mock)

  destination <- withr::local_tempdir()
  result <- sicar_download_state(
    client,
    state = "pa",
    polygon = "apps",
    dest_dir = destination,
    tries = 1
  )

  expect_identical(basename(result), "PA_APPS.zip")
  expect_true(file.exists(result))
  expect_identical(client$state$bootstrapped, TRUE)
})
