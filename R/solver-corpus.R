.sicar_prepare_captcha_corpus <- function(directory) {
  manifest <- file.path(directory, "manifest.csv")
  if (file.exists(manifest)) {
    existing <- .sicar_captcha_manifest(manifest)
    data <- utils::read.csv(manifest, colClasses = "character", na.strings = "")
    data$expected[is.na(data$expected)] <- ""
    known <- existing$md5
  } else {
    data <- data.frame(
      id = character(),
      path = character(),
      expected = character(),
      split = character(),
      protect = character()
    )
    known <- character()
  }
  paths <- list.files(
    directory,
    pattern = "[.]png$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  hashes <- unname(tools::md5sum(paths))
  if (anyNA(hashes)) {
    .sicar_abort(
      "Some corpus images could not be read.",
      "rsicar_benchmark_error"
    )
  }
  new <- !duplicated(hashes) & !hashes %in% known
  added <- data.frame(
    id = hashes[new],
    path = basename(paths[new]),
    expected = rep("", sum(new)),
    # Hash assignment is stable when more images arrive and ignores OCR output.
    split = ifelse(
      strtoi(substr(hashes[new], 1, 2), 16L) < 51L,
      "evaluation",
      "development"
    ),
    protect = rep("FALSE", sum(new))
  )
  data <- rbind(data, added)
  if (!nrow(data)) {
    .sicar_abort(
      "No PNG images found in the corpus directory.",
      "rsicar_benchmark_error"
    )
  }
  if (!file.exists(manifest) || any(new)) {
    utils::write.csv(data, manifest, row.names = FALSE, na = "")
  }
  data
}
