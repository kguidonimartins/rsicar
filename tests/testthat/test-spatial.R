skip_if_not_installed("sf")

make_source_zip <- function(
  data,
  directory,
  name = "source.zip",
  layer_name = "sicar",
  remove_prj = FALSE
) {
  layer_dir <- file.path(
    directory,
    paste0("layer-", tools::file_path_sans_ext(name))
  )
  dir.create(layer_dir)
  shapefile <- file.path(layer_dir, paste0(layer_name, ".shp"))
  sf::st_write(data, shapefile, quiet = TRUE, delete_layer = TRUE)
  if (remove_prj) {
    file.remove(file.path(layer_dir, paste0(layer_name, ".prj")))
  }
  archive <- file.path(directory, name)
  utils::zip(
    archive,
    files = list.files(layer_dir, full.names = TRUE),
    flags = "-qj"
  )
  archive
}

test_municipality_geometries <- function() {
  square <- function(xmin, xmax) {
    sf::st_polygon(list(rbind(
      c(xmin, 0),
      c(xmax, 0),
      c(xmax, 1),
      c(xmin, 1),
      c(xmin, 0)
    )))
  }
  sf::st_sf(
    code_muni = c("2611606", "2609600"),
    name_muni = c("Recife", "Olinda"),
    abbrev_state = c("PE", "PE"),
    geometry = sf::st_sfc(square(0, 1), square(1, 2), crs = 4674)
  )
}

recife_bbox <- function() {
  municipality <- test_municipality_geometries()[
    test_municipality_geometries()$code_muni == "2611606",
    ,
    drop = FALSE
  ]
  sf::st_bbox(municipality)
}

test_that("extraction preserves complete intersecting geometries", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
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
  archive <- make_source_zip(source, root, "PE_APPS.zip")

  result <- sicar_extract_municipality("Recife", archive)

  expect_s3_class(result, "sf")
  expect_identical(result$id, "crossing")
  expect_identical(names(result)[1:2], c("filepath", "tema"))
  expect_identical(result$filepath, normalizePath(archive))
  expect_identical(file.exists(result$filepath), TRUE)
  expect_identical(result$tema, "APPS")
  expect_length(sf::st_equals(result, source[1, ])[[1]], 1L)
  expect_identical(sf::st_crs(result)$epsg, 4674L)
})

test_that("boundary contact is included by st_intersects", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
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
  expect_identical(result$tema, NA_character_)
})

test_that("empty selections retain the source schema and CRS", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
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
  expect_identical(
    names(result),
    c("filepath", "tema", "id", "label", "geometry")
  )
  expect_identical(result$filepath, character(0))
  expect_identical(result$tema, character(0))
  expect_identical(sf::st_crs(result)$epsg, 4674L)
})

test_that("municipality CRS is transformed to the source CRS", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
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
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
  first_bbox <- recife_bbox()
  second <- test_municipality_geometries()[
    test_municipality_geometries()$code_muni == "2609600",
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
  make_source_zip(source, root, "PE_APPS.zip", layer_name = "APPS_1")
  make_source_zip(
    source,
    root,
    "second.zip",
    layer_name = "AREA_IMOVEL_1"
  )

  result <- sicar_extract_municipality(c("Recife", "Olinda"), root)

  expect_identical(nrow(result), 2L)
  expect_identical(result$id, c("shared", "shared"))
  expect_identical(
    result$filepath,
    normalizePath(file.path(root, c("PE_APPS.zip", "second.zip")))
  )
  expect_identical(result$tema, c("APPS", "AREA_IMOVEL"))
})

test_that("reading a source ZIP skips features outside the AOI bbox", {
  bbox <- recife_bbox()
  inside <- sf::st_as_sfc(bbox)[[1]]
  outside <- sf::st_polygon(list(rbind(
    c(-10, -10),
    c(-9, -10),
    c(-9, -9),
    c(-10, -9),
    c(-10, -10)
  )))
  source <- sf::st_sf(
    id = c("inside", "outside"),
    geometry = sf::st_sfc(inside, outside, crs = 4674)
  )
  archive <- make_source_zip(source, withr::local_tempdir())

  layers <- rsicar:::.sicar_read_source_zip(archive, aoi = sf::st_as_sfc(bbox))

  expect_identical(layers[[1]]$id, "inside")
})

test_that(".sicar_aoi_wkt_filter() skips filtering without an AOI or CRS", {
  expect_identical(
    rsicar:::.sicar_aoi_wkt_filter("does-not-matter.shp", NULL),
    character(0)
  )

  no_prj_dir <- withr::local_tempdir()
  no_prj_path <- file.path(no_prj_dir, "sicar.shp")
  sf::st_write(
    sf::st_sf(
      id = "x",
      geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4674)
    ),
    no_prj_path,
    quiet = TRUE
  )
  file.remove(file.path(no_prj_dir, "sicar.prj"))
  aoi <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 0, ymin = 0, xmax = 1, ymax = 1),
    crs = 4674
  ))

  expect_identical(
    rsicar:::.sicar_aoi_wkt_filter(no_prj_path, aoi),
    character(0)
  )
})

test_that("source archives without shapefiles are rejected", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
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

test_that("source shapefiles without a CRS are rejected", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
  source <- sf::st_sf(
    id = "missing-crs",
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4674)
  )
  archive <- make_source_zip(
    source,
    withr::local_tempdir(),
    remove_prj = TRUE
  )

  expect_snapshot(
    error = TRUE,
    sicar_extract_municipality("Recife", archive)
  )
})

test_that("invalid source geometries are repaired with st_make_valid()", {
  testthat::local_mocked_bindings(
    .sicar_municipality_geometries = test_municipality_geometries,
    .package = "rsicar"
  )
  bbox <- recife_bbox()
  # A bowtie polygon crossing the Recife bounding box: self-intersecting, so
  # invalid, but repairable by `sf::st_make_valid()` without losing the part
  # that intersects Recife.
  invalid <- sf::st_polygon(list(rbind(
    c(bbox[["xmin"]], bbox[["ymin"]]),
    c(bbox[["xmax"]], bbox[["ymax"]]),
    c(bbox[["xmax"]], bbox[["ymin"]]),
    c(bbox[["xmin"]], bbox[["ymax"]]),
    c(bbox[["xmin"]], bbox[["ymin"]])
  )))
  expect_false(sf::st_is_valid(invalid))
  source <- sf::st_sf(
    id = "invalid",
    geometry = sf::st_sfc(invalid, crs = 4674)
  )
  archive <- make_source_zip(source, withr::local_tempdir())

  expect_snapshot(result <- sicar_extract_municipality("Recife", archive))

  expect_s3_class(result, "sf")
  expect_identical(result$id, "invalid")
  expect_true(all(sf::st_is_valid(result)))
})

unit_square <- function(offset = 0) {
  sf::st_polygon(list(rbind(
    c(offset, 0),
    c(offset + 1, 0),
    c(offset + 1, 1),
    c(offset, 1),
    c(offset, 0)
  )))
}

bowtie <- function() {
  sf::st_polygon(list(rbind(c(0, 0), c(1, 1), c(1, 0), c(0, 1), c(0, 0))))
}

test_that("planar invalid geometries are repaired without disabling s2", {
  source <- sf::st_sf(id = 1, geometry = sf::st_sfc(bowtie(), crs = 3857))

  repaired <- rsicar:::.sicar_make_valid(source)

  expect_true(all(sf::st_is_valid(repaired)))
})

test_that("geometry repair failures are classified", {
  source <- sf::st_sf(id = 1, geometry = sf::st_sfc(bowtie(), crs = 4674))
  testthat::local_mocked_bindings(
    .sicar_make_valid = function(source) stop("GEOS exception"),
    .package = "rsicar"
  )

  error <- rlang::catch_cnd(
    rsicar:::.sicar_repair_invalid_geometries(source, "src.zip", "layer.shp")
  )

  expect_s3_class(error, "rsicar_spatial_error")
  expect_identical(error$path, "src.zip")
  expect_identical(error$layer, "layer.shp")
})

test_that("geometries that remain invalid after repair are rejected", {
  source <- sf::st_sf(id = 1, geometry = sf::st_sfc(bowtie(), crs = 4674))
  testthat::local_mocked_bindings(
    .sicar_make_valid = function(source) source,
    .package = "rsicar"
  )

  error <- rlang::catch_cnd(
    rsicar:::.sicar_repair_invalid_geometries(source, "src.zip", "layer.shp")
  )

  expect_s3_class(error, "rsicar_spatial_error")
  expect_identical(error$n_unrepaired, 1L)
})

test_that("an empty municipality selection has no AOI", {
  municipalities <- test_municipality_geometries()[0, ]

  expect_null(rsicar:::.sicar_aoi_bbox(municipalities))
})

test_that(".sicar_aoi_wkt_filter() skips filtering when the AOI cannot be transformed", {
  directory <- withr::local_tempdir()
  path <- file.path(directory, "sicar.shp")
  sf::st_write(
    sf::st_sf(id = "x", geometry = sf::st_sfc(unit_square(), crs = 4674)),
    path,
    quiet = TRUE
  )
  aoi_without_crs <- sf::st_sfc(unit_square())

  expect_identical(
    rsicar:::.sicar_aoi_wkt_filter(path, aoi_without_crs),
    character(0)
  )
})

test_that("source ZIPs that cannot be extracted are classified", {
  testthat::local_mocked_bindings(
    unzip = function(...) stop("bad archive"),
    .package = "utils"
  )

  expect_error(
    rsicar:::.sicar_read_source_zip("source.zip"),
    "Could not extract",
    class = "rsicar_source_error"
  )
})

test_that("unreadable source shapefiles are classified", {
  root <- withr::local_tempdir()
  shapefile <- file.path(root, "broken.shp")
  writeLines("not a shapefile", shapefile)
  archive <- file.path(root, "source.zip")
  utils::zip(archive, shapefile, flags = "-qj")

  error <- rlang::catch_cnd(rsicar:::.sicar_read_source_zip(archive))

  expect_s3_class(error, "rsicar_source_error")
  expect_identical(basename(error$layer), "broken.shp")
})

test_that("geometry columns are renamed to `geometry`", {
  named <- sf::st_sf(id = 1, geom = sf::st_sfc(unit_square(), crs = 4674))
  plain <- data.frame(id = 1)
  plain$geom <- sf::st_sfc(unit_square(), crs = 4674)

  for (source in list(named, plain)) {
    result <- rsicar:::.sicar_normalize_source_geometry_name(source)
    expect_identical(names(result), c("id", "geometry"))
    expect_identical(attr(result, "sf_column"), "geometry")
  }
})

test_that("source layers with different CRSes cannot be combined", {
  layers <- list(
    sf::st_sf(id = 1, geometry = sf::st_sfc(unit_square(), crs = 4674)),
    sf::st_sf(id = 2, geometry = sf::st_sfc(unit_square(), crs = 4326))
  )

  expect_error(
    rsicar:::.sicar_bind_source_layers(layers),
    "different coordinate reference systems",
    class = "rsicar_spatial_error"
  )
})

test_that("source layers with different attributes are filled with NA", {
  layers <- list(
    sf::st_sf(
      filepath = "a.zip",
      tema = "APPS",
      first = "a",
      geometry = sf::st_sfc(unit_square(), crs = 4674)
    ),
    sf::st_sf(
      filepath = "b.zip",
      tema = "APPS",
      second = "b",
      geometry = sf::st_sfc(unit_square(1), crs = 4674)
    )
  )

  result <- rsicar:::.sicar_bind_source_layers(layers)

  expect_identical(
    names(result),
    c("filepath", "tema", "first", "second", "geometry")
  )
  expect_identical(result$first, c("a", NA))
  expect_identical(result$second, c(NA, "b"))
})

test_that("municipalities that cannot be transformed to the source CRS fail", {
  source <- sf::st_sf(id = 1, geometry = sf::st_sfc(unit_square()))

  expect_error(
    rsicar:::.sicar_select_intersecting_features(
      source,
      test_municipality_geometries()
    ),
    "could not be transformed",
    class = "rsicar_spatial_error"
  )
})

test_that("intersection failures are classified", {
  source <- sf::st_sf(id = 1, geometry = sf::st_sfc(unit_square(), crs = 4674))
  testthat::local_mocked_bindings(
    st_intersects = function(...) stop("GEOS exception"),
    .package = "sf"
  )

  expect_error(
    rsicar:::.sicar_select_intersecting_features(
      source,
      test_municipality_geometries()
    ),
    "Could not intersect",
    class = "rsicar_spatial_error"
  )
})
