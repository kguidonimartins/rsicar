.sicar_normalize_choice <- function(value, allowed, field, multiple = FALSE) {
  if (
    length(value) < 1L ||
      (!multiple && length(value) != 1L) ||
      anyNA(value) ||
      !is.character(value)
  ) {
    message <- if (multiple) {
      sprintf("`%s` must be one or more non-missing character values.", field)
    } else {
      sprintf("`%s` must be a single non-missing character value.", field)
    }
    .sicar_abort(
      message,
      "rsicar_invalid_argument",
      field = field,
      value = value
    )
  }

  normalized <- toupper(trimws(value))
  unknown <- unique(normalized[!normalized %in% allowed])
  if (length(unknown) > 0L) {
    .sicar_abort(
      sprintf(
        "Unknown %s %s.",
        field,
        paste0("`", unknown, "`", collapse = ", ")
      ),
      "rsicar_invalid_argument",
      field = field,
      value = value,
      allowed = allowed
    )
  }

  if (multiple) unique(normalized) else normalized
}

#' List the accepted Brazilian state abbreviations
#'
#' @returns A character vector with the 27 official state abbreviations.
#' @examples
#' sicar_states()
#' @export
sicar_states <- function() {
  .sicar_states
}

#' List the accepted SICAR polygon themes
#'
#' @returns A character vector with the accepted polygon theme codes.
#' @examples
#' sicar_polygon_types()
#' @export
sicar_polygon_types <- function() {
  .sicar_polygons
}

.sicar_validate_state <- function(state, multiple = FALSE) {
  .sicar_normalize_choice(state, .sicar_states, "state", multiple = multiple)
}

.sicar_validate_polygon <- function(polygon, multiple = FALSE) {
  .sicar_normalize_choice(
    polygon,
    .sicar_polygons,
    "polygon",
    multiple = multiple
  )
}
