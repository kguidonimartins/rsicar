# Run from the repository root. All OCR and scoring are offline.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || !args[1] %in% c("tune", "evaluate", "downloads")) {
  stop(
    "Usage: benchmark-tesseract.R tune MANIFEST OUTPUT | evaluate MANIFEST OUTPUT FROZEN_CONFIG | downloads CSV OUTPUT",
    call. = FALSE
  )
}
if (args[1] == "evaluate" && length(args) != 4L) {
  stop(
    "Evaluation requires a frozen configuration from a development run.",
    call. = FALSE
  )
}
devtools::load_all(quiet = TRUE)
if (args[1] == "downloads") {
  summary <- rsicar:::.sicar_benchmark_downloads(args[2])
  dir.create(args[3], recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    summary,
    file.path(args[3], "downloads.csv"),
    row.names = FALSE
  )
  print(summary, row.names = FALSE)
  quit(status = 0L)
}
summary <- rsicar:::.sicar_benchmark_run(
  args[2],
  args[3],
  mode = args[1],
  frozen = if (length(args) == 4L) args[4] else NULL
)
rank <- order(summary$protected_failures, -summary$correct)
print(utils::head(summary[rank, ], 10L), row.names = FALSE)
cat("Complete results saved to", args[3], "\n")
