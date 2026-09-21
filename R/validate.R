.sicar_normalize_choice <- function(value, allowed, field) {
  if (length(value) != 1L || is.na(value) || !is.character(value)) {
    .sicar_abort(
      sprintf("`%s` must be a single non-missing character value.", field),
      "rsicar_invalid_argument",
      field = field,
      value = value
    )
  }

  normalized <- toupper(trimws(value))
  if (!normalized %in% allowed) {
    .sicar_abort(
      sprintf("Unknown %s `%s`.", field, value),
      "rsicar_invalid_argument",
      field = field,
      value = value,
      allowed = allowed
    )
  }

  normalized
}

#' List the accepted Brazilian state abbreviations
#'
#' @returns A character vector with the 27 official state abbreviations.
#' @export
sicar_states <- function() {
  .sicar_states
}

#' List the accepted SICAR polygon themes
#'
#' @returns A character vector with the accepted polygon theme codes.
#' @export
sicar_polygon_types <- function() {
  .sicar_polygons
}

.sicar_validate_state <- function(state) {
  .sicar_normalize_choice(state, .sicar_states, "state")
}

.sicar_validate_polygon <- function(polygon) {
  .sicar_normalize_choice(polygon, .sicar_polygons, "polygon")
}
