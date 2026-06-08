#!/usr/bin/env Rscript
# Fetch hourly NO2 and PM2.5 for one site; write CSVs for the quarterly report.
#
# Required in .env: BREATHE_API_KEY, BL_SITE_CODE
# Default date range: last completed calendar quarter (see scripts/show_api_times.R)
# Or pass site + start + end as CLI arguments
#
# Optional: BL_SPECIES_NO2 (default INO2), BL_SPECIES_PM25 (default IPM25)

args <- commandArgs(trailingOnly = TRUE)

root <- Sys.getenv("BL_PROJECT_ROOT", unset = getwd())
if (basename(root) == "scripts") {
  root <- normalizePath(file.path(root, ".."))
}
setwd(root)

source("scripts/load_env.R", local = TRUE)
source("R/bl_api.R", local = TRUE)
bl_load_env()

site_code <- if (length(args) >= 1) args[[1]] else bl_env("BL_SITE_CODE")
start_time <- if (length(args) >= 2) {
  bl_to_api_gmt_string(args[[2]])
} else {
  bl_resolve_fetch_start()
}
end_time <- if (length(args) >= 3) {
  bl_to_api_gmt_string(args[[3]])
} else {
  bl_resolve_fetch_end()
}

if (!nzchar(site_code) || !nzchar(start_time) || !nzchar(end_time)) {
  stop(
    "Set BL_SITE_CODE in .env\n",
    "Or: Rscript scripts/fetch_readings.R SITE \"01 Jan 2025 00:00:00 GMT\" \"31 Mar 2025 23:00:00 GMT\"",
    call. = FALSE
  )
}

message("API range: ", start_time, "  ->  ", end_time)

species_no2 <- bl_env("BL_SPECIES_NO2", "INO2")
species_pm25 <- bl_env("BL_SPECIES_PM25", "IPM25")

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

message("Fetching readings for ", site_code, " ...")
data <- bl_fetch_readings(
  site_code = site_code,
  start_time = start_time,
  end_time = end_time,
  species_no2 = species_no2,
  species_pm25 = species_pm25
)

utils::write.csv(data$no2, "data/processed/no2.csv", row.names = FALSE)
utils::write.csv(data$pm25, "data/processed/pm25.csv", row.names = FALSE)
message("Wrote ", nrow(data$no2), " NO2 rows and ", nrow(data$pm25), " PM2.5 rows")
