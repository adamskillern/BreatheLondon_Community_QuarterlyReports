#!/usr/bin/env Rscript

if (!file.exists("R/bl_api.R")) {
  stop("Run from the project root.", call. = FALSE)
}

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

source("R/bl_api.R")
source("R/bl_marylebone.R")
bl_load_env()

report_data <- bl_load_report_data()
dates <- bl_env_report_dates()

marylebone_hourly <- bl_load_marylebone_hourly()

pollutants <- c(NO2 = "no2", PM2.5 = "pm25")
for (pollutant in names(pollutants)) {
  value_col <- pollutants[[pollutant]]
  df <- if (value_col == "no2") report_data$no2 else report_data$pm25
  sel <- bl_select_marylebone_narrative(
    df,
    marylebone_hourly,
    value_col,
    dates$quarter_start,
    dates$quarter_end
  )
  cat("\n=== ", pollutant, " (", dates$quarter_start, "to", dates$quarter_end, ") ===\n", sep = "")
  if (is.null(sel)) {
    cat("No narrative selected (insufficient paired data).\n")
  } else {
    cat("Option:", sel$option, "\n")
    if (identical(sel$option, "SPIKE")) {
      cat("Period:", sel$period_label, "(", sel$window_label, ")\n", sep = "")
    }
    cat("Community headline:", sel$headline_community, "\n")
    cat("Marylebone headline:", sel$headline_marylebone, "\n")
    cat("Within 25%:", sel$within_25pct, "\n")
    cat("Cumulative load:", sel$cumulative_load, "\n")
    if (!is.na(sel$n_spike_days)) {
      cat("Spike days:", sel$n_spike_days, "\n")
    }
    footnote <- bl_format_marylebone_footnote(
      sel,
      pollutant,
      paste0("Q", dates$report_quarter)
    )
    cat("\nFootnote:\n", footnote, "\n", sep = "")
  }
}
