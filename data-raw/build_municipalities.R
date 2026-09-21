# Build the bundled municipality geometry catalog used by
# `sicar_resolve_municipality()` and `sicar_extract_municipality()`.
#
# Source: geobr 2.0.1, `read_municipality(year = 2025,
# simplified = FALSE)`. This script is run when the bundled reference data is
# intentionally refreshed; package users do not need geobr at runtime.

municipalities <- geobr::read_municipality(
  year = 2025,
  simplified = FALSE,
  output = "sf",
  showProgress = FALSE,
  verbose = FALSE
)

if (!inherits(municipalities, "sf")) {
  stop("geobr did not return an sf object.", call. = FALSE)
}

required <- c("code_muni", "name_muni", "abbrev_state")
missing <- setdiff(required, names(municipalities))
if (length(missing) > 0L) {
  stop(
    "The geobr municipality data is missing required columns: ",
    paste(missing, collapse = ", "),
    call. = FALSE
  )
}

if (is.null(sf::st_crs(municipalities))) {
  stop("The geobr municipality data has no CRS.", call. = FALSE)
}

sicar_municipalities <- municipalities[required]
sicar_municipalities$code_muni <- sprintf(
  "%07.0f",
  as.numeric(sicar_municipalities$code_muni)
)

if (
  anyNA(sicar_municipalities$code_muni) ||
    any(nchar(sicar_municipalities$code_muni) != 7L) ||
    anyDuplicated(sicar_municipalities$code_muni)
) {
  stop(
    "The geobr municipality codes are not unique seven-digit values.",
    call. = FALSE
  )
}

save(
  sicar_municipalities,
  file = file.path("R", "sysdata.rda"),
  compress = "xz"
)
