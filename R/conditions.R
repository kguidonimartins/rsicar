.sicar_abort <- function(message, class, ...) {
  rlang::abort(
    message,
    class = c(class, "rscicar_error"),
    ...
  )
}

.sicar_warn <- function(message, class, ...) {
  rlang::warn(
    message,
    class = c(class, "rscicar_warning"),
    ...
  )
}
