#!/usr/bin/env Rscript
# Fetch PM2.5 for one or many SiteCodes and plot all series on one chart (grey lines).
#
# Plot analysis uses BL_PLOT_* only (not BL_START_DATE / BL_END_DATE for reports).
# Configure in .env:
#   BL_PLOT_MODE=single|selected|all
#   BL_PLOT_START_DATE / BL_PLOT_END_DATE — leave empty to use each sensor's
#     StartDate and formal EndDate (decommission), not HourlyBulletinEnd
#   BREATHE_API_KEY
#
# Run:
#   Rscript scripts/fetch_sensors.R   # if listSensors.json missing
#   Rscript scripts/generate_plots.R

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

root <- Sys.getenv("BL_PROJECT_ROOT", unset = getwd())
if (basename(root) == "scripts") {
  root <- normalizePath(file.path(root, ".."))
}
setwd(root)

source("scripts/load_env.R", local = TRUE)
source("R/bl_api.R", local = TRUE)
source("R/bl_plot_api.R", local = TRUE)
bl_load_env()

bl_plot_env_flag <- function(key, default = "0") {
  identical(bl_env(key, default), "1")
}

#' Fetch PM2.5 for many sites; resume from partial cache file.
fetch_pm25_all_sites <- function(
    site_codes,
    cache_path,
    start_time = NULL,
    end_time = NULL,
    species = NULL,
    save_every = 10L) {
  # save_every: write cache to disk every N sites (crash-safe), not a site limit
  species <- species %||% bl_env("BL_PLOT_SPECIES", bl_env("BL_SPECIES_PM25", "IPM25"))
  use_global_plot_window <- !bl_plot_dates_unrestricted()
  plot_start_global <- if (use_global_plot_window) {
    bl_resolve_plot_fetch_start()
  } else {
    ""
  }
  plot_end_global <- if (use_global_plot_window) {
    bl_resolve_plot_fetch_end()
  } else {
    ""
  }
  # Unrestricted: per-site StartDate -> formal EndDate (decommission), not bulletin.
  sensors_meta <- if (bl_plot_dates_unrestricted()) {
    bl_sensors_metadata_df()
  } else {
    NULL
  }

  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)

  if (file.exists(cache_path)) {
    existing <- utils::read.csv(cache_path, stringsAsFactors = FALSE)
    existing$date <- as.POSIXct(existing$date, tz = "UTC")
    existing$SiteCode <- as.character(existing$SiteCode)
    completed <- unique(existing$SiteCode)
    message("Resuming: ", length(completed), " sites already in cache")
  } else {
    existing <- data.frame(
      SiteCode = character(),
      date = as.POSIXct(character()),
      pm25 = numeric(),
      stringsAsFactors = FALSE
    )
    completed <- character()
  }

  todo <- setdiff(site_codes, completed)
  if (!length(todo)) {
    message("All ", length(site_codes), " sites already cached")
    return(existing)
  }

  message(
    "Fetching PM2.5 for ", length(todo), " sites (",
    length(site_codes), " total) ..."
  )

  new_rows <- list()
  for (i in seq_along(todo)) {
    site <- todo[[i]]
    message("[", i, "/", length(todo), "] ", site)
    site_start <- if (nzchar(plot_start_global)) {
      plot_start_global
    } else {
      bl_resolve_plot_fetch_start(site, sensors_meta)
    }
    # End: BL_PLOT_END_DATE, else formal EndDate (decommission), not HourlyBulletinEnd.
    site_end <- if (nzchar(plot_end_global)) {
      plot_end_global
    } else {
      bl_resolve_plot_fetch_end(site, sensors_meta)
    }
    chunk <- tryCatch(
      bl_fetch_pm25_site(site, site_start, site_end, species),
      error = function(e) {
        warning("Failed ", site, ": ", conditionMessage(e), call. = FALSE)
        NULL
      }
    )
    if (!is.null(chunk) && nrow(chunk) > 0) {
      new_rows[[site]] <- chunk
    }

    if (i %% save_every == 0L && length(new_rows)) {
      partial <- bind_rows(c(list(existing), new_rows))
      utils::write.csv(partial, cache_path, row.names = FALSE)
      message("  checkpoint: ", nrow(partial), " rows")
    }
  }

  if (length(new_rows)) {
    existing <- bind_rows(c(list(existing), new_rows))
  }

  utils::write.csv(existing, cache_path, row.names = FALSE)
  message("Wrote cache: ", cache_path, " (", nrow(existing), " rows)")
  existing
}

#' Time average with openair (per SiteCode).
aggregate_pm25_openair <- function(df, agg = c("hourly", "daily")) {
  agg <- match.arg(agg)
  if (agg == "hourly") {
    return(df)
  }

  if (!requireNamespace("openair", quietly = TRUE)) {
    stop(
      "Install openair for BL_PLOT_AGG=daily: install.packages('openair')",
      call. = FALSE
    )
  }

  openair::timeAverage(
    df,
    pollutant = "pm25",
    type = "SiteCode",
    avg.time = "day",
    data.thresh = 0
  ) %>%
    mutate(
      SiteCode = as.character(SiteCode),
      date = as.POSIXct(date, tz = "UTC")
    )
}

plot_pm25_all_sites <- function(df, output_path) {
  n_sites <- dplyr::n_distinct(df$SiteCode)
  date_range <- range(df$date, na.rm = TRUE)

  p <- ggplot(df, aes(x = date, y = pm25, group = SiteCode)) +
    geom_line(colour = "grey55", linewidth = 0.25, alpha = 0.35) +
    labs(
      title = "PM2.5 by Breathe London site",
      subtitle = paste(
        n_sites, "sites;",
        format(date_range[1], "%d %b %Y"),
        "to",
        format(date_range[2], "%d %b %Y")
      ),
      x = NULL,
      y = "PM2.5 (ug/m3)"
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.background = element_rect(fill = "white", colour = NA),
      plot.background = element_rect(fill = "white", colour = NA)
    )

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  ggsave(output_path, p, width = 12, height = 6, dpi = 150, bg = "white")
  message("Saved plot: ", output_path)
  invisible(p)
}

# --- Main ---------------------------------------------------------------------
site_codes <- bl_resolve_plot_site_codes()
cache_path <- bl_env("BL_PLOT_CACHE_CSV", "data/processed/pm25_all_sites.csv")
output_path <- bl_env("BL_PLOT_OUTPUT", "output/pm25_all_sites.png")
agg <- tolower(bl_env("BL_PLOT_AGG", "daily"))

mode <- tolower(trimws(bl_env("BL_PLOT_MODE", "single")))
message("Plot fetch window: ", bl_describe_plot_fetch_window())
message("BL_PLOT_MODE=", mode, " → ", length(site_codes), " SiteCode(s)")
if (identical(mode, "all")) {
  message("(BL_PLOT_SITE_CODES ignored — using all sites from listSensors.json)")
}

if (bl_plot_env_flag("BL_PLOT_USE_CACHE") && file.exists(cache_path)) {
  message("BL_PLOT_USE_CACHE=1 — loading ", cache_path)
  pm25_long <- utils::read.csv(cache_path, stringsAsFactors = FALSE)
  pm25_long$date <- as.POSIXct(pm25_long$date, tz = "UTC")
} else {
  pm25_long <- fetch_pm25_all_sites(site_codes, cache_path)
  n_cached <- dplyr::n_distinct(pm25_long$SiteCode)
  message("Cache has data for ", n_cached, " / ", length(site_codes), " sites")
}

if (!nrow(pm25_long)) {
  stop("No PM2.5 data to plot", call. = FALSE)
}

pm25_plot <- aggregate_pm25_openair(pm25_long, agg = agg)
plot_pm25_all_sites(pm25_plot, output_path)
