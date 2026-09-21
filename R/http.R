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
    httr2::req_options(
      # `timeout` bounds only how long the connection may take to establish
      # and how long a stalled transfer may sit below `low_speed_limit`
      # bytes/sec. Large ZIP downloads can otherwise take several minutes,
      # so a request-wide timeout would abort them mid-transfer.
      connecttimeout = client$timeout,
      low_speed_time = client$timeout,
      low_speed_limit = 1,
      followlocation = FALSE
    ) |>
    httr2::req_cookie_preserve(client$state$cookie_jar)
}

.sicar_perform <- function(client, url) {
  tryCatch(
    httr2::req_perform(.sicar_request(client, url)),
    error = function(error) {
      .sicar_abort(
        sprintf("Request to `%s` failed: %s", url, conditionMessage(error)),
        "rsicar_http_error",
        parent = error,
        url = url,
        retryable = TRUE,
        # A raw transport failure (DNS, connection reset, TLS handshake,
        # genuine timeout) is the one case that plausibly means the server
        # or network is struggling, so back off exponentially. See
        # `.sicar_retry_delay()`.
        slow_retry = TRUE
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
    # 408/429/5xx are the service telling us it is overloaded or
    # rate-limiting; back off exponentially. A 302 outside of bootstrap just
    # means the session expired, which a fresh bootstrap fixes immediately,
    # so it is retried right away instead of being slowed down. See
    # `.sicar_attempt_download()` and `.sicar_retry_delay()`.
    server_signal <- actual_status %in% c(408, 429, 500, 502, 503, 504)
    .sicar_abort(
      sprintf(
        "Unexpected HTTP status %s for `%s`; expected %s.",
        actual_status,
        url,
        status
      ),
      "rsicar_http_error",
      url = url,
      status = actual_status,
      expected_status = status,
      retryable = server_signal || actual_status == 302L,
      slow_retry = server_signal
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
        "rsicar_http_error",
        url = url,
        content_type = actual_type,
        expected_content_type = content_type,
        retryable = TRUE,
        # Almost always means SICAR rejected the CAPTCHA (an expected,
        # frequent outcome of automatic solving, not a server problem), so
        # retry immediately with a fresh CAPTCHA rather than backing off.
        slow_retry = FALSE
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
