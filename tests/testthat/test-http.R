test_that("bootstrap accepts only the SICAR redirect", {
  client <- sicar_client()
  client$urls$index <- "https://example.test/index"

  responses <- list(
    httr2::response(
      status_code = 302,
      url = client$urls$index,
      headers = list(
        location = "http://example.test/index",
        `set-cookie` = "session=valid; Path=/"
      )
    ),
    httr2::response(
      status_code = 200,
      url = "https://example.test/downloads",
      headers = list(`content-type` = "text/html"),
      body = charToRaw(release_fixture())
    )
  )
  httr2::local_mocked_responses(responses)

  expect_invisible(rsicar:::.sicar_bootstrap(client))
  expect_identical(client$state$bootstrapped, TRUE)
})

test_that("release dates use bootstrap and validate HTML", {
  client <- sicar_client()
  client$urls$index <- "https://example.test/index"
  client$urls$release_date <- "https://example.test/downloads"
  responses <- list(
    httr2::response(
      status_code = 302,
      url = client$urls$index,
      headers = list(`set-cookie` = "session=valid; Path=/")
    ),
    httr2::response(
      status_code = 200,
      url = client$urls$release_date,
      headers = list(`content-type` = "text/html"),
      body = charToRaw(release_fixture())
    )
  )
  httr2::local_mocked_responses(responses)

  result <- sicar_release_dates(client)

  expect_length(result$state, 27)
  expect_identical(client$state$bootstrapped, TRUE)
})

test_that("response validation reports status and content type failures", {
  bad_status <- httr2::response(status_code = 500)
  bad_type <- httr2::response(
    status_code = 200,
    headers = list(`content-type` = "text/plain")
  )

  expect_error(
    rsicar:::.sicar_require_response(bad_status, "https://example.test", 200),
    class = "rsicar_http_error"
  )
  expect_error(
    rsicar:::.sicar_require_response(
      bad_type,
      "https://example.test",
      200,
      "text/html"
    ),
    class = "rsicar_http_error"
  )
})

test_that("an unexpected 302 is retryable", {
  unexpected_redirect <- httr2::response(
    status_code = 302,
    headers = list(location = "http://example.test/index")
  )

  error <- rlang::catch_cnd(
    rsicar:::.sicar_require_response(
      unexpected_redirect,
      "https://example.test",
      200,
      "application/zip"
    )
  )

  expect_s3_class(error, "rsicar_http_error")
  expect_true(rsicar:::.sicar_retryable(error))
})
