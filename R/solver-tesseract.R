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
      "rscicar_missing_dependency",
      packages = missing[!available]
    )
  }
}

.sicar_tesseract_preprocess <- function(path) {
  image <- magick::image_read(path)
  image <- magick::image_convert(image, colorspace = "gray")
  pixels <- as.integer(magick::image_data(image, channels = "gray"))
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
  threshold <- (which.max(between_class_variance) - 1) / 255 * 100
  image <- magick::image_threshold(
    image,
    type = "black",
    threshold = sprintf("%.6f%%", threshold)
  )
  image <- magick::image_morphology(
    image,
    method = "Dilate",
    kernel = "Rectangle:3x2"
  )
  image <- magick::image_morphology(
    image,
    method = "Erode",
    kernel = "Rectangle:4x1",
    iterations = 2
  )
  image <- magick::image_morphology(
    image,
    method = "Dilate",
    kernel = "Rectangle:3x1",
    iterations = 2
  )
  image <- magick::image_morphology(
    image,
    method = "Erode",
    kernel = "Rectangle:2x1",
    iterations = 2
  )
  image
}

#' Create a CAPTCHA solver backed by Tesseract OCR
#'
#' The optional `magick` and `tesseract` packages are checked when this solver
#' is created. The solver applies grayscale conversion, thresholding and
#' morphology before using Tesseract page segmentation mode 7.
#'
#' @returns An object usable as the `solver` argument of `sicar_client()`.
#' @export
sicar_solver_tesseract <- function() {
  .sicar_tesseract_requirements()
  engine <- tesseract::tesseract(
    language = "eng",
    options = list(
      tessedit_pageseg_mode = 7,
      tessedit_char_whitelist = paste0(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abcdefghijklmnopqrstuvwxyz",
        "0123456789"
      )
    )
  )

  .sicar_solver(
    function(path) {
      recognized <- tesseract::ocr(
        .sicar_tesseract_preprocess(path),
        engine = engine
      )
      gsub("[^A-Za-z0-9]", "", recognized)
    },
    "tesseract"
  )
}
