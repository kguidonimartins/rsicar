.sicar_tesseract_requirements <- function() {
  missing <- c("magick", "tesseract")
  available <- vapply(missing, requireNamespace, logical(1), quietly = TRUE)
  if (any(!available)) {
    .sicar_abort(
      paste0(
        "The Tesseract solver requires the R packages ",
        paste(missing[!available], collapse = " and "),
        ". Install them with install.packages(c(\"magick\", \"tesseract\"))."
      ),
      "rsicar_missing_dependency",
      packages = missing[!available]
    )
  }
}

.sicar_tesseract_preprocess <- function(path) {
  image <- magick::image_background(
    magick::image_read(path),
    "white",
    flatten = TRUE
  )
  rgb <- magick::image_data(image, channels = "rgb")
  width <- dim(rgb)[2]
  height <- dim(rgb)[3]
  # OpenCV's BGR-to-gray conversion uses these channel weights. The upstream
  # solver then applies Otsu with THRESH_TRUNC, retaining values below the
  # threshold and capping those above it instead of making a binary image.
  pixels <- round(
    0.299 *
      as.integer(rgb[1, , ]) +
      0.587 * as.integer(rgb[2, , ]) +
      0.114 * as.integer(rgb[3, , ])
  )
  histogram <- tabulate(pixels + 1L, nbins = 256L)
  probabilities <- histogram / sum(histogram)
  cumulative_probability <- cumsum(probabilities)
  cumulative_mean <- cumsum(probabilities * 0:255)
  global_mean <- cumulative_mean[256]
  between_class_variance <- (global_mean *
    cumulative_probability -
    cumulative_mean)^2 /
    (cumulative_probability * (1 - cumulative_probability))
  between_class_variance[!is.finite(between_class_variance)] <- 0
  threshold <- which.max(between_class_variance) - 1L
  pixels <- pmin(pixels, threshold)
  colors <- sprintf("#%02X%02X%02X", pixels, pixels, pixels)
  image <- magick::image_read(
    grDevices::as.raster(t(matrix(colors, nrow = width, ncol = height)))
  )
  # OpenCV kernel matrices are specified as rows x columns. ImageMagick's
  # Rectangle kernels take width x height, so the dimensions are transposed.
  image <- magick::image_morphology(
    image,
    method = "Dilate",
    kernel = "Rectangle:2x3"
  )
  image <- magick::image_morphology(
    image,
    method = "Erode",
    kernel = "Rectangle:1x4",
    iterations = 2
  )
  image <- magick::image_morphology(
    image,
    method = "Dilate",
    kernel = "Rectangle:1x3",
    iterations = 2
  )
  image <- magick::image_morphology(
    image,
    method = "Erode",
    kernel = "Rectangle:1x2",
    iterations = 2
  )
  image
}

.sicar_tesseract_preprocess_red <- function(path) {
  image <- magick::image_background(
    magick::image_read(path),
    "white",
    flatten = TRUE
  )
  # The interference stroke is red while the characters are dark. Its red
  # channel therefore has much less of the stroke than a grayscale image.
  magick::image_separate(image, channel = "red") |>
    magick::image_resize("200%")
}

.sicar_tesseract_read <- function(image, engine) {
  words <- tesseract::ocr_data(image, engine = engine)
  confidence <- words$confidence[is.finite(words$confidence)]
  list(
    value = gsub("[^A-Za-z0-9]", "", paste(words$word, collapse = "")),
    confidence = if (length(confidence) > 0L) mean(confidence) else 0
  )
}

.sicar_tesseract_engine <- function(psm = 7L, dictionaries = TRUE) {
  tesseract::tesseract(
    language = "eng",
    options = list(
      tessedit_pageseg_mode = psm,
      load_system_dawg = as.integer(dictionaries),
      load_freq_dawg = as.integer(dictionaries),
      tessedit_char_whitelist = paste0(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
      )
    ),
    cache = FALSE
  )
}

.sicar_tesseract_candidates <- function(path, engine, border = 0L) {
  preprocessors <- list(
    primary = .sicar_tesseract_preprocess,
    red = .sicar_tesseract_preprocess_red
  )
  rows <- lapply(names(preprocessors), function(method) {
    start <- proc.time()[["elapsed"]]
    image <- preprocessors[[method]](path)
    if (border > 0L) {
      image <- magick::image_border(image, "white", paste0(border, "x", border))
    }
    reading <- .sicar_tesseract_read(image, engine)
    data.frame(
      method = method,
      value = reading$value,
      confidence = reading$confidence,
      elapsed_seconds = proc.time()[["elapsed"]] - start,
      valid = grepl("^[A-Za-z0-9]{5}$", reading$value)
    )
  })
  do.call(rbind, rows)
}

.sicar_tesseract_select <- function(candidates, margin = 30) {
  primary <- candidates[1L, ]
  red <- candidates[2L, ]
  if (red$valid && !primary$valid) {
    return(list(index = 2L, reason = "valid_red"))
  }
  if (primary$valid && identical(primary$value, red$value)) {
    return(list(index = 1L, reason = "agreement"))
  }
  if (red$valid && red$confidence >= primary$confidence + margin) {
    return(list(index = 2L, reason = "confidence_red"))
  }
  list(index = 1L, reason = "primary")
}

#' Create a CAPTCHA solver backed by Tesseract OCR
#'
#' The optional `magick` and `tesseract` packages are checked when this solver
#' is created. The solver applies grayscale conversion, Otsu truncation and
#' morphology before using Tesseract page segmentation mode 7 (single line).
#' It also reads an enlarged red channel to reduce the red interference line,
#' using that answer when the first pass is incomplete or the second has much
#' higher OCR confidence.
#'
#' This solver is experimental. Tesseract can still confuse similar characters
#' or return an incomplete answer; `sicar_download_state()` retries rejected
#' CAPTCHAs. Prefer `sicar_solver_manual()` or a custom
#' `sicar_solver_function()` where accuracy matters.
#'
#' @param diagnostics_dir Optional directory in which to save each input PNG
#'   and a JSON record of both readings, confidence scores, timing, selection
#'   and OCR environment. Defaults to `NULL` (no files). These records contain
#'   predictions, not verified CAPTCHA answers or download outcomes. Files are
#'   saved before answer validation, so incomplete readings are retained too.
#'   A write failure emits an `rsicar_diagnostics_warning` and solving continues.
#' @returns An object usable as the `solver` argument of `sicar_client()`.
#' @examples
#' \dontrun{
#' # Requires the optional `magick` and `tesseract` R packages and the
#' # Tesseract OCR program installed on the system.
#' solver <- sicar_solver_tesseract()
#' solver <- sicar_solver_tesseract(diagnostics_dir = "captcha-diagnostics")
#' }
#' @export
sicar_solver_tesseract <- function(diagnostics_dir = NULL) {
  if (
    !is.null(diagnostics_dir) &&
      (!is.character(diagnostics_dir) ||
        length(diagnostics_dir) != 1L ||
        is.na(diagnostics_dir) ||
        !nzchar(trimws(diagnostics_dir)))
  ) {
    .sicar_abort(
      "`diagnostics_dir` must be NULL or one non-empty directory path.",
      "rsicar_invalid_argument",
      field = "diagnostics_dir"
    )
  }
  .sicar_tesseract_requirements()
  engine <- .sicar_tesseract_engine()
  environment <- NULL

  .sicar_solver(
    function(path) {
      candidates <- .sicar_tesseract_candidates(path, engine)
      selected <- .sicar_tesseract_select(candidates)
      if (!is.null(diagnostics_dir)) {
        if (is.null(environment)) {
          environment <<- .sicar_tesseract_environment()
        }
        .sicar_tesseract_diagnostics(
          path,
          diagnostics_dir,
          candidates,
          selected,
          environment
        )
      }
      candidates$value[selected$index]
    },
    "tesseract"
  )
}
