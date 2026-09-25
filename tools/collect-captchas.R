# Opt-in, low-volume collection. Run from the repository root.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: collect-captchas.R COUNT DIRECTORY", call. = FALSE)
}
if (!identical(Sys.getenv("RSICAR_RUN_LIVE_TESTS"), "true")) {
  stop("Set RSICAR_RUN_LIVE_TESTS=true to collect from SICAR.", call. = FALSE)
}
count <- suppressWarnings(as.numeric(args[1]))
if (!is.finite(count) || count != floor(count) || count < 1L || count > 100L) {
  stop("COUNT must be an integer between 1 and 100.", call. = FALSE)
}
devtools::load_all(quiet = TRUE)
dest <- args[2]
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
dest <- normalizePath(dest, mustWork = TRUE)
client <- rsicar::sicar_client(timeout = 30)
rsicar:::.sicar_bootstrap(client)
existing <- list.files(dest, pattern = "^[a-f0-9]{32}[.]png$")
remaining <- max(0L, count - length(existing))
for (i in seq_len(remaining)) {
  if (i > 1L) {
    Sys.sleep(2)
  }
  path <- rsicar:::.sicar_download_captcha(client)
  hash <- unname(tools::md5sum(path))
  target <- file.path(dest, paste0(hash, ".png"))
  if (!file.exists(target)) {
    if (!file.copy(path, target)) {
      stop("Could not save CAPTCHA.")
    }
    jsonlite::write_json(
      list(
        source = "SICAR public CAPTCHA endpoint",
        collected_at = rsicar:::.sicar_now_iso8601(),
        image = basename(target),
        md5 = hash
      ),
      file.path(dest, paste0(hash, ".json")),
      auto_unbox = TRUE,
      pretty = TRUE
    )
  }
  unlink(path)
  cat(sprintf("Collected %d/%d\n", length(existing) + i, count))
}
cat("Unique images:", length(list.files(dest, pattern = "[.]png$")), "\n")
