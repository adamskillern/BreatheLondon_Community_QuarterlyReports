#!/usr/bin/env Rscript
# Fetch hourly NO2 and PM2.5 for one or more sites; write CSVs for the quarterly report.
#
# Required in .env: BREATHE_API_KEY, BL_REPORT_SITE_CODES (or BL_SITE_CODE)
# Default date range: each site's StartDate → EndDate from listSensors.json
# Or pass site code(s) as CLI arguments (optional shared start/end dates after codes)
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

is_site_arg <- function(x) grepl("^CLDP", x, ignore.case = TRUE)
site_codes <- if (length(args) && any(is_site_arg(args))) {
  bl_parse_site_code_list(paste(args[is_site_arg(args)], collapse = ","))
} else {
  bl_resolve_report_site_codes()
}

date_args <- args[!is_site_arg(args)]
shared_start <- if (length(date_args) >= 1) bl_to_api_gmt_string(date_args[[1]]) else NULL
shared_end <- if (length(date_args) >= 2) bl_to_api_gmt_string(date_args[[2]]) else NULL

species_no2 <- bl_env("BL_SPECIES_NO2", "INO2")
species_pm25 <- bl_env("BL_SPECIES_PM25", "IPM25")

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

for (site_code in site_codes) {
  start_time <- shared_start %||% bl_resolve_fetch_start(site_code)
  end_time <- shared_end %||% bl_resolve_fetch_end(site_code)

  if (!nzchar(start_time) || !nzchar(end_time)) {
    stop("Could not resolve API date range for ", site_code, call. = FALSE)
  }

  message("Fetching ", site_code, " (", start_time, " -> ", end_time, ") ...")
  data <- bl_fetch_readings(
    site_code = site_code,
    start_time = start_time,
    end_time = end_time,
    species_no2 = species_no2,
    species_pm25 = species_pm25
  )

  no2_path <- file.path("data/processed", paste0("no2_", site_code, ".csv"))
  pm25_path <- file.path("data/processed", paste0("pm25_", site_code, ".csv"))
  utils::write.csv(data$no2, no2_path, row.names = FALSE)
  utils::write.csv(data$pm25, pm25_path, row.names = FALSE)
  message("  Wrote ", nrow(data$no2), " NO2 rows -> ", no2_path)
  message("  Wrote ", nrow(data$pm25), " PM2.5 rows -> ", pm25_path)
}
