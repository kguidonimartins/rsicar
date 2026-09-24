skip_if_not_installed("sf")

test_that("the bundled municipality lookup is complete and tabular", {
  catalog <- rsicar:::sicar_municipality_lookup

  expect_identical(
    names(catalog),
    c("code_muni", "name_muni", "abbrev_state")
  )
  expect_identical(nrow(catalog), 5571L)
  expect_identical(length(unique(catalog$code_muni)), nrow(catalog))
  expect_true(all(!is.na(catalog$code_muni)))
  expect_true(all(nchar(catalog$code_muni) == 7L))
  expect_false("geometry" %in% names(catalog))
})

test_that("resolving municipality names does not download geometries", {
  calls <- 0L
  testthat::local_mocked_bindings(
    .sicar_download_municipalities = function() {
      calls <<- calls + 1L
      stop("geometry download should not be called", call. = FALSE)
    },
    .package = "rsicar"
  )

  expect_identical(
    rsicar::sicar_resolve_municipality("Recife"),
    c("Recife/PE" = "2611606")
  )
  expect_identical(calls, 0L)
})

test_that("municipality geometries are downloaded lazily and cached", {
  cache_dir <- withr::local_tempdir()
  calls <- 0L
  fixture <- sf::st_sf(
    code_muni = "0000001",
    name_muni = "Development Fixture",
    abbrev_state = "XX",
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(0, 0),
        c(1, 0),
        c(1, 1),
        c(0, 1),
        c(0, 0)
      ))),
      crs = 4674
    )
  )
  testthat::local_mocked_bindings(
    .sicar_municipality_cache_path = function() {
      file.path(cache_dir, "municipalities-2025.rds")
    },
    .sicar_download_municipalities = function() {
      calls <<- calls + 1L
      fixture
    },
    .package = "rsicar"
  )

  expect_identical(calls, 0L)
  first <- rsicar:::.sicar_municipality_geometries()
  expect_identical(calls, 1L)
  expect_s3_class(first, "sf")
  second <- rsicar:::.sicar_municipality_geometries()
  expect_identical(calls, 1L)
  expect_identical(second$code_muni, "0000001")
})

municipality_fixture <- function(code_muni = "2611606", crs = 4674) {
  sf::st_sf(
    code_muni = code_muni,
    name_muni = "Recife",
    abbrev_state = "PE",
    geometry = sf::st_sfc(
      rep(
        list(sf::st_polygon(list(rbind(
          c(0, 0),
          c(1, 0),
          c(1, 1),
          c(0, 1),
          c(0, 0)
        )))),
        length(code_muni)
      ),
      crs = crs
    )
  )
}

test_that("municipality geometries are validated and codes zero-padded", {
  result <- rsicar:::.sicar_validate_municipality_geometries(
    municipality_fixture(code_muni = 1100015)
  )

  expect_identical(result$code_muni, "1100015")
})

test_that("invalid municipality geometries are rejected", {
  validate <- rsicar:::.sicar_validate_municipality_geometries

  expect_error(
    validate(sf::st_drop_geometry(municipality_fixture())),
    "not an `sf` object",
    class = "rsicar_spatial_error"
  )
  error <- rlang::catch_cnd(validate(municipality_fixture()[, "code_muni"]))
  expect_s3_class(error, "rsicar_spatial_error")
  expect_identical(error$missing, c("name_muni", "abbrev_state"))
  expect_error(
    validate(municipality_fixture(crs = sf::NA_crs_)),
    "has no CRS",
    class = "rsicar_spatial_error"
  )
  expect_error(
    validate(municipality_fixture(code_muni = c("2611606", "2611606"))),
    "unique seven-digit",
    class = "rsicar_spatial_error"
  )
  expect_error(
    validate(municipality_fixture(code_muni = "12345678")),
    "unique seven-digit",
    class = "rsicar_spatial_error"
  )
})

test_that("the municipality cache lives in the user cache directory", {
  expect_identical(
    rsicar:::.sicar_municipality_cache_path(),
    file.path(
      tools::R_user_dir("rsicar", which = "cache"),
      "municipalities-2025.rds"
    )
  )
})

test_that("municipality geometries are downloaded from geobr", {
  skip_if_not_installed("geobr")
  arguments <- NULL
  testthat::local_mocked_bindings(
    read_municipality = function(...) {
      arguments <<- list(...)
      municipality_fixture(code_muni = 2611606)
    },
    .package = "geobr"
  )

  result <- suppressMessages(rsicar:::.sicar_download_municipalities())

  expect_identical(result$code_muni, "2611606")
  expect_identical(arguments$year, 2025)
  expect_false(arguments$simplified)
})

test_that("geobr download failures are classified", {
  skip_if_not_installed("geobr")
  testthat::local_mocked_bindings(
    read_municipality = function(...) stop("network unavailable"),
    .package = "geobr"
  )

  expect_error(
    suppressMessages(rsicar:::.sicar_download_municipalities()),
    "Could not download",
    class = "rsicar_spatial_error"
  )
})

test_that("an unreadable municipality cache is reported", {
  cache_path <- withr::local_tempfile(fileext = ".rds")
  writeLines("not an RDS file", cache_path)
  testthat::local_mocked_bindings(
    .sicar_municipality_cache_path = function() cache_path,
    .package = "rsicar"
  )

  error <- rlang::catch_cnd(rsicar:::.sicar_municipality_geometries())

  expect_s3_class(error, "rsicar_spatial_error")
  expect_identical(error$path, cache_path)
})

test_that("the municipality cache directory is created when needed", {
  cache_path <- file.path(withr::local_tempdir(), "nested", "cache.rds")
  testthat::local_mocked_bindings(
    .sicar_municipality_cache_path = function() cache_path,
    .sicar_download_municipalities = function() municipality_fixture(),
    .package = "rsicar"
  )

  rsicar:::.sicar_municipality_geometries()

  expect_true(file.exists(cache_path))
})

test_that("an uncreatable municipality cache directory is reported", {
  blocker <- withr::local_tempfile()
  writeLines("a file, not a directory", blocker)
  testthat::local_mocked_bindings(
    .sicar_municipality_cache_path = function() {
      file.path(blocker, "cache", "municipalities-2025.rds")
    },
    .sicar_download_municipalities = function() municipality_fixture(),
    .package = "rsicar"
  )

  expect_error(
    rsicar:::.sicar_municipality_geometries(),
    "cache directory",
    class = "rsicar_source_error"
  )
})
