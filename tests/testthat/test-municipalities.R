test_that("the bundled municipality catalog is complete and spatial", {
  catalog <- rsicar:::sicar_municipalities

  expect_s3_class(catalog, "sf")
  expect_identical(
    names(catalog),
    c("code_muni", "name_muni", "abbrev_state", "geometry")
  )
  expect_identical(nrow(catalog), 5571L)
  expect_identical(length(unique(catalog$code_muni)), nrow(catalog))
  expect_true(all(!is.na(catalog$code_muni)))
  expect_true(all(nchar(catalog$code_muni) == 7L))
  expect_identical(sf::st_crs(catalog)$epsg, 4674L)
})
