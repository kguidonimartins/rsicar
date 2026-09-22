.sicar_require_sf <- function() {
  rlang::check_installed(
    "sf",
    reason = "to read and intersect SICAR geometries"
  )
}

.sicar_make_valid <- function(source) {
  repaired <- sf::st_make_valid(source)
  revalidated <- sf::st_is_valid(repaired, NA_on_exception = TRUE)
  if (!(anyNA(revalidated) || any(!revalidated)) || !isTRUE(sf::sf_use_s2())) {
    return(repaired)
  }
  # `st_make_valid()` dispatches to the spherical s2 engine for geographic
  # CRSes (SICAR data is SIRGAS 2000 / WGS 84), which does not always resolve
  # self-intersections that the planar GEOS engine handles fine. Retry once
  # with s2 switched off before giving up.
  previous_s2 <- sf::sf_use_s2()
  suppressMessages(sf::sf_use_s2(FALSE))
  withr::defer(suppressMessages(sf::sf_use_s2(previous_s2)))
  sf::st_make_valid(source)
}

.sicar_repair_invalid_geometries <- function(source, zip_path, path) {
  valid <- sf::st_is_valid(source, NA_on_exception = TRUE)
  invalid <- is.na(valid) | !valid
  if (!any(invalid)) {
    return(source)
  }

  repaired <- tryCatch(
    .sicar_make_valid(source),
    error = function(error) {
      .sicar_abort(
        sprintf(
          "Could not repair invalid geometries in source shapefile: `%s`.",
          path
        ),
        "rsicar_spatial_error",
        parent = error,
        path = zip_path,
        layer = path
      )
    }
  )

  revalidated <- sf::st_is_valid(repaired, NA_on_exception = TRUE)
  if (anyNA(revalidated) || any(!revalidated)) {
    .sicar_abort(
      "Source shapefile contains geometries that could not be repaired.",
      "rsicar_spatial_error",
      path = zip_path,
      layer = path,
      n_unrepaired = sum(is.na(revalidated) | !revalidated)
    )
  }

  n_invalid <- sum(invalid)
  .sicar_warn(
    sprintf(
      "Repaired %d invalid %s in source shapefile with `sf::st_make_valid()`.",
      n_invalid,
      if (n_invalid == 1L) "geometry" else "geometries"
    ),
    "rsicar_repaired_geometry",
    path = zip_path,
    layer = path,
    n = n_invalid
  )
  repaired
}

.sicar_aoi_bbox <- function(municipalities) {
  if (nrow(municipalities) == 0L) {
    return(NULL)
  }
  sf::st_as_sfc(sf::st_bbox(municipalities))
}

.sicar_shapefile_crs <- function(path) {
  # Read the sibling `.prj` file directly instead of `sf::st_read()`-ing the
  # shapefile just to ask its CRS: this lets the AOI bounding box be
  # reprojected to match *before* the real read, so that read can pass it in
  # as `wkt_filter` and let GDAL skip features outside it instead of
  # materializing (and later discarding) the whole layer.
  prj_path <- sub("\\.shp$", ".prj", path, ignore.case = TRUE)
  if (!file.exists(prj_path)) {
    return(sf::NA_crs_)
  }
  tryCatch(
    sf::st_crs(paste(readLines(prj_path, warn = FALSE), collapse = " ")),
    error = function(error) sf::NA_crs_
  )
}

.sicar_aoi_wkt_filter <- function(path, aoi) {
  if (is.null(aoi)) {
    return(character(0))
  }
  crs <- .sicar_shapefile_crs(path)
  if (is.na(crs)) {
    return(character(0))
  }
  transformed <- tryCatch(
    sf::st_transform(aoi, crs),
    error = function(error) NULL
  )
  if (is.null(transformed)) {
    return(character(0))
  }
  sf::st_as_text(transformed)
}

.sicar_source_theme <- function(shapefile, zip_path) {
  for (path in c(shapefile, zip_path)) {
    stem <- toupper(tools::file_path_sans_ext(basename(path)))
    stem <- sub("^[A-Z]{2}_", "", stem)
    stem <- sub("_[0-9]+$", "", stem)
    if (stem %in% .sicar_polygons) {
      return(stem)
    }
  }
  NA_character_
}

.sicar_read_source_zip <- function(zip_path, aoi = NULL) {
  extracted <- withr::local_tempdir("rsicar-source-")
  tryCatch(
    utils::unzip(zip_path, exdir = extracted),
    error = function(error) {
      .sicar_abort(
        sprintf("Could not extract source ZIP archive: `%s`.", zip_path),
        "rsicar_source_error",
        parent = error,
        path = zip_path
      )
    }
  )

  shapefiles <- list.files(
    extracted,
    pattern = "\\.shp$",
    full.names = TRUE,
    recursive = TRUE,
    ignore.case = TRUE
  )
  if (length(shapefiles) == 0L) {
    .sicar_abort(
      "Source ZIP contains no shapefile.",
      "rsicar_source_error",
      path = zip_path
    )
  }

  lapply(shapefiles, function(path) {
    wkt_filter <- .sicar_aoi_wkt_filter(path, aoi)
    source <- tryCatch(
      sf::st_read(
        path,
        quiet = TRUE,
        stringsAsFactors = FALSE,
        wkt_filter = wkt_filter
      ),
      error = function(error) {
        .sicar_abort(
          sprintf("Could not read source shapefile: `%s`.", path),
          "rsicar_source_error",
          parent = error,
          path = zip_path,
          layer = path
        )
      }
    )
    source_crs <- sf::st_crs(source)
    if (is.na(source_crs)) {
      .sicar_abort(
        "Source shapefile has no CRS.",
        "rsicar_spatial_error",
        path = zip_path,
        layer = path
      )
    }

    source <- .sicar_repair_invalid_geometries(source, zip_path, path)
    source$filepath <- rep(zip_path, nrow(source))
    source$tema <- rep(.sicar_source_theme(path, zip_path), nrow(source))
    source
  })
}

.sicar_read_source_zips <- function(source_paths, aoi = NULL) {
  # `.sicar_read_source_zip()` extracts and validates each ZIP, which can take
  # a while with no output of its own; surface progress here so the console
  # does not go silent for the whole call, the way `sicar_download_state()`
  # already does for downloads.
  progress_id <- cli::cli_progress_bar(
    format = paste0(
      "Reading source archive {cli::pb_current}/{cli::pb_total} ",
      "{cli::pb_bar} {cli::pb_percent} | eta: {cli::pb_eta}"
    ),
    total = length(source_paths),
    clear = TRUE
  )
  on.exit(cli::cli_progress_done(id = progress_id), add = TRUE)

  lapply(seq_along(source_paths), function(i) {
    result <- .sicar_read_source_zip(source_paths[[i]], aoi = aoi)
    cli::cli_progress_update(id = progress_id, set = i)
    result
  })
}

.sicar_normalize_source_geometry_name <- function(source) {
  geometry_name <- attr(source, "sf_column")
  if (is.null(geometry_name)) {
    geometry_name <- names(source)[
      vapply(source, inherits, logical(1), what = "sfc")
    ]
  }
  if (!identical(geometry_name, "geometry")) {
    names(source)[names(source) == geometry_name] <- "geometry"
    attr(source, "sf_column") <- "geometry"
  }
  source
}

.sicar_bind_source_layers <- function(layers) {
  layers <- lapply(layers, .sicar_normalize_source_geometry_name)
  crs <- sf::st_crs(layers[[1]])
  if (
    any(!vapply(layers, function(x) isTRUE(sf::st_crs(x) == crs), logical(1)))
  ) {
    .sicar_abort(
      "Source shapefiles use different coordinate reference systems.",
      "rsicar_spatial_error"
    )
  }

  columns <- unique(unlist(lapply(layers, names), use.names = FALSE))
  columns <- c(
    "filepath",
    "tema",
    setdiff(columns, c("filepath", "tema", "geometry")),
    "geometry"
  )
  layers <- lapply(layers, function(layer) {
    missing <- setdiff(columns, names(layer))
    for (name in missing) {
      layer[[name]] <- NA
    }
    layer[columns]
  })

  tryCatch(
    # A layer can legitimately have zero rows once the AOI `wkt_filter` in
    # `.sicar_read_source_zip()` excludes every feature; `rbind()`-ing it
    # then hits a known sf/GEOS wart where computing an empty bounding box
    # warns ("no non-missing arguments to min/max"). It is harmless here.
    suppressWarnings(do.call(rbind, layers)),
    error = function(error) {
      .sicar_abort(
        "Source shapefiles could not be combined because their schemas are incompatible.",
        "rsicar_source_error",
        parent = error
      )
    }
  )
}

.sicar_select_intersecting_features <- function(source, municipalities) {
  target <- municipalities
  source_crs <- sf::st_crs(source)
  if (!isTRUE(sf::st_crs(target) == source_crs)) {
    target <- tryCatch(
      sf::st_transform(target, source_crs),
      error = function(error) {
        .sicar_abort(
          "Municipality geometries could not be transformed to the source CRS.",
          "rsicar_spatial_error",
          parent = error
        )
      }
    )
  }

  hits <- tryCatch(
    sf::st_intersects(source, target),
    error = function(error) {
      .sicar_abort(
        "Could not intersect source and municipality geometries.",
        "rsicar_spatial_error",
        parent = error
      )
    }
  )
  source[lengths(hits) > 0L, , drop = FALSE]
}

#' Extract SICAR geometries intersecting one or more municipalities
#'
#' Reads shapefiles from one ZIP archive or recursively from a source
#' directory, then keeps every SICAR feature that intersects at least one
#' requested municipality. The original SICAR geometries and attributes are
#' returned without clipping or writing files. Two source columns are added:
#' `filepath` is the absolute path of the source ZIP archive, and `tema` is
#' the matching value from [sicar_polygon_types()]. These are the first two
#' attribute columns. If neither the shapefile nor its ZIP archive has a
#' recognized theme in its name, `tema` is `NA`.
#'
#' @param x One or more identifiers accepted by
#'   [sicar_resolve_municipality()].
#' @param src_dir A path to one SICAR ZIP archive or a directory containing
#'   ZIP archives. Directory contents are searched recursively.
#'
#' @returns An `sf` object containing the selected original SICAR features.
#'   If no source feature intersects the requested municipalities, the result
#'   has zero rows and retains the source schema, including `filepath` and
#'   `tema`.
#' @family municipality extraction
#' @examples
#' \dontrun{
#' features <- sicar_extract_municipality(
#'   c("Recife", "Olinda"),
#'   src_dir = "SICAR/PE"
#' )
#' sf::st_write(features, "minha-aoi.gpkg")
#' }
#' @export
sicar_extract_municipality <- function(x, src_dir) {
  .sicar_require_sf()
  codes <- sicar_resolve_municipality(x)
  source_paths <- .sicar_source_files(src_dir)
  municipalities <- .sicar_municipality_geometries()
  municipalities <- municipalities[
    municipalities$code_muni %in% codes,
    ,
    drop = FALSE
  ]

  aoi <- .sicar_aoi_bbox(municipalities)
  layers <- unlist(
    .sicar_read_source_zips(source_paths, aoi = aoi),
    recursive = FALSE
  )
  source <- .sicar_bind_source_layers(layers)
  .sicar_select_intersecting_features(source, municipalities)
}
