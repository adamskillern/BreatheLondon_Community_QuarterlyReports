# Fetch PM2.5 + NO2 for every site in listSensors.json (API → CSV).
# Each site uses its own StartDate and formal EndDate from listSensors.json. Very slow.
#
# Terminal:
#   Rscript scripts/fetch_sensors.R
#   Rscript scripts/analysis_BL.R
#
# R console (fixes "cannot open R/bl_api.R" if wd is wrong):
#   source("~/Desktop/Code/BreatheLondon_Community_QuarterlyReports/scripts/setup_BL.R")
#   bl_fetch_all_sites_readings()

if (file.exists("scripts/setup_BL.R")) {
  source("scripts/setup_BL.R", local = TRUE)
} else if (file.exists("../scripts/setup_BL.R")) {
  source("../scripts/setup_BL.R", local = TRUE)
} else {
  source(
    "~/Desktop/Code/BreatheLondon_Community_QuarterlyReports/scripts/setup_BL.R",
    local = TRUE
  )
}

# Run the line below to fetch all sites and save the data to a CSV if save = TRUE
# data <- bl_fetch_all_sites_readings(save = FALSE)

