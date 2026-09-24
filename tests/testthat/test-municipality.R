test_that("municipality identifiers resolve to ordered unique IBGE codes", {
  result <- sicar_resolve_municipality(
    c("recife", "olinda", "paulista/PE", "Recife", "Passos/MG")
  )

  expect_identical(
    result,
    c(
      "Recife/PE" = "2611606",
      "Olinda/PE" = "2609600",
      "Paulista/PE" = "2610707",
      "Passos/MG" = "3147907"
    )
  )
})

test_that("municipality names ignore accents and repeated whitespace", {
  expect_identical(
    sicar_resolve_municipality("  sao   lourenco da mata "),
    c("São Lourenço da Mata/PE" = "2613701")
  )
})

test_that("state identifiers expand to all municipality codes", {
  result <- sicar_resolve_municipality("PE")

  expect_identical(length(result), 185L)
  expect_identical(result[[1]], "2600054")
  expect_identical(result[[185]], "2616506")
})

test_that("the uf argument disambiguates municipality names", {
  expect_identical(
    sicar_resolve_municipality("Araçoiaba", uf = "PE"),
    c("Araçoiaba/PE" = "2601052")
  )
})

test_that("ambiguous municipality names produce a classified error", {
  expect_snapshot(
    error = TRUE,
    sicar_resolve_municipality("araçoiaba")
  )
})

test_that("unknown names can be omitted in non-strict mode", {
  expect_snapshot({
    result <- sicar_resolve_municipality(
      c("recife", "municipio inexistente"),
      strict = FALSE
    )
    expect_identical(result, c("Recife/PE" = "2611606"))
  })
})

test_that("invalid municipality identifiers produce classified errors", {
  expect_snapshot(
    error = TRUE,
    sicar_resolve_municipality("123")
  )
  expect_snapshot(
    error = TRUE,
    sicar_resolve_municipality("Municipio/XX")
  )
})

test_that("seven-digit IBGE codes resolve as character or numeric input", {
  expect_identical(
    sicar_resolve_municipality("2611606"),
    c("Recife/PE" = "2611606")
  )
  expect_identical(
    sicar_resolve_municipality(2611606),
    c("Recife/PE" = "2611606")
  )
})

test_that("unknown municipality codes and names abort in strict mode", {
  expect_error(
    sicar_resolve_municipality("9999999"),
    "code not found",
    class = "rsicar_unknown_municipality"
  )
  expect_error(
    sicar_resolve_municipality("municipio inexistente"),
    "not found in the catalog",
    class = "rsicar_unknown_municipality"
  )
})

test_that("malformed municipality identifiers are rejected", {
  for (x in c("  ", "Recife/PE/BR", "/PE", "Recife/")) {
    expect_error(
      sicar_resolve_municipality(x),
      class = "rsicar_invalid_argument"
    )
  }
})

test_that("sicar_resolve_municipality validates its arguments", {
  expect_error(
    sicar_resolve_municipality(character(0)),
    class = "rsicar_invalid_argument"
  )
  expect_error(
    sicar_resolve_municipality(TRUE),
    class = "rsicar_invalid_argument"
  )
  expect_error(
    sicar_resolve_municipality(c("Recife", NA)),
    "missing municipality identifiers",
    class = "rsicar_invalid_argument"
  )
  for (strict in list(NA, "yes", c(TRUE, FALSE))) {
    error <- rlang::catch_cnd(sicar_resolve_municipality(
      "Recife",
      strict = strict
    ))
    expect_s3_class(error, "rsicar_invalid_argument")
    expect_identical(error$field, "strict")
  }
})
