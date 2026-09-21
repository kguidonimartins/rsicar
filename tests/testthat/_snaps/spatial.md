# source archives without shapefiles are rejected

    Code
      sicar_extract_municipality("Recife", archive)
    Condition
      Error in `.sicar_abort()`:
      ! Source ZIP contains no shapefile.

# source shapefiles without a CRS are rejected

    Code
      sicar_extract_municipality("Recife", archive)
    Condition
      Error in `.sicar_abort()`:
      ! Source shapefile has no CRS.

# invalid source geometries are rejected

    Code
      sicar_extract_municipality("Recife", archive)
    Condition
      Error in `.sicar_abort()`:
      ! Source shapefile contains invalid geometries.

