.sicar_require_sf <- function() {
  rlang::check_installed(
    "sf",
    reason = "to read and intersect SICAR geometries"
  )
}

.sicar_read_source_zip <- function(zip_path) {
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
    source <- tryCatch(
      sf::st_read(path, quiet = TRUE, stringsAsFactors = FALSE),
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

    valid <- sf::st_is_valid(source, NA_on_exception = TRUE)
    if (anyNA(valid) || any(!valid)) {
      .sicar_abort(
        "Source shapefile contains invalid geometries.",
        "rsicar_spatial_error",
        path = zip_path,
        layer = path
      )
    }
    source
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
  columns <- c(setdiff(columns, "geometry"), "geometry")
  layers <- lapply(layers, function(layer) {
    missing <- setdiff(columns, names(layer))
    for (name in missing) {
      layer[[name]] <- NA
    }
    layer[columns]
  })

  tryCatch(
    do.call(rbind, layers),
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
#' returned unchanged; the function does not clip or write files.
#'
#' @param x One or more identifiers accepted by
#'   [sicar_resolve_municipality()].
#' @param src_dir A path to one SICAR ZIP archive or a directory containing
#'   ZIP archives. Directory contents are searched recursively.
#'
#' @returns An `sf` object containing the selected original SICAR features.
#'   If no source feature intersects the requested municipalities, the result
#'   has zero rows and retains the source schema.
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

  layers <- unlist(
    lapply(source_paths, .sicar_read_source_zip),
    recursive = FALSE
  )
  source <- .sicar_bind_source_layers(layers)
  .sicar_select_intersecting_features(source, municipalities)
}
