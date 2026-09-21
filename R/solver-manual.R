#' Create a manual CAPTCHA solver
#'
#' @returns An object usable as the `solver` argument of `sicar_client()`.
#' @export
sicar_solver_manual <- function() {
  .sicar_solver(
    function(path) {
      if (!interactive()) {
        .sicar_abort(
          "The manual CAPTCHA solver requires an interactive session.",
          "rscicar_solver_error",
          path = path
        )
      }
      answer <- readline(sprintf("Enter the CAPTCHA for %s: ", path))
      .sicar_normalize_solver_output(answer)
    },
    "manual"
  )
}
