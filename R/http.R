.sicar_headers <- function(client) {
  c(.sicar_default_headers, client$headers)
}

.sicar_request <- function(client, url) {
  request <- httr2::request(url)
  request <- do.call(
    httr2::req_headers,
    c(list(.req = request), as.list(.sicar_headers(client)))
  )
  request |>
    httr2::req_options(timeout = client$timeout, followlocation = FALSE) |>
    httr2::req_cookie_preserve(client$state$cookie_jar)
}

.sicar_perform <- function(client, url) {
  tryCatch(
    httr2::req_perform(.sicar_request(client, url)),
    error = function(error) {
      .sicar_abort(
        sprintf("Request to `%s` failed: %s", url, conditionMessage(error)),
        "rscicar_http_error",
        parent = error,
        url = url,
        retryable = TRUE
      )
    }
  )
}

.sicar_require_response <- function(
  response,
  url,
  status,
  content_type = NULL
) {
  actual_status <- httr2::resp_status(response)
  if (actual_status != status) {
    .sicar_abort(
      sprintf(
        "Unexpected HTTP status %s for `%s`; expected %s.",
        actual_status,
        url,
        status
      ),
      "rscicar_http_error",
      url = url,
      status = actual_status,
      expected_status = status,
      retryable = actual_status %in% c(408, 429, 500, 502, 503, 504)
    )
  }

  if (!is.null(content_type)) {
    actual_type <- httr2::resp_content_type(response)
    if (!identical(tolower(actual_type), tolower(content_type))) {
      .sicar_abort(
        sprintf(
          "Unexpected content type `%s` for `%s`; expected `%s`.",
          actual_type,
          url,
          content_type
        ),
        "rscicar_http_error",
        url = url,
        content_type = actual_type,
        expected_content_type = content_type,
        retryable = TRUE
      )
    }
  }

  response
}

.sicar_bootstrap <- function(client) {
  if (isTRUE(client$state$bootstrapped)) {
    return(invisible(client))
  }

  response <- .sicar_perform(client, client$urls$index)
  .sicar_require_response(response, client$urls$index, 302)
  client$state$bootstrapped <- TRUE
  invisible(client)
}
