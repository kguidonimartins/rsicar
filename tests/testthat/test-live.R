test_that("live SICAR endpoints expose all release dates", {
  skip_if_not(
    identical(Sys.getenv("RSCICAR_RUN_LIVE_TESTS"), "true"),
    "set RSCICAR_RUN_LIVE_TESTS=true to run live contract tests"
  )

  client <- sicar_client(
    solver = sicar_solver_function(function(path) "ABCDE")
  )
  result <- sicar_release_dates(client)

  expect_length(result$state, 27)
  expect_length(which(is.na(result$date)), 0)
})
