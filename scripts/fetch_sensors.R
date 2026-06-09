#!/usr/bin/env Rscript
# Fetch all sensor metadata and cache under data/raw/
# After initial / refreshed fetch, use listSensors.json

root <- Sys.getenv("BL_PROJECT_ROOT", unset = getwd())
if (basename(root) == "scripts") {
  root <- normalizePath(file.path(root, ".."))
}
setwd(root)

source("scripts/load_env.R", local = TRUE)
source("R/bl_api.R", local = TRUE)
bl_load_env()

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

message("Fetching sensor list...")
sensors <- bl_list_sensors()

out <- "data/raw/listSensors.json"
jsonlite::write_json(sensors, out, auto_unbox = TRUE, pretty = TRUE)
n <- if (is.data.frame(sensors)) {
  nrow(sensors)
} else if (is.list(sensors) && length(sensors) == 1L && is.data.frame(sensors[[1]])) {
  nrow(sensors[[1]])
} else {
  length(sensors)
}
message("Wrote ", n, " sensors to ", out)
