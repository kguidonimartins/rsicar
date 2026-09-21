test_that("the official states and polygon types are exposed", {
  expect_length(sicar_states(), 27)
  expect_identical(sicar_states()[1], "AC")
  expect_identical(sicar_states()[27], "TO")
  expect_length(sicar_polygon_types(), 9)
  expect_identical(sicar_polygon_types()[2], "APPS")
})

test_that("clients are lazy and preserve configuration", {
  solver <- sicar_solver_function(function(path) "a1b2c")
  client <- sicar_client(
    solver = solver,
    headers = c("X-Test" = "yes"),
    timeout = 12
  )

  expect_s3_class(client, "sicar_client")
  expect_identical(client$headers, c("X-Test" = "yes"))
  expect_identical(client$timeout, 12)
  expect_identical(client$solver$name, "function")
})

test_that("state and polygon values are normalized", {
  expect_identical(rsicar:::.sicar_validate_state(" pa "), "PA")
  expect_identical(rsicar:::.sicar_validate_polygon("apps"), "APPS")
})

test_that("invalid domain values have structured errors", {
  expect_error(
    rsicar:::.sicar_validate_state("XX"),
    class = "rscicar_invalid_argument"
  )
  expect_error(
    rsicar:::.sicar_validate_polygon("unknown"),
    class = "rscicar_invalid_argument"
  )
})
