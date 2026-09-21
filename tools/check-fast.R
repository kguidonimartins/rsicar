package_path <- normalizePath(".", mustWork = TRUE)
temporary_path <- tempfile("rsicar-check-fast-")
dir.create(temporary_path, recursive = TRUE)
on.exit(unlink(temporary_path, recursive = TRUE, force = TRUE), add = TRUE)

items <- list.files(package_path, all.files = TRUE, no.. = TRUE)
items <- setdiff(items, c(".git", "R/sysdata.rda"))
for (item in items) {
  file.copy(
    file.path(package_path, item),
    temporary_path,
    recursive = TRUE,
    copy.date = TRUE
  )
}

if (!requireNamespace("sf", quietly = TRUE)) {
  stop("Install the 'sf' package to run check-fast.", call. = FALSE)
}

sicar_municipalities <- sf::st_sf(
  code_muni = "0000001",
  name_muni = "Development Fixture",
  abbrev_state = "XX",
  geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4674)
)
save(
  sicar_municipalities,
  file = file.path(temporary_path, "R", "sysdata.rda"),
  compress = "xz"
)

devtools::check(
  pkg = temporary_path,
  document = FALSE,
  vignettes = FALSE,
  cran = FALSE,
  args = c(
    "--no-tests",
    "--no-examples",
    "--no-vignettes",
    "--no-manual"
  ),
  error_on = "error"
)
