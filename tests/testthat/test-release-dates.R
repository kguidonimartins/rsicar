test_that("release dates parse all states", {
  result <- rsicar:::.sicar_parse_release_dates(release_fixture())

  expect_identical(names(result), c("state", "date"))
  expect_length(result$state, 27)
  expect_s3_class(result$date, "Date")
  expect_identical(result$state[1], "AC")
  expect_identical(result$date[27], as.Date("2026-01-27"))
})

test_that("release dates reject incomplete markup", {
  html <- sub("data-estado='TO'", "data-estado='XX'", release_fixture())

  expect_error(
    rsicar:::.sicar_parse_release_dates(html),
    class = "rsicar_parse_error"
  )
})

test_that("release dates reject invalid dates", {
  html <- sub("01/01/2026", "not-a-date", release_fixture(), fixed = TRUE)

  expect_error(
    rsicar:::.sicar_parse_release_dates(html),
    class = "rsicar_parse_error"
  )
})

test_that("release dates accept an already parsed document", {
  result <- rsicar:::.sicar_parse_release_dates(
    xml2::read_html(release_fixture())
  )

  expect_length(result$state, 27)
})

test_that("sicar_release_dates validates the client", {
  expect_error(
    sicar_release_dates("not-a-client"),
    class = "rsicar_invalid_argument"
  )
})
