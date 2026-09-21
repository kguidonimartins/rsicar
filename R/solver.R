.sicar_solver <- function(solve, name) {
  structure(list(solve = solve, name = name), class = "sicar_solver")
}

.sicar_normalize_solver_output <- function(value) {
  if (length(value) != 1L || is.na(value) || !is.character(value)) {
    .sicar_abort(
      "A CAPTCHA solver must return one non-missing character value.",
      "rscicar_solver_error"
    )
  }
  value <- toupper(trimws(value))
  if (!grepl("^[A-Z0-9]{5}$", value)) {
    .sicar_abort(
      "A CAPTCHA solver must return exactly five alphanumeric characters.",
      "rscicar_solver_error",
      value = value
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
#' @export
sicar_solver_function <- function(fn) {
  if (!is.function(fn)) {
    .sicar_abort(
      "`fn` must be a function.",
      "rscicar_invalid_argument",
      field = "fn",
      value = fn
    )
  }
  .sicar_solver(fn, "function")
}
