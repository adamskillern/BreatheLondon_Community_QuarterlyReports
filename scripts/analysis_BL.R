# Fetch PM2.5 + NO2 for every site in listSensors.json (API → CSV).
# Each site uses its own StartDate and formal EndDate from listSensors.json. Very slow.
#
# Terminal:
#   Rscript scripts/fetch_sensors.R
#   Rscript scripts/analysis_BL.R
#
# R console (if wd is wrong):
#   source("scripts/setup_BL.R")
#   bl_fetch_all_sites_readings()

if (file.exists("scripts/setup_BL.R")) {
  source("scripts/setup_BL.R")
} else if (file.exists("../scripts/setup_BL.R")) {
  source("../scripts/setup_BL.R")
} else {
  stop(
    "Run from the project root (Rscript scripts/analysis_BL.R) ",
    "or source('scripts/setup_BL.R') after setwd() to the repo.",
    call. = FALSE
  )
}

# Run the line below to fetch all sites and save the data to a CSV if save = TRUE
# data <- bl_fetch_all_sites_readings(save = FALSE)


get_marylebone_openair <- function(
  json_path = "data/raw/listSensors.json") {
  # Get earliest start date from listSensors.json
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite: install.packages('jsonlite')", call. = FALSE)
  }
  library(jsonlite)
  sensors <- fromJSON(json_path, simplifyVector = TRUE)[[1]]
  earliest_start <- min(as.Date(sensors$StartDate), na.rm = TRUE)
  cat("Earliest start date:", format(earliest_start, "%Y-%m-%d"), "\n")

  # Import Marylebone Road data from openair
  if (!requireNamespace("openair", quietly = TRUE)) {
    stop("Install openair: install.packages('openair')", call. = FALSE)
  }
  end_year <- as.integer(format(Sys.Date(), "%Y"))
  data <- openair::importUKAQ(
    site = "my1",
    year = lubridate::year(earliest_start):end_year,
    pollutant = c("no2", "pm2.5"),
    progress = FALSE
  )
  data <- data[data$date >= earliest_start, ]
  cat(
    "Marylebone Road (MY1):", nrow(data), "hourly rows from",
    format(min(data$date), "%Y-%m-%d %H:%M"), "to",
    format(max(data$date), "%Y-%m-%d %H:%M"), "\n"
  )
  data
}

# Marylebone Road reference site — AURN kerbside monitor on Marylebone Rd.
# Quarterly reports auto-cache MY1: if data/processed/marylebone.RData is missing,
# the first knit fetches via openair and saves it; later knits load RData only.
# To refresh manually:
#   marylebone <- get_marylebone_openair()
#   save(marylebone, file = "data/processed/marylebone.RData")


