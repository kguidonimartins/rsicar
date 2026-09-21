test_that("custom solvers are normalized", {
  solver <- sicar_solver_function(function(path) " ab1c2 ")

  expect_s3_class(solver, "sicar_solver")
  expect_identical(rsicar:::.sicar_solve(solver, "captcha.png"), "AB1C2")
})

test_that("custom solvers reject invalid output", {
  solver <- sicar_solver_function(function(path) "too-long")

  expect_error(
    rsicar:::.sicar_solve(solver, "captcha.png"),
    class = "rscicar_solver_error"
  )
})
