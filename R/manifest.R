.sicar_manifest_path <- function(dest_dir) {
  file.path(dest_dir, "manifest.json")
}

.sicar_now_iso8601 <- function(time = Sys.time()) {
  format(time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

.sicar_manifest_empty <- function() {
  list(schema_version = 1L, updated_at = NA_character_, downloads = list())
}

.sicar_manifest_read_raw <- function(dest_dir) {
  path <- .sicar_manifest_path(dest_dir)
  if (!file.exists(path)) {
    return(.sicar_manifest_empty())
  }
  manifest <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(error) {
      .sicar_abort(
        sprintf(
          "The manifest at `%s` could not be parsed: %s",
          path,
          conditionMessage(error)
        ),
        "rsicar_manifest_error",
        parent = error,
        path = path
      )
    }
  )
  if (is.null(manifest$downloads)) {
    manifest$downloads <- list()
  }
  manifest
}

.sicar_manifest_entry_key <- function(entry) {
  paste(entry$state, entry$polygon, sep = "_")
}

.sicar_manifest_upsert <- function(dest_dir, entry) {
  manifest <- .sicar_manifest_read_raw(dest_dir)
  downloads <- manifest$downloads
  keys <- vapply(downloads, .sicar_manifest_entry_key, character(1))
  match_index <- match(.sicar_manifest_entry_key(entry), keys)
  if (is.na(match_index)) {
    downloads[[length(downloads) + 1L]] <- entry
  } else {
    downloads[[match_index]] <- entry
  }
  manifest$downloads <- downloads
  manifest$schema_version <- 1L
  manifest$updated_at <- .sicar_now_iso8601()

  path <- .sicar_manifest_path(dest_dir)
  temporary <- tempfile("rsicar-manifest-", tmpdir = dest_dir, fileext = ".json")
  jsonlite::write_json(
    manifest,
    temporary,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )
  if (!file.rename(temporary, path)) {
    unlink(temporary)
    .sicar_abort(
      "The manifest could not be written to its destination.",
      "rsicar_manifest_error",
      path = path
    )
  }
  invisible(manifest)
}

.sicar_manifest_entry <- function(
  state,
  polygon,
  path,
  solver,
  attempts,
  tries,
  overwrite,
  downloaded_at
) {
  list(
    state = state,
    polygon = polygon,
    file = basename(path),
    size_bytes = as.numeric(file.info(path)$size),
    md5 = unname(tools::md5sum(path)),
    downloaded_at = downloaded_at,
    solver = solver,
    attempts = attempts,
    tries = as.integer(tries),
    overwrite = isTRUE(overwrite),
    rsicar_version = as.character(utils::packageVersion("rsicar")),
    status = "success"
  )
}

# Called after a fresh, successful download: always (re)records the entry,
# since `attempt` reflects what actually just happened.
.sicar_manifest_record_download <- function(
  dest_dir,
  state,
  polygon,
  path,
  client,
  attempt,
  tries,
  overwrite
) {
  entry <- .sicar_manifest_entry(
    state,
    polygon,
    path,
    client$solver$name,
    as.integer(attempt),
    tries,
    overwrite,
    .sicar_now_iso8601()
  )
  .sicar_manifest_upsert(dest_dir, entry)
}

# Called when an already-validated archive on disk is reused instead of
# downloaded again: only backfills a manifest entry if one is not already
# recorded, so a real download's `attempts` is never overwritten with NA.
.sicar_manifest_ensure_recorded <- function(
  dest_dir,
  state,
  polygon,
  path,
  client,
  tries,
  overwrite
) {
  manifest <- .sicar_manifest_read_raw(dest_dir)
  keys <- vapply(manifest$downloads, .sicar_manifest_entry_key, character(1))
  if (paste(state, polygon, sep = "_") %in% keys) {
    return(invisible(NULL))
  }
  entry <- .sicar_manifest_entry(
    state,
    polygon,
    path,
    client$solver$name,
    NA_integer_,
    tries,
    overwrite,
    .sicar_now_iso8601(file.info(path)$mtime)
  )
  .sicar_manifest_upsert(dest_dir, entry)
}

.sicar_manifest_to_data_frame <- function(manifest) {
  downloads <- manifest$downloads
  if (length(downloads) == 0L) {
    return(data.frame(
      state = character(),
      polygon = character(),
      file = character(),
      size_bytes = numeric(),
      md5 = character(),
      downloaded_at = character(),
      solver = character(),
      attempts = numeric(),
      tries = numeric(),
      overwrite = logical(),
      rsicar_version = character(),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(downloads, function(entry) {
    data.frame(
      state = entry$state %||% NA_character_,
      polygon = entry$polygon %||% NA_character_,
      file = entry$file %||% NA_character_,
      size_bytes = as.numeric(entry$size_bytes %||% NA_real_),
      md5 = entry$md5 %||% NA_character_,
      downloaded_at = entry$downloaded_at %||% NA_character_,
      solver = entry$solver %||% NA_character_,
      attempts = as.numeric(entry$attempts %||% NA_real_),
      tries = as.numeric(entry$tries %||% NA_real_),
      overwrite = isTRUE(entry$overwrite),
      rsicar_version = entry$rsicar_version %||% NA_character_,
      status = entry$status %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Read a SICAR download manifest
#'
#' [sicar_download_state()] records a `manifest.json` file in `dest_dir`
#' after each successful download, with the polygon type, file size and
#' checksum, download timestamp, CAPTCHA solver used, and number of
#' attempts it took. This reads that file back as a data frame.
#'
#' @param dest_dir Directory that may contain a `manifest.json` file.
#' @returns A data frame with one row per recorded download and `state`,
#'   `polygon`, `file`, `size_bytes`, `md5`, `downloaded_at`, `solver`,
#'   `attempts`, `tries`, `overwrite`, `rsicar_version`, and `status`
#'   columns. Zero rows (with those columns) when `dest_dir` has no
#'   manifest yet.
#' @examples
#' \dontrun{
#' sicar_read_manifest("SICAR/PA")
#' }
#' @export
sicar_read_manifest <- function(dest_dir) {
  if (length(dest_dir) != 1L || !is.character(dest_dir) || is.na(dest_dir)) {
    .sicar_abort(
      "`dest_dir` must be one non-missing path.",
      "rsicar_invalid_argument"
    )
  }
  .sicar_manifest_to_data_frame(.sicar_manifest_read_raw(dest_dir))
}

#' Diagnose missing or corrupted SICAR downloads in a state directory
#'
#' Compares `polygon` against what `dest_dir`'s `manifest.json` (see
#' [sicar_read_manifest()]) says was downloaded there, and checks that each
#' recorded file is still present on disk at its recorded size. Use this
#' after a run that stopped partway - for example because a CAPTCHA solver
#' exhausted its `tries` on one polygon type - to see what is left to
#' (re)download.
#'
#' @param dest_dir Directory that may contain a `manifest.json` file, as
#'   written by [sicar_download_state()].
#' @param polygon SICAR polygon types expected in `dest_dir`, case-
#'   insensitive. Defaults to every type returned by [sicar_polygon_types()].
#' @returns A data frame with one row per `polygon` value and `polygon`,
#'   `status` (one of `"downloaded"`, `"corrupted"`, or `"missing"`),
#'   `file`, `size_bytes`, `downloaded_at`, and `solver` columns.
#'   `"corrupted"` means a manifest entry exists but the file is now
#'   missing or a different size than recorded; `"missing"` means no
#'   attempt was ever recorded.
#' @examples
#' \dontrun{
#' sicar_download_status("SICAR/PA")
#' sicar_download_status("SICAR/PA", c("APPS", "RESERVA_LEGAL"))
#' }
#' @export
sicar_download_status <- function(dest_dir, polygon = sicar_polygon_types()) {
  if (length(dest_dir) != 1L || !is.character(dest_dir) || is.na(dest_dir)) {
    .sicar_abort(
      "`dest_dir` must be one non-missing path.",
      "rsicar_invalid_argument"
    )
  }
  polygon <- .sicar_validate_polygon(polygon, multiple = TRUE)
  manifest <- sicar_read_manifest(dest_dir)

  rows <- lapply(polygon, function(one_polygon) {
    entry <- manifest[manifest$polygon == one_polygon, , drop = FALSE]
    if (nrow(entry) == 0L) {
      return(data.frame(
        polygon = one_polygon,
        status = "missing",
        file = NA_character_,
        size_bytes = NA_real_,
        downloaded_at = NA_character_,
        solver = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
    entry <- entry[1L, ]
    file_path <- file.path(dest_dir, entry$file)
    on_disk <- file.exists(file_path)
    size_matches <- on_disk &&
      isTRUE(all.equal(as.numeric(file.info(file_path)$size), entry$size_bytes))
    data.frame(
      polygon = one_polygon,
      status = if (size_matches) "downloaded" else "corrupted",
      file = entry$file,
      size_bytes = entry$size_bytes,
      downloaded_at = entry$downloaded_at,
      solver = entry$solver,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Diagnose missing or corrupted SICAR downloads across states
#'
#' Applies [sicar_download_status()] to every state's subdirectory of
#' `dest_dir`, matching the layout [sicar_download_country()] writes
#' (`dest_dir/<state>/manifest.json`).
#'
#' @param dest_dir Root directory passed to [sicar_download_country()].
#' @param polygon SICAR polygon types expected for each state, case-
#'   insensitive. Defaults to every type returned by [sicar_polygon_types()].
#' @param state Brazilian state abbreviations to check, case-insensitive.
#'   Defaults to every state returned by [sicar_states()].
#' @returns A data frame with one row per `state`/`polygon` combination; see
#'   [sicar_download_status()] for the remaining columns.
#' @examples
#' \dontrun{
#' sicar_download_country_status("SICAR")
#' }
#' @export
sicar_download_country_status <- function(
  dest_dir,
  polygon = sicar_polygon_types(),
  state = sicar_states()
) {
  if (length(dest_dir) != 1L || !is.character(dest_dir) || is.na(dest_dir)) {
    .sicar_abort(
      "`dest_dir` must be one non-missing path.",
      "rsicar_invalid_argument"
    )
  }
  state <- .sicar_validate_state(state, multiple = TRUE)
  results <- lapply(state, function(one_state) {
    status <- sicar_download_status(file.path(dest_dir, one_state), polygon)
    cbind(state = one_state, status, stringsAsFactors = FALSE)
  })
  do.call(rbind, results)
}
