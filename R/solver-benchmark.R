.sicar_captcha_manifest <- function(path) {
  data <- utils::read.csv(path, colClasses = "character", na.strings = "")
  required <- c("id", "path", "expected", "split", "protect")
  if (!all(required %in% names(data)) || nrow(data) == 0L) {
    .sicar_abort(
      "The corpus CSV must contain rows with id, path, expected, split and protect columns.",
      "rsicar_benchmark_error"
    )
  }
  data$expected[is.na(data$expected)] <- ""
  if (
    anyNA(data[c("id", "path", "split", "protect")]) ||
      any(!nzchar(data$id)) ||
      any(!nzchar(data$path)) ||
      anyDuplicated(data$id) ||
      any(!data$split %in% c("development", "evaluation")) ||
      any(!tolower(data$protect) %in% c("true", "false")) ||
      any(nzchar(data$expected) & !grepl("^[A-Za-z0-9]{5}$", data$expected))
  ) {
    .sicar_abort(
      "Corpus IDs must be unique, splits development/evaluation, protect TRUE/FALSE, and labels empty or five alphanumeric characters.",
      "rsicar_benchmark_error"
    )
  }
  data$protect <- tolower(data$protect) == "true"
  paths <- ifelse(
    grepl("^(/|[A-Za-z]:)", data$path),
    data$path,
    file.path(dirname(path), data$path)
  )
  if (any(!file.exists(paths))) {
    .sicar_abort("Some corpus images are missing.", "rsicar_benchmark_error")
  }
  data$path <- normalizePath(paths, mustWork = TRUE)
  data$md5 <- unname(tools::md5sum(data$path))
  if (anyNA(data$md5) || anyDuplicated(data$md5)) {
    .sicar_abort(
      "Corpus images must be readable and unique, including across splits.",
      "rsicar_benchmark_error"
    )
  }
  data
}

.sicar_benchmark_config <- function(
  psm = 7L,
  dictionaries = TRUE,
  border = 0L,
  margin = 30
) {
  list(psm = psm, dictionaries = dictionaries, border = border, margin = margin)
}

.sicar_benchmark_downloads <- function(path) {
  data <- utils::read.csv(path, colClasses = "character")
  if (!all(c("id", "attempts", "success") %in% names(data)) || !nrow(data)) {
    .sicar_abort(
      "Download CSV must contain id, attempts and success rows.",
      "rsicar_benchmark_error"
    )
  }
  attempts <- suppressWarnings(as.numeric(data$attempts))
  if (
    anyNA(data$id) ||
      any(!nzchar(data$id)) ||
      anyDuplicated(data$id) ||
      any(!is.finite(attempts) | attempts < 1 | attempts != floor(attempts)) ||
      any(!tolower(data$success) %in% c("true", "false"))
  ) {
    .sicar_abort(
      "Downloads need unique IDs, positive integer attempts and TRUE/FALSE success.",
      "rsicar_benchmark_error"
    )
  }
  success <- tolower(data$success) == "true"
  data.frame(
    downloads = nrow(data),
    successes = sum(success),
    success_first_attempt = mean(success & attempts == 1),
    success_within_3 = mean(success & attempts <= 3),
    success_within_5 = mean(success & attempts <= 5),
    mean_attempts_all = mean(attempts)
  )
}

.sicar_benchmark_candidates <- function(data, config) {
  engine <- .sicar_tesseract_engine(config$psm, config$dictionaries)
  rows <- lapply(seq_len(nrow(data)), function(i) {
    candidates <- .sicar_tesseract_candidates(
      data$path[i],
      engine,
      config$border
    )
    cbind(id = data$id[i], candidates)
  })
  do.call(rbind, rows)
}

.sicar_benchmark_predictions <- function(data, candidates, margin) {
  rows <- lapply(seq_len(nrow(data)), function(i) {
    readings <- candidates[candidates$id == data$id[i], , drop = FALSE]
    choice <- .sicar_tesseract_select(readings, margin)
    answer <- readings$value[choice$index]
    oracle <- any(readings$value == data$expected[i])
    data.frame(
      id = data$id[i],
      expected = data$expected[i],
      answer = answer,
      correct = identical(answer, data$expected[i]),
      valid = readings$valid[choice$index],
      oracle_correct = oracle,
      selection_missed = oracle && !identical(answer, data$expected[i]),
      selection_reason = choice$reason,
      elapsed_seconds = sum(readings$elapsed_seconds)
    )
  })
  do.call(rbind, rows)
}

.sicar_benchmark_summary <- function(predictions, protected) {
  data.frame(
    images = nrow(predictions),
    correct = sum(predictions$correct),
    accuracy = mean(predictions$correct),
    valid_rate = mean(predictions$valid),
    oracle_correct = sum(predictions$oracle_correct),
    selection_missed = sum(predictions$selection_missed),
    protected_failures = sum(protected & !predictions$correct),
    mean_seconds = mean(predictions$elapsed_seconds),
    median_seconds = stats::median(predictions$elapsed_seconds)
  )
}

.sicar_benchmark_run <- function(
  manifest,
  output,
  mode = "tune",
  frozen = NULL
) {
  .sicar_tesseract_requirements()
  corpus <- .sicar_captcha_manifest(manifest)
  split <- if (identical(mode, "tune")) "development" else "evaluation"
  data <- corpus[
    corpus$split == split & nzchar(corpus$expected),
    ,
    drop = FALSE
  ]
  if (!nrow(data)) {
    .sicar_abort(
      sprintf("No visually labeled images in the %s split.", split),
      "rsicar_benchmark_error"
    )
  }
  if (
    dir.exists(output) &&
      length(list.files(output, all.files = TRUE, no.. = TRUE))
  ) {
    .sicar_abort(
      "Use an empty benchmark output directory.",
      "rsicar_benchmark_error"
    )
  }
  environment <- .sicar_tesseract_environment()
  default <- .sicar_benchmark_config()
  if (identical(mode, "tune")) {
    grid <- expand.grid(
      psm = c(7L, 8L, 13L),
      dictionaries = c(TRUE, FALSE),
      border = c(0L, 10L)
    )
    margins <- c(0, 10, 20, 30, 40, 50, 101)
    baseline_candidates <- .sicar_benchmark_candidates(data, default)
    baseline <- .sicar_benchmark_predictions(
      data,
      baseline_candidates,
      default$margin
    )
    protected <- data$protect | baseline$correct
  } else {
    if (!identical(mode, "evaluate") || is.null(frozen)) {
      .sicar_abort(
        "Use tune or evaluate with a frozen configuration.",
        "rsicar_benchmark_error"
      )
    }
    lock <- jsonlite::read_json(frozen, simplifyVector = TRUE)
    config <- lock$configuration
    if (
      !is.list(config) ||
        !all(names(default) %in% names(config)) ||
        length(config$psm) != 1L ||
        !config$psm %in% c(7L, 8L, 13L) ||
        !is.logical(config$dictionaries) ||
        length(config$dictionaries) != 1L ||
        is.na(config$dictionaries) ||
        length(config$border) != 1L ||
        !config$border %in% c(0L, 10L) ||
        length(config$margin) != 1L ||
        !is.numeric(config$margin) ||
        !is.finite(config$margin) ||
        config$margin < 0 ||
        is.null(lock$development_images_md5)
    ) {
      .sicar_abort(
        "Invalid frozen benchmark configuration.",
        "rsicar_benchmark_error"
      )
    }
    if (any(data$md5 %in% lock$development_images_md5)) {
      .sicar_abort(
        "Evaluation images overlap the tuning corpus.",
        "rsicar_benchmark_error"
      )
    }
    grid <- as.data.frame(config[c("psm", "dictionaries", "border")])
    margins <- config$margin
    protected <- data$protect
  }
  summaries <- list()
  predictions <- list()
  readings <- list()
  configs <- list()
  for (i in seq_len(nrow(grid))) {
    config <- as.list(grid[i, ])
    cat(sprintf("OCR configuration %d/%d (%s)\n", i, nrow(grid), split))
    candidates <- if (identical(mode, "tune") && i == 1L) {
      baseline_candidates
    } else {
      .sicar_benchmark_candidates(data, config)
    }
    readings[[i]] <- cbind(
      ocr_configuration = i,
      as.data.frame(config),
      candidates
    )
    for (margin in margins) {
      config$margin <- margin
      key <- length(configs) + 1L
      configs[[key]] <- config
      result <- .sicar_benchmark_predictions(data, candidates, margin)
      predictions[[key]] <- cbind(
        configuration = key,
        ocr_configuration = i,
        result
      )
      summaries[[key]] <- cbind(
        configuration = key,
        ocr_configuration = i,
        as.data.frame(config),
        .sicar_benchmark_summary(result, protected)
      )
    }
  }
  summary <- do.call(rbind, summaries)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    do.call(rbind, readings),
    file.path(output, "candidates.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    do.call(rbind, predictions),
    file.path(output, "predictions.csv"),
    row.names = FALSE
  )
  utils::write.csv(summary, file.path(output, "summary.csv"), row.names = FALSE)
  jsonlite::write_json(
    list(
      environment = environment,
      split = split,
      scored = nrow(data),
      unlabeled = sum(corpus$split == split & !nzchar(corpus$expected)),
      images = data[c("id", "md5")],
      generated_at = .sicar_now_iso8601()
    ),
    file.path(output, "environment.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  if (identical(mode, "evaluate")) {
    file.copy(
      frozen,
      file.path(output, "frozen-config.json"),
      overwrite = FALSE
    )
  }
  if (identical(mode, "tune")) {
    eligible <- which(summary$protected_failures == 0L)
    if (length(eligible)) {
      changes <- with(
        summary,
        (psm != 7L) + (!dictionaries) + (border != 0L) + (margin != 30)
      )
      rank <- order(
        -summary$correct[eligible],
        changes[eligible],
        summary$configuration[eligible]
      )
      best <- eligible[rank[1L]]
      jsonlite::write_json(
        list(
          configuration = configs[[best]],
          development_images_md5 = data$md5,
          environment = environment,
          summary = summary[best, ]
        ),
        file.path(output, "frozen-config.json"),
        auto_unbox = TRUE,
        pretty = TRUE
      )
    }
  }
  invisible(summary)
}
