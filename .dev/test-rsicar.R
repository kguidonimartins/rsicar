library(tidyverse)

client <- rsicar::sicar_client(rsicar::sicar_solver_tesseract())

rsicar::sicar_release_dates(client)

rsicar::sicar_states()

rsicar::sicar_polygon_types()

state <- "RJ"
rsicar::sicar_download_state(
  client,
  state,
  c("APPS", "RESERVA_LEGAL", "AREA_IMOVEL"),
  dest_dir = paste0("~/Downloads/RSICAR/", state)
)

rsicar::sicar_read_manifest("~/Downloads/RSICAR/SE")

rsicar::sicar_download_status("~/Downloads/RSICAR/SE")

mun_cod <-
  rsicar::sicar_resolve_municipality(
    c("viana/es", "domingos martins", "cariacica", "vitoria")
  )

mun_cod %>%
  as.data.frame()

mun_car <-
  rsicar::sicar_extract_municipality(mun_cod, "~/Downloads/RSICAR/ES/")

mun_car %>%
  mapview::mapview(map.types = c("OpenStreetMap", "Esri.WorldImagery"), zcol = "municipio")
