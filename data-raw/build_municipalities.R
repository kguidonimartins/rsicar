# Build the bundled municipality lookup used by
# `sicar_resolve_municipality()`. Full municipality geometries are downloaded
# lazily by `sicar_extract_municipality()` and are not bundled in the package.
#
# Source: geobr 2.0.1, `read_municipality(year = 2025,
# simplified = FALSE)`. This script is run when the bundled lookup is
# intentionally refreshed; package users need geobr only for extraction.

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

municipality_lookup <- data.frame(
  code_muni = sprintf("%07.0f", as.numeric(municipalities$code_muni)),
  name_muni = as.character(municipalities$name_muni),
  abbrev_state = as.character(municipalities$abbrev_state),
  stringsAsFactors = FALSE
)

if (
  anyNA(municipality_lookup$code_muni) ||
    any(nchar(municipality_lookup$code_muni) != 7L) ||
    anyDuplicated(municipality_lookup$code_muni)
) {
  stop(
    "The geobr municipality codes are not unique seven-digit values.",
    call. = FALSE
  )
}

sicar_municipality_lookup <- municipality_lookup
save(
  sicar_municipality_lookup,
  file = file.path("R", "sysdata.rda"),
  compress = "xz"
)
