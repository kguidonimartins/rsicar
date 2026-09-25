# Builds a browser-based, offline labeling page. No OCR guesses are shown.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || length(args) > 3L) {
  stop(
    "Usage: prepare-captcha-corpus.R DIRECTORY [development | evaluation FROZEN_CONFIG]",
    call. = FALSE
  )
}
devtools::load_all(quiet = TRUE)
directory <- normalizePath(args[1], mustWork = TRUE)
split <- if (length(args) >= 2L) args[2] else "development"
if (!split %in% c("development", "evaluation")) {
  stop("Invalid split.")
}
data <- rsicar:::.sicar_prepare_captcha_corpus(directory)
manifest <- rsicar:::.sicar_captcha_manifest(file.path(
  directory,
  "manifest.csv"
))
if (split == "evaluation") {
  if (length(args) != 3L) {
    stop("Freeze a development configuration before opening evaluation images.")
  }
  lock <- jsonlite::read_json(args[3], simplifyVector = TRUE)
  if (is.null(lock$development_images_md5) || is.null(lock$configuration)) {
    stop("Invalid frozen configuration.")
  }
  if (
    any(manifest$md5[manifest$split == split] %in% lock$development_images_md5)
  ) {
    stop("Evaluation images overlap the tuning corpus.")
  }
}
images <- lapply(which(data$split == split), function(i) {
  path <- manifest$path[i]
  list(
    id = data$id[i],
    png = jsonlite::base64_enc(readBin(path, "raw", file.info(path)$size))
  )
})
payload <- jsonlite::toJSON(
  list(rows = data, images = images, split = split),
  auto_unbox = TRUE
)
payload <- gsub("<", "\\u003c", payload, fixed = TRUE)
template <- paste(
  readLines("tools/label-captchas.html", warn = FALSE),
  collapse = "\n"
)
parts <- strsplit(template, "__CORPUS_DATA__", fixed = TRUE)[[1]]
output <- file.path(directory, paste0("label-", split, ".html"))
writeLines(paste0(parts[1], payload, parts[2]), output)
cat("Manifest:", file.path(directory, "manifest.csv"), "\n")
cat("Labeling page:", output, "\n")
print(table(data$split))
