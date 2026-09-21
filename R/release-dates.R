.sicar_parse_release_dates <- function(html) {
  document <- if (inherits(html, "xml_document")) {
    html
  } else {
    xml2::read_html(html)
  }
  blocks <- xml2::xml_find_all(
    document,
    ".//div[contains(@class, 'listagem-estados')]"
  )
  states <- vapply(
    blocks,
    function(block) {
      button <- xml2::xml_find_first(block, ".//button[@data-estado]")
      xml2::xml_attr(button, "data-estado")
    },
    character(1)
  )
  dates <- vapply(
    blocks,
    function(block) {
      date <- xml2::xml_find_first(
        block,
        ".//*[contains(@class, 'data-disponibilizacao')]"
      )
      trimws(xml2::xml_text(date))
    },
    character(1)
  )

  valid <- states %in% .sicar_states & nzchar(states) & nzchar(dates)
  states <- states[valid]
  dates <- dates[valid]
  if (
    length(states) != length(unique(states)) ||
      length(states) != length(.sicar_states)
  ) {
    .sicar_abort(
      sprintf(
        "Expected one release date for each of the %d states.",
        length(.sicar_states)
      ),
      "rscicar_parse_error",
      states = states
    )
  }

  parsed_dates <- as.Date(dates, format = "%d/%m/%Y")
  if (anyNA(parsed_dates)) {
    .sicar_abort(
      "SICAR returned an invalid release date.",
      "rscicar_parse_error",
      dates = dates
    )
  }

  data.frame(
    state = states,
    date = parsed_dates,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Query SICAR polygon release dates
#'
#' @param client An object created by [sicar_client()].
#' @returns A data frame with `state` and `date` columns for all 27 states.
#' @export
sicar_release_dates <- function(client) {
  if (!inherits(client, "sicar_client")) {
    .sicar_abort(
      "`client` must be created by `sicar_client()`.",
      "rscicar_invalid_argument",
      field = "client",
      value = client
    )
  }
  .sicar_bootstrap(client)
  response <- .sicar_perform(client, client$urls$release_date)
  response <- .sicar_require_response(
    response,
    client$urls$release_date,
    200,
    "text/html"
  )
  .sicar_parse_release_dates(httr2::resp_body_string(response))
}
