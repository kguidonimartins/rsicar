# Official SICAR domain values, kept in the same order as the upstream project.
.sicar_states <- c(
  "AC",
  "AL",
  "AM",
  "AP",
  "BA",
  "CE",
  "DF",
  "ES",
  "GO",
  "MA",
  "MG",
  "MS",
  "MT",
  "PA",
  "PB",
  "PE",
  "PI",
  "PR",
  "RJ",
  "RN",
  "RO",
  "RR",
  "RS",
  "SC",
  "SE",
  "SP",
  "TO"
)

.sicar_polygons <- c(
  "AREA_IMOVEL",
  "APPS",
  "VEGETACAO_NATIVA",
  "AREA_CONSOLIDADA",
  "AREA_POUSIO",
  "HIDROGRAFIA",
  "USO_RESTRITO",
  "SERVIDAO_ADMINISTRATIVA",
  "RESERVA_LEGAL"
)

.sicar_urls <- list(
  base = "https://consultapublica.car.gov.br/publico",
  index = "https://consultapublica.car.gov.br/publico/imoveis/index",
  download_base = "https://consultapublica.car.gov.br/publico/estados/downloadBase",
  recaptcha = "https://consultapublica.car.gov.br/publico/municipios/ReCaptcha",
  release_date = "https://consultapublica.car.gov.br/publico/estados/downloads"
)

.sicar_default_headers <- c(
  `User-Agent` = paste(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/122.0.0.0 Safari/537.36"
  ),
  Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  Connection = "close"
)
