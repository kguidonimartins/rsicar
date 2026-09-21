#' Create a manual CAPTCHA solver
#'
#' Prompts the user to type the CAPTCHA shown at the given image path.
#' Requires an interactive session.
#'
#' @returns An object usable as the `solver` argument of `sicar_client()`.
#' @examples
#' solver <- sicar_solver_manual()
#' solver$name
#' @export
sicar_solver_manual <- function() {
  .sicar_solver(
    function(path) {
      if (!interactive()) {
        .sicar_abort(
          "The manual CAPTCHA solver requires an interactive session.",
          "rsicar_solver_error",
          path = path,
          retryable = FALSE
        )
      }
      answer <- readline(sprintf("Enter the CAPTCHA for %s: ", path))
      .sicar_normalize_solver_output(answer)
    },
    "manual"
  )
}
