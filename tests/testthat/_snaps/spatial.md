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

# invalid source geometries are repaired with st_make_valid()

    Code
      result <- sicar_extract_municipality("Recife", archive)
    Condition
      Warning:
      Repaired 1 invalid geometry in source shapefile with `sf::st_make_valid()`.

