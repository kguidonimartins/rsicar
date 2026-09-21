skip_if_not_installed("sf")

make_source_zip <- function(data, directory, name = "source.zip") {
  layer_dir <- file.path(
    directory,
    paste0("layer-", tools::file_path_sans_ext(name))
  )
  dir.create(layer_dir)
  shapefile <- file.path(layer_dir, "sicar.shp")
  sf::st_write(data, shapefile, quiet = TRUE, delete_layer = TRUE)
  archive <- file.path(directory, name)
  utils::zip(
    archive,
    files = list.files(layer_dir, full.names = TRUE),
    flags = "-qj"
  )
  archive
}

recife_bbox <- function() {
  municipality <- rsicar:::sicar_municipalities[
    rsicar:::sicar_municipalities$code_muni == "2611606",
    ,
    drop = FALSE
  ]
  sf::st_bbox(municipality)
}

test_that("extraction preserves complete intersecting geometries", {
  bbox <- recife_bbox()
  crossing <- sf::st_as_sfc(bbox)
  outside <- sf::st_polygon(list(rbind(
    c(-10, -10),
    c(-9, -10),
    c(-9, -9),
    c(-10, -9),
    c(-10, -10)
  )))
  source <- sf::st_sf(
    id = c("crossing", "outside"),
    geometry = sf::st_sfc(crossing[[1]], outside, crs = 4674)
  )
  root <- withr::local_tempdir()
  archive <- make_source_zip(source, root)

  result <- sicar_extract_municipality("Recife", archive)

  expect_s3_class(result, "sf")
  expect_identical(result$id, "crossing")
  expect_length(sf::st_equals(result, source[1, ])[[1]], 1L)
  expect_identical(sf::st_crs(result)$epsg, 4674L)
})

test_that("boundary contact is included by st_intersects", {
  bbox <- recife_bbox()
  touching <- sf::st_polygon(list(rbind(
    c(bbox[["xmin"]] - 1, bbox[["ymin"]]),
    c(bbox[["xmin"]], bbox[["ymin"]]),
    c(bbox[["xmin"]], bbox[["ymax"]]),
    c(bbox[["xmin"]] - 1, bbox[["ymax"]]),
    c(bbox[["xmin"]] - 1, bbox[["ymin"]])
  )))
  source <- sf::st_sf(
    id = "boundary",
    geometry = sf::st_sfc(touching, crs = 4674)
  )
  archive <- make_source_zip(source, withr::local_tempdir())

  result <- sicar_extract_municipality("Recife", archive)

  expect_identical(result$id, "boundary")
})

test_that("empty selections retain the source schema and CRS", {
  source <- sf::st_sf(
    id = "outside",
    label = "not selected",
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(-10, -10),
        c(-9, -10),
        c(-9, -9),
        c(-10, -9),
        c(-10, -10)
      ))),
      crs = 4674
    )
  )
  archive <- make_source_zip(source, withr::local_tempdir())

  result <- sicar_extract_municipality("Recife", archive)

  expect_s3_class(result, "sf")
  expect_identical(nrow(result), 0L)
  expect_identical(names(result), names(source))
  expect_identical(sf::st_crs(result)$epsg, 4674L)
})

test_that("municipality CRS is transformed to the source CRS", {
  bbox <- recife_bbox()
  source <- sf::st_sf(
    id = "crossing",
    geometry = sf::st_transform(sf::st_as_sfc(bbox), 4326)
  )
  archive <- make_source_zip(source, withr::local_tempdir())

  result <- sicar_extract_municipality("Recife", archive)

  expect_identical(sf::st_crs(result)$epsg, 4326L)
  expect_identical(result$id, "crossing")
})

test_that("multiple source ZIPs and municipalities are combined once", {
  first_bbox <- recife_bbox()
  second <- rsicar:::sicar_municipalities[
    rsicar:::sicar_municipalities$code_muni == "2609600",
    ,
    drop = FALSE
  ]
  second_bbox <- sf::st_bbox(second)
  combined <- c(
    xmin = min(first_bbox[["xmin"]], second_bbox[["xmin"]]),
    ymin = min(first_bbox[["ymin"]], second_bbox[["ymin"]]),
    xmax = max(first_bbox[["xmax"]], second_bbox[["xmax"]]),
    ymax = max(first_bbox[["ymax"]], second_bbox[["ymax"]])
  )
  class(combined) <- "bbox"
  attr(combined, "crs") <- sf::st_crs(4674)
  source <- sf::st_sf(
    id = "shared",
    geometry = sf::st_as_sfc(combined)
  )
  root <- withr::local_tempdir()
  make_source_zip(source, root, "first.zip")
  make_source_zip(source, root, "second.zip")

  result <- sicar_extract_municipality(c("Recife", "Olinda"), root)

  expect_identical(nrow(result), 2L)
  expect_identical(result$id, c("shared", "shared"))
})

test_that("source archives without shapefiles are rejected", {
  root <- withr::local_tempdir()
  text_path <- file.path(root, "source.txt")
  writeLines("fixture", text_path)
  archive <- file.path(root, "source.zip")
  utils::zip(archive, text_path, flags = "-qj")

  expect_snapshot(
    error = TRUE,
    sicar_extract_municipality("Recife", archive)
  )
})
