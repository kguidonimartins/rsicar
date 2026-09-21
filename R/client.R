#' Create an rsicar client
#'
#' The client stores configuration only. It does not access the SICAR service
#' until an operation such as `sicar_release_dates()` is called.
#'
#' @param solver A CAPTCHA solver created by one of the `sicar_solver_*()`
#'   functions. Defaults to a manual solver.
#' @param headers Optional named character vector of additional HTTP headers.
#' @param timeout Connection and transfer timeout in seconds.
#' @returns An object of class `sicar_client`.
#' @export
sicar_client <- function(
  solver = sicar_solver_manual(),
  headers = character(),
  timeout = 60
) {
  if (!inherits(solver, "sicar_solver")) {
    .sicar_abort(
      "`solver` must be created by a `sicar_solver_*()` function.",
      "rscicar_invalid_argument",
      field = "solver",
      value = solver
    )
  }
  if (
    !is.character(headers) ||
      (length(headers) > 0L &&
        (is.null(names(headers)) || any(!nzchar(names(headers)))))
  ) {
    .sicar_abort(
      "`headers` must be a named character vector.",
      "rscicar_invalid_argument",
      field = "headers",
      value = headers
    )
  }
  if (
    length(timeout) != 1L ||
      !is.numeric(timeout) ||
      is.na(timeout) ||
      timeout <= 0
  ) {
    .sicar_abort(
      "`timeout` must be a positive number.",
      "rscicar_invalid_argument",
      field = "timeout",
      value = timeout
    )
  }

  state <- new.env(parent = emptyenv())
  state$cookie_jar <- tempfile("rsicar-cookies-", fileext = ".txt")
  state$bootstrapped <- FALSE
  reg.finalizer(
    state,
    function(environment) unlink(environment$cookie_jar),
    onexit = TRUE
  )

  structure(
    list(
      solver = solver,
      headers = headers,
      timeout = timeout,
      urls = .sicar_urls,
      state = state
    ),
    class = "sicar_client"
  )
}
