# ambiguous municipality names produce a classified error

    Code
      sicar_resolve_municipality("araçoiaba")
    Condition
      Error in `.sicar_abort()`:
      ! Ambiguous municipality name: `araçoiaba`.
      * i Found in state(s): CE, PE.
      * i Use the format `Municipality/UF` or provide `uf`.

# unknown names can be omitted in non-strict mode

    Code
      result <- sicar_resolve_municipality(c("recife", "municipio inexistente"),
      strict = FALSE)
    Condition
      Warning:
      Municipality not found in the catalog: `municipio inexistente`.
      * i Ignored because `strict` is `FALSE`.
    Code
      expect_identical(result, c(`Recife/PE` = "2611606"))

# invalid municipality identifiers produce classified errors

    Code
      sicar_resolve_municipality("123")
    Condition
      Error in `.sicar_abort()`:
      ! Invalid municipality code: `123`.

---

    Code
      sicar_resolve_municipality("Municipio/XX")
    Condition
      Error in `.sicar_abort()`:
      ! Unknown state `XX`.

