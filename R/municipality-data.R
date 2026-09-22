.sicar_validate_municipality_geometries <- function(municipalities) {
  if (!inherits(municipalities, "sf")) {
    .sicar_abort(
      "The municipality reference data is not an `sf` object.",
      "rsicar_spatial_error"
    )
  }

  required <- c("code_muni", "name_muni", "abbrev_state")
  missing <- setdiff(required, names(municipalities))
  if (length(missing) > 0L) {
    .sicar_abort(
      paste0(
        "The municipality reference data is missing required columns: ",
        paste(missing, collapse = ", "),
        "."
      ),
      "rsicar_spatial_error",
      missing = missing
    )
  }

  if (is.na(sf::st_crs(municipalities))) {
    .sicar_abort(
      "The municipality reference data has no CRS.",
      "rsicar_spatial_error"
    )
  }

  municipalities$code_muni <- sprintf(
    "%07.0f",
    as.numeric(municipalities$code_muni)
  )
  if (
    anyNA(municipalities$code_muni) ||
      any(nchar(municipalities$code_muni) != 7L) ||
      anyDuplicated(municipalities$code_muni)
  ) {
    .sicar_abort(
      "The municipality reference codes are not unique seven-digit values.",
      "rsicar_spatial_error"
    )
  }

  municipalities
}

.sicar_municipality_cache_path <- function() {
  file.path(
    tools::R_user_dir("rsicar", which = "cache"),
    "municipalities-2025.rds"
  )
}

.sicar_download_municipalities <- function() {
  if (!requireNamespace("geobr", quietly = TRUE)) {
    .sicar_abort(
      "Install the `geobr` package to download municipality geometries.",
      "rsicar_dependency_error",
      package = "geobr"
    )
  }

  cli::cli_progress_step(
    "Downloading municipality geometries from geobr (first run only; cached afterwards)"
  )
  municipalities <- tryCatch(
    geobr::read_municipality(
      year = 2025,
      simplified = FALSE,
      output = "sf",
      showProgress = FALSE,
      verbose = FALSE
    ),
    error = function(error) {
      .sicar_abort(
        "Could not download the 2025 municipality geometries from geobr.",
        "rsicar_spatial_error",
        parent = error,
        source = "geobr::read_municipality"
      )
    }
  )

  .sicar_validate_municipality_geometries(municipalities)
}

.sicar_municipality_geometries <- function() {
  cache_path <- .sicar_municipality_cache_path()
  if (file.exists(cache_path)) {
    cached <- tryCatch(
      readRDS(cache_path),
      error = function(error) {
        .sicar_abort(
          "Could not read the cached municipality geometries.",
          "rsicar_spatial_error",
          parent = error,
          path = cache_path
        )
      }
    )
    return(.sicar_validate_municipality_geometries(cached))
  }

  municipalities <- .sicar_download_municipalities()
  cache_dir <- dirname(cache_path)
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(cache_dir)) {
    .sicar_abort(
      "Could not create the municipality geometry cache directory.",
      "rsicar_source_error",
      path = cache_dir
    )
  }

  temporary_path <- tempfile(
    pattern = "municipalities-",
    tmpdir = cache_dir,
    fileext = ".rds"
  )
  on.exit(unlink(temporary_path, force = TRUE), add = TRUE)
  tryCatch(
    saveRDS(municipalities, temporary_path, compress = "xz"),
    error = function(error) {
      .sicar_abort(
        "Could not cache the municipality geometries.",
        "rsicar_source_error",
        parent = error,
        path = cache_path
      )
    }
  )

  if (!file.rename(temporary_path, cache_path) && !file.exists(cache_path)) {
    .sicar_abort(
      "Could not finalize the municipality geometry cache.",
      "rsicar_source_error",
      path = cache_path
    )
  }
  municipalities
}
