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
