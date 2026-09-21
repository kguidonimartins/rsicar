.sicar_normalize_municipality_text <- function(x) {
  x <- toupper(trimws(x))
  x <- chartr(
    "\u00C1\u00C0\u00C2\u00C3\u00C4\u00C9\u00C8\u00CA\u00CB\u00CD\u00CC\u00CE\u00CF\u00D3\u00D2\u00D4\u00D5\u00D6\u00DA\u00D9\u00DB\u00DC\u00C7\u00D1",
    "AAAAAEEEEIIIIOOOOOUUUUCN",
    x
  )
  gsub("\\s+", " ", x)
}

.sicar_municipality_catalog <- function() {
  data.frame(
    code_muni = as.character(sicar_municipality_lookup$code_muni),
    name_muni = as.character(sicar_municipality_lookup$name_muni),
    abbrev_state = as.character(sicar_municipality_lookup$abbrev_state),
    stringsAsFactors = FALSE
  )
}

.sicar_resolve_municipality_code <- function(code, catalog, original) {
  if (nchar(code) != 7L) {
    .sicar_abort(
      sprintf("Invalid municipality code: `%s`.", original),
      "rsicar_invalid_argument",
      input = original
    )
  }

  if (!(code %in% catalog$code_muni)) {
    .sicar_abort(
      sprintf("Municipality code not found in the catalog: `%s`.", original),
      "rsicar_unknown_municipality",
      input = original
    )
  }

  code
}

.sicar_resolve_municipality_name <- function(
  name,
  uf,
  catalog,
  strict,
  original
) {
  candidates <- catalog
  if (!is.null(uf)) {
    candidates <- candidates[candidates$abbrev_state == uf, , drop = FALSE]
  }

  name_norm <- .sicar_normalize_municipality_text(name)
  matches <- candidates[
    .sicar_normalize_municipality_text(candidates$name_muni) == name_norm,
    ,
    drop = FALSE
  ]

  if (nrow(matches) == 1L) {
    return(matches$code_muni)
  }

  if (nrow(matches) > 1L) {
    .sicar_abort(
      c(
        sprintf("Ambiguous municipality name: `%s`.", original),
        paste0(
          "i Found in state(s): ",
          paste(unique(matches$abbrev_state), collapse = ", "),
          "."
        ),
        "i Use the format `Municipality/UF` or provide `uf`."
      ),
      "rsicar_ambiguous_municipality",
      input = original,
      candidates = matches
    )
  }

  if (isTRUE(strict)) {
    .sicar_abort(
      sprintf("Municipality not found in the catalog: `%s`.", original),
      "rsicar_unknown_municipality",
      input = original
    )
  }

  .sicar_warn(
    c(
      sprintf("Municipality not found in the catalog: `%s`.", original),
      "i Ignored because `strict` is `FALSE`."
    ),
    "rsicar_unknown_municipality",
    input = original
  )
  character(0)
}

.sicar_resolve_municipality_token <- function(
  token,
  uf,
  catalog,
  strict
) {
  original <- token
  token <- trimws(token)

  if (!nzchar(token)) {
    .sicar_abort(
      "Municipality identifiers must not be empty.",
      "rsicar_invalid_argument",
      input = original
    )
  }

  if (grepl("^[0-9]+$", token)) {
    return(.sicar_resolve_municipality_code(token, catalog, original))
  }

  if (grepl("/", token, fixed = TRUE)) {
    parts <- strsplit(token, "/", fixed = TRUE)[[1]]
    if (length(parts) != 2L || any(!nzchar(trimws(parts)))) {
      .sicar_abort(
        sprintf("Invalid municipality/UF identifier: `%s`.", original),
        "rsicar_invalid_argument",
        input = original
      )
    }
    state <- .sicar_validate_state(parts[[2]])
    return(.sicar_resolve_municipality_name(
      parts[[1]],
      state,
      catalog,
      strict,
      original
    ))
  }

  token_upper <- toupper(token)
  if (nchar(token_upper) == 2L && token_upper %in% .sicar_states) {
    return(catalog$code_muni[catalog$abbrev_state == token_upper])
  }

  .sicar_resolve_municipality_name(token, uf, catalog, strict, original)
}

#' Resolve municipality identifiers to IBGE codes
#'
#' Accepts seven-digit IBGE codes, municipality names with or without accents,
#' state abbreviations, and `Municipality/UF` identifiers. Names are matched
#' case-insensitively after whitespace and diacritic normalization. Ambiguous
#' names always fail instead of being resolved silently.
#'
#' @param x One or more IBGE codes, municipality names, state abbreviations,
#'   or `Municipality/UF` identifiers.
#' @param uf Optional state abbreviation used to disambiguate names without a
#'   state suffix.
#' @param strict If `TRUE`, unknown municipality names abort. If `FALSE`,
#'   unknown names are warned about and omitted.
#'
#' @returns A character vector of unique seven-digit IBGE codes, in order of
#'   first occurrence.
#' @family municipality extraction
#' @examples
#' sicar_resolve_municipality(c("Recife", "Olinda", "Passos/MG"))
#' sicar_resolve_municipality("sao lourenco da mata")
#' @export
sicar_resolve_municipality <- function(x, uf = NULL, strict = TRUE) {
  if (length(x) == 0L || !is.character(x) && !is.numeric(x)) {
    .sicar_abort(
      "`x` must contain one or more municipality identifiers.",
      "rsicar_invalid_argument",
      input = x
    )
  }
  if (anyNA(x)) {
    .sicar_abort(
      "`x` must not contain missing municipality identifiers.",
      "rsicar_invalid_argument",
      input = x
    )
  }
  if (
    length(strict) != 1L ||
      !is.logical(strict) ||
      is.na(strict)
  ) {
    .sicar_abort(
      "`strict` must be TRUE or FALSE.",
      "rsicar_invalid_argument",
      field = "strict",
      value = strict
    )
  }

  if (!is.null(uf)) {
    uf <- .sicar_validate_state(uf)
  }

  catalog <- .sicar_municipality_catalog()
  resolved <- lapply(
    as.character(x),
    .sicar_resolve_municipality_token,
    uf = uf,
    catalog = catalog,
    strict = strict
  )
  unique(unlist(resolved, use.names = FALSE))
}
