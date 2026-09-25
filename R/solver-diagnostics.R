.sicar_tesseract_environment <- function() {
  info <- tesseract::tesseract_info()
  model <- file.path(info$datapath, "eng.traineddata")
  list(
    rsicar = as.character(utils::packageVersion("rsicar")),
    R = as.character(getRversion()),
    platform = R.version$platform,
    tesseract = info$version,
    tesseract_package = as.character(utils::packageVersion("tesseract")),
    magick_package = as.character(utils::packageVersion("magick")),
    imagemagick = as.character(magick::magick_config()$version),
    language = "eng",
    traineddata_md5 = if (file.exists(model)) {
      unname(tools::md5sum(model))
    } else {
      NA_character_
    }
  )
}

.sicar_tesseract_diagnostics <- function(
  path,
  dest_dir,
  candidates,
  selected,
  environment
) {
  image_path <- NULL
  record_path <- NULL
  tryCatch(
    {
      if (file.exists(dest_dir) && !dir.exists(dest_dir)) {
        stop("Diagnostic destination is not a directory.")
      }
      if (!dir.exists(dest_dir)) {
        dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
      }
      stem <- tempfile("captcha-", tmpdir = dest_dir)
      image_path <- paste0(stem, ".png")
      record_path <- paste0(stem, ".json")
      if (!suppressWarnings(file.copy(path, image_path, overwrite = FALSE))) {
        stop("Could not copy the CAPTCHA image.")
      }
      candidates$selected <- seq_len(nrow(candidates)) == selected$index
      record <- list(
        schema_version = 1L,
        collected_at = .sicar_now_iso8601(),
        image = basename(image_path),
        image_md5 = unname(tools::md5sum(image_path)),
        candidates = candidates,
        answer = candidates$value[selected$index],
        selection_reason = selected$reason,
        configuration = list(
          psm = 7L,
          dictionaries = TRUE,
          border = 0L,
          margin = 30
        ),
        environment = environment
      )
      jsonlite::write_json(
        record,
        record_path,
        auto_unbox = TRUE,
        pretty = TRUE,
        na = "null"
      )
      invisible(record_path)
    },
    error = function(error) {
      unlink(c(image_path, record_path))
      .sicar_warn(
        "CAPTCHA diagnostics could not be saved; solving will continue.",
        "rsicar_diagnostics_warning",
        path = dest_dir,
        parent = error
      )
      invisible(NULL)
    }
  )
}
