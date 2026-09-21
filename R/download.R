.sicar_download_url <- function(client, state, polygon, captcha) {
  query <- c(
    idEstado = state,
    tipoBase = polygon,
    ReCaptcha = captcha
  )
  paste0(
    client$urls$download_base,
    "?",
    paste(
      paste0(names(query), "=", utils::URLencode(query, reserved = TRUE)),
      collapse = "&"
    )
  )
}

.sicar_download_captcha <- function(client) {
  query <- paste0("id=", sample.int(1000000, 1L))
  url <- paste0(client$urls$recaptcha, "?", query)
  response <- .sicar_perform(client, url)
  response <- .sicar_require_response(response, url, 200, "image/png")
  path <- tempfile("rsicar-captcha-", fileext = ".png")
  writeBin(httr2::resp_body_raw(response), path)
  path
}

.sicar_validate_zip <- function(path) {
  if (!file.exists(path) || file.info(path)$size <= 0) {
    .sicar_abort(
      "The downloaded file is empty or missing.",
      "rsicar_download_error",
      path = path
    )
  }
  signature <- readBin(path, what = "raw", n = 2L)
  if (
    length(signature) != 2L ||
      !identical(as.character(signature), c("50", "4b"))
  ) {
    .sicar_abort(
      "The download is not a ZIP archive.",
      "rsicar_download_error",
      path = path
    )
  }
  tryCatch(
    utils::unzip(path, list = TRUE),
    error = function(error) {
      .sicar_abort(
        "The downloaded ZIP archive is invalid or truncated.",
        "rsicar_download_error",
        parent = error,
        path = path
      )
    }
  )
  invisible(path)
}

.sicar_download_zip <- function(client, url, path) {
  response <- tryCatch(
    httr2::req_perform(
      .sicar_request(client, url),
      path = path
    ),
    error = function(error) {
      .sicar_abort(
        sprintf("Download from `%s` failed: %s", url, conditionMessage(error)),
        "rsicar_download_error",
        parent = error,
        url = url,
        path = path,
        retryable = TRUE,
        slow_retry = TRUE
      )
    }
  )
  .sicar_require_response(response, url, 200, "application/zip")
  # `req_perform(path =)` streams the body straight to disk on a real
  # transfer, but mocked responses (`httr2::local_mocked_responses()`) keep
  # the body in memory only and never write `path`. This fallback covers
  # that case and any other request that returns a body without streaming.
  if (!file.exists(path) || file.info(path)$size == 0) {
    writeBin(httr2::resp_body_raw(response), path)
  }
  .sicar_validate_zip(path)
  invisible(path)
}

.sicar_forget_session_on_302 <- function(client, error) {
  # A 302 mid-flow means the session cookies were not honored (typically an
  # expired session). Clearing the bootstrapped flag makes the next retry's
  # `.sicar_bootstrap()` call actually re-run instead of being a no-op, so
  # the client recovers on its own instead of exhausting `tries` immediately.
  if (identical(error$status, 302L) || identical(error$status, 302)) {
    client$state$bootstrapped <- FALSE
  }
  stop(error)
}

.sicar_attempt_download <- function(client, state, polygon, dest_dir) {
  .sicar_bootstrap(client)
  captcha_path <- tryCatch(
    .sicar_download_captcha(client),
    error = function(error) .sicar_forget_session_on_302(client, error)
  )
  on.exit(unlink(captcha_path), add = TRUE)
  captcha <- .sicar_solve(client$solver, captcha_path)
  url <- .sicar_download_url(client, state, polygon, captcha)
  temporary <- tempfile(
    pattern = paste0(state, "_", polygon, "-"),
    tmpdir = dest_dir,
    fileext = ".zip"
  )
  success <- FALSE
  on.exit(if (!success) unlink(temporary), add = TRUE)
  tryCatch(
    .sicar_download_zip(client, url, temporary),
    error = function(error) .sicar_forget_session_on_302(client, error)
  )
  success <- TRUE
  temporary
}

.sicar_retryable <- function(error) {
  isTRUE(error$retryable)
}

.sicar_slow_retry <- function(error) {
  isTRUE(error$slow_retry)
}

.sicar_retry_delay <- function(attempt, random, slow = FALSE) {
  if (slow) {
    # Reserved for signals that the service itself is struggling (a 5xx,
    # 429, or a dropped connection): back off exponentially so retries
    # don't add to the trouble.
    base <- min(60, 2^(attempt - 1))
    return(base + max(0, min(1, random())))
  }
  # Most retries just mean "that CAPTCHA guess was wrong" or "the session
  # needed a fresh bootstrap" - routine, expected outcomes of automatic
  # CAPTCHA solving, not signs of server trouble - so retry quickly. This
  # mirrors the upstream Python client's flat ~0-2s jitter between
  # attempts, which is what lets a solver with well under 100% accuracy
  # still succeed automatically within a handful of seconds.
  max(0, min(2, random() * 2))
}

.sicar_download_state_polygon <- function(
  client,
  state,
  polygon,
  dest_dir,
  overwrite,
  tries,
  wait,
  random,
  attempt_download
) {
  final_path <- file.path(dest_dir, paste0(state, "_", polygon, ".zip"))
  if (file.exists(final_path) && !overwrite) {
    .sicar_validate_zip(final_path)
    return(normalizePath(final_path, mustWork = TRUE))
  }

  last_error <- NULL
  for (attempt in seq_len(as.integer(tries))) {
    result <- tryCatch(
      attempt_download(client, state, polygon, dest_dir),
      error = function(error) {
        last_error <<- error
        NULL
      }
    )
    if (!is.null(result)) {
      if (file.exists(final_path) && overwrite) {
        unlink(final_path)
      }
      if (!file.rename(result, final_path)) {
        .sicar_abort(
          "The validated download could not be moved to its destination.",
          "rsicar_download_error",
          path = final_path,
          attempt = attempt
        )
      }
      return(normalizePath(final_path, mustWork = TRUE))
    }
    if (!.sicar_retryable(last_error) || attempt == as.integer(tries)) {
      .sicar_abort(
        sprintf("Download failed on attempt %d.", attempt),
        "rsicar_download_error",
        state = state,
        polygon = polygon,
        attempt = attempt,
        parent = last_error,
        retryable = FALSE
      )
    }
    wait(.sicar_retry_delay(
      attempt,
      random,
      slow = .sicar_slow_retry(last_error)
    ))
  }
}

#' Download one or more SICAR polygon archives for a state
#'
#' @param client An object created by [sicar_client()].
#' @param state Brazilian state abbreviation, case-insensitive.
#' @param polygon One or more SICAR polygon types, case-insensitive. All
#'   values are validated before any download starts.
#' @param dest_dir Destination directory.
#' @param overwrite Whether to replace an existing validated archive.
#' @param tries Maximum number of attempts per polygon. Most failed attempts
#'   are just a wrong CAPTCHA guess or an expired session, both retried
#'   within a couple of seconds, so a solver well under 100% accuracy (such
#'   as `sicar_solver_tesseract()`) still needs a generous budget to
#'   automatically land a correct answer; this matches the default used by
#'   the upstream Python client.
#' @param wait Internal sleep function used between retry attempts.
#' @param random Internal jitter function used to calculate retry delays.
#' @param attempt_download Internal dependency-injection hook.
#' @returns The normalized path of the downloaded ZIP archive. When `polygon`
#'   has more than one value, a character vector of paths named by polygon
#'   type.
#' @examples
#' \dontrun{
#' client <- sicar_client(solver = sicar_solver_manual())
#' sicar_download_state(client, "PA", "APPS", dest_dir = "SICAR/PA")
#' sicar_download_state(
#'   client,
#'   "PA",
#'   c("APPS", "RESERVA_LEGAL"),
#'   dest_dir = "SICAR/PA"
#' )
#' }
#' @importFrom stats runif
#' @export
sicar_download_state <- function(
  client,
  state,
  polygon,
  dest_dir,
  overwrite = FALSE,
  tries = 25,
  wait = Sys.sleep,
  random = function() runif(1),
  attempt_download = .sicar_attempt_download
) {
  if (!inherits(client, "sicar_client")) {
    .sicar_abort(
      "`client` must be created by `sicar_client()`.",
      "rsicar_invalid_argument"
    )
  }
  state <- .sicar_validate_state(state)
  polygon <- .sicar_validate_polygon(polygon, multiple = TRUE)
  if (length(dest_dir) != 1L || !is.character(dest_dir) || is.na(dest_dir)) {
    .sicar_abort(
      "`dest_dir` must be one non-missing path.",
      "rsicar_invalid_argument"
    )
  }
  if (length(tries) != 1L || !is.numeric(tries) || is.na(tries) || tries < 1) {
    .sicar_abort(
      "`tries` must be a positive number.",
      "rsicar_invalid_argument"
    )
  }
  if (
    !is.function(wait) || !is.function(random) || !is.function(attempt_download)
  ) {
    .sicar_abort(
      "`wait`, `random`, and `attempt_download` must be functions.",
      "rsicar_invalid_argument"
    )
  }
  if (length(overwrite) != 1L || is.na(overwrite) || !is.logical(overwrite)) {
    .sicar_abort(
      "`overwrite` must be TRUE or FALSE.",
      "rsicar_invalid_argument"
    )
  }

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  .sicar_bootstrap(client)

  paths <- vapply(
    polygon,
    function(one_polygon) {
      .sicar_download_state_polygon(
        client,
        state,
        one_polygon,
        dest_dir,
        overwrite,
        tries,
        wait,
        random,
        attempt_download
      )
    },
    character(1)
  )

  if (length(paths) == 1L) unname(paths) else paths
}

#' Download one SICAR polygon archive for every Brazilian state
#'
#' @param client An object created by [sicar_client()].
#' @param polygon SICAR polygon type, case-insensitive.
#' @param dest_dir Root destination directory.
#' @param overwrite Whether to replace existing validated archives.
#' @param tries Maximum number of attempts per state. See
#'   [sicar_download_state()] for why the default is generous.
#' @param download_state Internal dependency-injection hook; leave at its
#'   default in normal use.
#' @param wait Internal sleep function used between retry attempts.
#' @param random Internal jitter function used to calculate retry delays.
#' @returns A data frame with one row per state and `path`, `status`, and
#'   `error` columns.
#' @examples
#' \dontrun{
#' client <- sicar_client(solver = sicar_solver_manual())
#' sicar_download_country(client, "APPS", dest_dir = "SICAR")
#' }
#' @export
sicar_download_country <- function(
  client,
  polygon,
  dest_dir,
  overwrite = FALSE,
  tries = 25,
  download_state = sicar_download_state,
  wait = Sys.sleep,
  random = function() runif(1)
) {
  if (!inherits(client, "sicar_client")) {
    .sicar_abort(
      "`client` must be created by `sicar_client()`.",
      "rsicar_invalid_argument"
    )
  }
  if (length(dest_dir) != 1L || !is.character(dest_dir) || is.na(dest_dir)) {
    .sicar_abort(
      "`dest_dir` must be one non-missing path.",
      "rsicar_invalid_argument"
    )
  }
  polygon <- .sicar_validate_polygon(polygon)
  results <- lapply(sicar_states(), function(state) {
    state_dir <- file.path(dest_dir, state)
    result <- tryCatch(
      download_state(
        client,
        state,
        polygon,
        state_dir,
        overwrite = overwrite,
        tries = tries,
        wait = wait,
        random = random
      ),
      error = function(error) error
    )
    if (inherits(result, "condition")) {
      data.frame(
        state = state,
        path = NA_character_,
        status = "failed",
        error = conditionMessage(result),
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        state = state,
        path = result,
        status = "success",
        error = NA_character_,
        stringsAsFactors = FALSE
      )
    }
  })
  result <- do.call(rbind, results)
  if (any(result$status == "failed")) {
    .sicar_warn(
      sprintf("%d state download(s) failed.", sum(result$status == "failed")),
      "rsicar_download_warning",
      result = result
    )
  }
  result
}
