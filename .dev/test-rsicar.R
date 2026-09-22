library(tidyverse)

client <- rsicar::sicar_client(rsicar::sicar_solver_manual())

rsicar::sicar_release_dates(client)

rsicar::sicar_states()

rsicar::sicar_polygon_types()

state <- "ES"
rsicar::sicar_download_state(
  client,
  state,
  c("APPS", "RESERVA_LEGAL", "AREA_IMOVEL"),
  dest_dir = paste0("~/Downloads/RSICAR/", state)
)

rsicar::sicar_read_manifest("~/Downloads/RSICAR/ES")

rsicar::sicar_download_status("~/Downloads/RSICAR/ES")

mun_cod <-
  rsicar::sicar_resolve_municipality(
    c("viana/es", "domingos martins", "cariacica", "vitoria")
  )

mun_cod %>%
  as.data.frame()

mun_car <-
  rsicar::sicar_extract_municipality(mun_cod, "~/Downloads/RSICAR/ES/")

mun_car %>%
  glimpse()

## precisamos de mais duas colunas nos dados entregues pela rsicar::sicar_extract_municipality:
## `filepath` com o basename do arquivo extraído e
## `tema` com o tipoo do arquivo extraído (outputs de rsicar::sicar_polygon_types())

mun_car %>%
  mapview::mapview(map.types = c("OpenStreetMap", "Esri.WorldImagery"), zcol = "municipio")
