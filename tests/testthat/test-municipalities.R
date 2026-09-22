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
