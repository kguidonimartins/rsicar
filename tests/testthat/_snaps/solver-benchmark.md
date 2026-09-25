# duplicate image content cannot contaminate development and evaluation

    Code
      rsicar:::.sicar_captcha_manifest(manifest)
    Condition
      Error in `.sicar_abort()`:
      ! Corpus images must be readable and unique, including across splits.

# tuning never reads evaluation or unlabeled images

    Code
      rsicar:::.sicar_benchmark_run(manifest, file.path(directory, "evaluation"),
      "evaluate", file.path(output, "frozen-config.json"))
    Condition
      Error in `.sicar_abort()`:
      ! Evaluation images overlap the tuning corpus.

# an empty label set cannot be scored as perfect accuracy

    Code
      rsicar:::.sicar_benchmark_run(manifest, file.path(directory, "results"),
      "evaluate")
    Condition
      Error in `.sicar_abort()`:
      ! No visually labeled images in the evaluation split.
