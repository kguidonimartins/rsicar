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
  on.exit(unlink(path), add = TRUE)
  writeBin(httr2::resp_body_raw(response), path)
  path
}

.sicar_validate_zip <- function(path) {
  if (!file.exists(path) || file.info(path)$size <= 0) {
    .sicar_abort(
      "The downloaded file is empty or missing.",
      "rscicar_download_error",
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
      "rscicar_download_error",
      path = path
    )
  }
  tryCatch(
    utils::unzip(path, list = TRUE),
    error = function(error) {
      .sicar_abort(
        "The downloaded ZIP archive is invalid or truncated.",
        "rscicar_download_error",
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
        "rscicar_download_error",
        parent = error,
        url = url,
        path = path
      )
    }
  )
  .sicar_require_response(response, url, 200, "application/zip")
  if (!file.exists(path) || file.info(path)$size == 0) {
    writeBin(httr2::resp_body_raw(response), path)
  }
  .sicar_validate_zip(path)
  invisible(path)
}

.sicar_attempt_download <- function(client, state, polygon, dest_dir) {
  captcha_path <- .sicar_download_captcha(client)
  captcha <- .sicar_solve(client$solver, captcha_path)
  url <- .sicar_download_url(client, state, polygon, captcha)
  temporary <- tempfile(
    pattern = paste0(state, "_", polygon, "-"),
    tmpdir = dest_dir,
    fileext = ".zip"
  )
  success <- FALSE
  on.exit(if (!success) unlink(temporary), add = TRUE)
  .sicar_download_zip(client, url, temporary)
  success <- TRUE
  temporary
}

#' Download one SICAR polygon archive
#'
#' @param client An object created by [sicar_client()].
#' @param state Brazilian state abbreviation, case-insensitive.
#' @param polygon SICAR polygon type, case-insensitive.
#' @param dest_dir Destination directory.
#' @param overwrite Whether to replace an existing validated archive.
#' @param tries Maximum number of attempts.
#' @returns The normalized path of the downloaded ZIP archive.
#' @export
sicar_download_state <- function(
  client,
  state,
  polygon,
  dest_dir,
  overwrite = FALSE,
  tries = 3
) {
  if (!inherits(client, "sicar_client")) {
    .sicar_abort(
      "`client` must be created by `sicar_client()`.",
      "rscicar_invalid_argument"
    )
  }
  state <- .sicar_validate_state(state)
  polygon <- .sicar_validate_polygon(polygon)
  if (length(dest_dir) != 1L || !is.character(dest_dir) || is.na(dest_dir)) {
    .sicar_abort(
      "`dest_dir` must be one non-missing path.",
      "rscicar_invalid_argument"
    )
  }
  if (length(tries) != 1L || !is.numeric(tries) || is.na(tries) || tries < 1) {
    .sicar_abort(
      "`tries` must be a positive number.",
      "rscicar_invalid_argument"
    )
  }
  if (length(overwrite) != 1L || is.na(overwrite) || !is.logical(overwrite)) {
    .sicar_abort(
      "`overwrite` must be TRUE or FALSE.",
      "rscicar_invalid_argument"
    )
  }

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  .sicar_bootstrap(client)
  final_path <- file.path(dest_dir, paste0(state, "_", polygon, ".zip"))
  if (file.exists(final_path) && !overwrite) {
    .sicar_validate_zip(final_path)
    return(normalizePath(final_path, mustWork = TRUE))
  }

  last_error <- NULL
  for (attempt in seq_len(as.integer(tries))) {
    result <- tryCatch(
      .sicar_attempt_download(client, state, polygon, dest_dir),
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
          "rscicar_download_error",
          path = final_path,
          attempt = attempt
        )
      }
      return(normalizePath(final_path, mustWork = TRUE))
    }
  }

  .sicar_abort(
    sprintf("Download failed after %d attempt(s).", tries),
    "rscicar_download_error",
    state = state,
    polygon = polygon,
    attempt = tries,
    parent = last_error
  )
}

#' Download one SICAR polygon archive for every Brazilian state
#'
#' @param client An object created by [sicar_client()].
#' @param polygon SICAR polygon type, case-insensitive.
#' @param dest_dir Root destination directory.
#' @param overwrite Whether to replace existing validated archives.
#' @param tries Maximum number of attempts per state.
#' @param download_state Internal dependency-injection hook; leave at its
#'   default in normal use.
#' @returns A data frame with one row per state and `path`, `status`, and
#'   `error` columns.
#' @export
sicar_download_country <- function(
  client,
  polygon,
  dest_dir,
  overwrite = FALSE,
  tries = 3,
  download_state = sicar_download_state
) {
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
        tries = tries
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
      "rscicar_download_warning",
      result = result
    )
  }
  result
}
