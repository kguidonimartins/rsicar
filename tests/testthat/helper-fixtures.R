release_fixture <- function() {
  blocks <- vapply(
    seq_along(sicar_states()),
    function(index) {
      sprintf(
        paste0(
          "<div class='listagem-estados'>",
          "<button data-estado='%s'></button>",
          "<div class='data-disponibilizacao'>%02d/01/2026</div>",
          "</div>"
        ),
        sicar_states()[index],
        index
      )
    },
    character(1)
  )
  paste0("<html><body>", paste(blocks, collapse = ""), "</body></html>")
}
