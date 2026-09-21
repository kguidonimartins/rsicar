.sicar_source_files <- function(src_dir) {
  if (
    length(src_dir) != 1L ||
      !is.character(src_dir) ||
      is.na(src_dir) ||
      !nzchar(trimws(src_dir))
  ) {
    .sicar_abort(
      "`src_dir` must be one non-missing path.",
      "rsicar_invalid_argument",
      field = "src_dir",
      value = src_dir
    )
  }

  src_dir <- path.expand(src_dir)
  if (!file.exists(src_dir)) {
    .sicar_abort(
      sprintf("Source path does not exist: `%s`.", src_dir),
      "rsicar_source_error",
      path = src_dir
    )
  }

  if (dir.exists(src_dir)) {
    paths <- list.files(
      src_dir,
      pattern = "\\.zip$",
      full.names = TRUE,
      recursive = TRUE,
      ignore.case = TRUE
    )
  } else {
    if (!grepl("\\.zip$", src_dir, ignore.case = TRUE)) {
      .sicar_abort(
        sprintf("Source file is not a ZIP archive: `%s`.", src_dir),
        "rsicar_source_error",
        path = src_dir
      )
    }
    paths <- src_dir
  }

  if (length(paths) == 0L) {
    .sicar_abort(
      sprintf("No ZIP archives were found in `%s`.", src_dir),
      "rsicar_source_error",
      path = src_dir
    )
  }

  paths <- normalizePath(paths, mustWork = TRUE)
  paths <- sort(unique(paths))
  for (path in paths) {
    tryCatch(
      .sicar_validate_zip(path),
      error = function(error) {
        .sicar_abort(
          sprintf("Source ZIP archive is invalid: `%s`.", path),
          "rsicar_source_error",
          parent = error,
          path = path
        )
      }
    )
  }

  paths
}
