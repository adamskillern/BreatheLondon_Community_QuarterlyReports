#!/usr/bin/env Rscript
# PM2.5 polar plots for BLC CLDP sites using co-located wind module data (SS2 / CLDP0665).
#
# Fetches PM2.5 from the API, merges with high-resolution wind CSVs, saves an RData
# cache, and writes mean + NWR polar plots per site.
#
# Run from project root:
#   Rscript scripts/polar_plots.R
#
# Outputs:
#   data/processed/pm25_wd_analysis_14Jun2026.RData
#   output/polar_plots/pm25_<SiteCode>_{mean,nwr}.png
#
# For NWR polar plots on a shared-scale Leaflet map (all four sites):
#   Rscript scripts/polar_map_nwr.R
#   -> output/polar_plots/pm25_nwr_polar_map.html

suppressPackageStartupMessages({
  library(dplyr)
})

bl_find_project_root <- function() {
  candidates <- c(
    Sys.getenv("BL_PROJECT_ROOT", unset = ""),
    getwd(),
    if (basename(getwd()) == "scripts") normalizePath("..", mustWork = FALSE)
  )
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    script_path <- sub("^--file=", "", file_arg[[1]])
    script_dir <- dirname(normalizePath(script_path, mustWork = FALSE))
    candidates <- c(candidates, script_dir, dirname(script_dir))
  }
  for (start in unique(candidates[nzchar(candidates)])) {
    dir <- normalizePath(start, mustWork = FALSE)
    for (i in 1:6) {
      if (file.exists(file.path(dir, "scripts/setup_BL.R"))) {
        return(dir)
      }
      parent <- dirname(dir)
      if (identical(parent, dir)) break
      dir <- parent
    }
  }
  stop("Could not find project root (scripts/setup_BL.R).", call. = FALSE)
}

BL_POLAR_SITE_CODES <- c("CLDP0665", "CLDP0667", "CLDP0668", "CLDP0670")
BL_POLAR_START_DATE <- as.Date("2026-04-01")
BL_POLAR_END_DATE <- as.Date("2026-06-18")
BL_POLAR_WDIR_CSV <- "data/raw/WDIR to 18062026.csv"
BL_POLAR_WSPD_CSV <- "data/raw/WSPD to 18062026.csv"
BL_POLAR_RDATA <- "data/processed/pm25_wd_analysis_14Jun2026.RData"
BL_POLAR_PLOT_DIR <- "output/polar_plots"

bl_read_wind_export <- function(path, value_col) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c("DateTime", "ScaledValue") %in% names(raw))) {
    stop("Unexpected wind CSV columns in ", path, call. = FALSE)
  }
  values <- suppressWarnings(as.numeric(raw$ScaledValue))
  keep <- !is.na(values) & nzchar(trimws(raw$DateTime))
  out <- data.frame(
    date = as.POSIXct(raw$DateTime[keep], tz = "UTC"),
    value = values[keep],
    stringsAsFactors = FALSE
  )
  names(out)[2] <- value_col
  out[order(out$date), , drop = FALSE]
}

bl_load_wind_data <- function(wdir_path, wspd_path) {
  wd <- bl_read_wind_export(wdir_path, "wd")
  ws <- bl_read_wind_export(wspd_path, "ws")
  wind <- dplyr::inner_join(wd, ws, by = "date")
  wind <- wind[!is.na(wind$wd) & !is.na(wind$ws), , drop = FALSE]
  wind <- wind[wind$ws >= 0 & wind$wd >= 0 & wind$wd <= 360, , drop = FALSE]
  wind
}

bl_aggregate_wind_hourly <- function(wind_df) {
  if (!requireNamespace("openair", quietly = TRUE)) {
    stop("Install openair: install.packages('openair')", call. = FALSE)
  }
  openair::timeAverage(
    wind_df,
    avg.time = "hour",
    statistic = "mean",
    data.thresh = 0
  ) %>%
    mutate(date = as.POSIXct(date, tz = "UTC")) %>%
    filter(!is.na(wd), !is.na(ws))
}

bl_fetch_pm25_sites <- function(site_codes, start_api, end_api, clean = TRUE) {
  species <- bl_env("BL_SPECIES_PM25", "IPM25")
  parts <- lapply(site_codes, function(site) {
    message("Fetching PM2.5: ", site)
    bl_fetch_site_species(site, species, "pm25", start_api, end_api)
  })
  pm25 <- bl_bind_site_readings(parts)
  if (!nrow(pm25)) {
    stop("No PM2.5 rows returned from API.", call. = FALSE)
  }
  pm25$date <- as.POSIXct(pm25$date, tz = "UTC")
  if (clean) {
    pm25 <- pm25 %>%
      group_by(SiteCode) %>%
      group_modify(~ bl_clean_pollutant_values(.x, "pm25")) %>%
      ungroup()
  } else {
    pm25$pm25 <- as.numeric(pm25$pm25)
  }
  pm25
}

bl_build_polar_dataset <- function(pm25_df, wind_hourly, site_code, start_date, end_date) {
  site_pm25 <- pm25_df %>%
    filter(SiteCode == site_code, !is.na(pm25)) %>%
    transmute(date = as.POSIXct(date, tz = "UTC"), pm25 = as.numeric(pm25))

  merged <- dplyr::inner_join(site_pm25, wind_hourly, by = "date") %>%
    filter(
      as.Date(date) >= start_date,
      as.Date(date) <= end_date
    ) %>%
    arrange(date)

  merged
}

bl_save_polar_plot <- function(df, site_code, method, outdir) {
  if (!requireNamespace("openair", quietly = TRUE)) {
    stop("Install openair: install.packages('openair')", call. = FALSE)
  }
  if (!nrow(df)) {
    warning("No data to plot for ", site_code, " (", method, ")", call. = FALSE)
    return(invisible(NULL))
  }

  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  fname <- file.path(outdir, paste0("pm25_", site_code, "_", method, ".png"))

  grDevices::png(fname, width = 900, height = 900, res = 120)
  on.exit(grDevices::dev.off(), add = TRUE)

  if (identical(method, "mean")) {
    openair::polarPlot(
      df,
      pollutant = "pm25",
      main = paste0(site_code, " PM2.5 (binned mean, unsmoothed)\n",
                    format(BL_POLAR_START_DATE, "%d %b %Y"), " – ",
                    format(BL_POLAR_END_DATE, "%d %b %Y")),
      statistic = "mean",
      smooth = FALSE
    )
  } else if (identical(method, "nwr")) {
    openair::polarPlot(
      df,
      pollutant = "pm25",
      main = paste0(site_code, " PM2.5 (NWR, default smoothing)\n",
                    format(BL_POLAR_START_DATE, "%d %b %Y"), " – ",
                    format(BL_POLAR_END_DATE, "%d %b %Y"))
    )
  } else {
    stop("Unknown polar plot method: ", method, call. = FALSE)
  }

  message("Saved plot: ", fname)
  invisible(fname)
}

setwd(bl_find_project_root())
source("scripts/setup_BL.R")

if (!requireNamespace("openair", quietly = TRUE)) {
  stop("Install openair: install.packages('openair')", call. = FALSE)
}

message("Polar plot analysis: ", paste(BL_POLAR_SITE_CODES, collapse = ", "))
message(
  "Window: ", format(BL_POLAR_START_DATE, "%Y-%m-%d"),
  " to ", format(BL_POLAR_END_DATE, "%Y-%m-%d")
)

api_range <- bl_quarter_api_range(BL_POLAR_START_DATE, BL_POLAR_END_DATE)

wind_raw <- bl_load_wind_data(BL_POLAR_WDIR_CSV, BL_POLAR_WSPD_CSV)
message(
  "Wind (SS2 module): ", nrow(wind_raw), " sub-hourly rows, ",
  format(min(wind_raw$date), "%Y-%m-%d %H:%M"), " to ",
  format(max(wind_raw$date), "%Y-%m-%d %H:%M")
)

wind_hourly <- bl_aggregate_wind_hourly(wind_raw)
message("Wind hourly: ", nrow(wind_hourly), " rows")

pm25 <- bl_fetch_pm25_sites(
  BL_POLAR_SITE_CODES,
  api_range$start_api,
  api_range$end_api,
  clean = TRUE
)
message(
  "PM2.5 fetched: ", nrow(pm25), " rows across ",
  dplyr::n_distinct(pm25$SiteCode), " site(s)"
)

polar_data <- stats::setNames(
  lapply(BL_POLAR_SITE_CODES, function(sc) {
    bl_build_polar_dataset(pm25, wind_hourly, sc, BL_POLAR_START_DATE, BL_POLAR_END_DATE)
  }),
  BL_POLAR_SITE_CODES
)

for (sc in BL_POLAR_SITE_CODES) {
  n <- nrow(polar_data[[sc]])
  message(sc, ": ", n, " paired hourly row(s) for polar plots")
  bl_save_polar_plot(polar_data[[sc]], sc, "mean", BL_POLAR_PLOT_DIR)
  bl_save_polar_plot(polar_data[[sc]], sc, "nwr", BL_POLAR_PLOT_DIR)
}

analysis_meta <- list(
  site_codes = BL_POLAR_SITE_CODES,
  wind_site_code = "SS2",
  wind_sensor_host = "CLDP0665",
  start_date = BL_POLAR_START_DATE,
  end_date = BL_POLAR_END_DATE,
  wdir_csv = BL_POLAR_WDIR_CSV,
  wspd_csv = BL_POLAR_WSPD_CSV,
  pm25_clean = TRUE,
  wind_aggregation = "hourly mean via openair::timeAverage",
  polar_methods = c("mean" = "statistic='mean', smooth=FALSE",
                    "nwr" = "openair::polarPlot default smoothing")
)
saved_at <- Sys.time()

dir.create(dirname(BL_POLAR_RDATA), recursive = TRUE, showWarnings = FALSE)
save(
  wind_raw,
  wind_hourly,
  pm25,
  polar_data,
  analysis_meta,
  saved_at,
  file = BL_POLAR_RDATA
)
message("Saved RData: ", BL_POLAR_RDATA)
