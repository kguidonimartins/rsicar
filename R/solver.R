.sicar_solver <- function(solve, name) {
  structure(list(solve = solve, name = name), class = "sicar_solver")
}

.sicar_normalize_solver_output <- function(value) {
  if (length(value) != 1L || is.na(value) || !is.character(value)) {
    .sicar_abort(
      "A CAPTCHA solver must return one non-missing character value.",
      "rsicar_solver_error",
      retryable = TRUE
    )
  }
  # SICAR CAPTCHAs are case-sensitive; only whitespace is stripped here.
  # Do not uppercase, or correctly-read CAPTCHAs will be rejected by the
  # service.
  value <- trimws(value)
  if (!grepl("^[A-Za-z0-9]{5}$", value)) {
    .sicar_abort(
      "A CAPTCHA solver must return exactly five alphanumeric characters.",
      "rsicar_solver_error",
      value = value,
      retryable = TRUE
    )
  }
  value
}

.sicar_solve <- function(solver, path) {
  .sicar_normalize_solver_output(solver$solve(path))
}

#' Create a CAPTCHA solver from an R function
#'
#' @param fn A function accepting a path to a CAPTCHA image and returning its
#'   five-character answer.
#' @returns An object usable as the `solver` argument of `sicar_client()`.
#' @examples
#' solver <- sicar_solver_function(function(path) "AB12c")
#' solver$name
#' @export
sicar_solver_function <- function(fn) {
  if (!is.function(fn)) {
    .sicar_abort(
      "`fn` must be a function.",
      "rsicar_invalid_argument",
      field = "fn",
      value = fn
    )
  }
  .sicar_solver(fn, "function")
}
