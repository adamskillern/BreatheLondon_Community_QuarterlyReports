# Find nearest active Breathe London sensor to a target site
# (e.g. for comparison plots)

library(jsonlite)
library(tidyverse)

bl_project_root <- function() {
  candidates <- c(
    Sys.getenv("BL_PROJECT_ROOT", unset = ""),
    getwd(),
    if (basename(getwd()) == "scripts") normalizePath("..", mustWork = FALSE)
  )
  for (root in unique(candidates[nzchar(candidates)])) {
    root <- normalizePath(root, mustWork = FALSE)
    if (file.exists(file.path(root, "R", "bl_api.R"))) {
      return(root)
    }
  }
  stop(
    "Could not find project root (folder with R/bl_api.R). ",
    "setwd() to the repo root or set BL_PROJECT_ROOT.",
    call. = FALSE
  )
}

# Calculate the distance between two points on the Earth's surface
earth_dist_km <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180          # convert degrees → radians (trig functions need radians)
  r <- 6371                # mean Earth radius in km
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  lat1 <- lat1 * rad       # reuse names: now lat1/lat2 are in radians
  lat2 <- lat2 * rad
  # Intermediate term inside the Haversine formula
  h <- sin(dlat / 2)^2 + cos(lat1) * cos(lat2) * sin(dlon / 2)^2
  r * 2 * atan2(sqrt(h), sqrt(1 - h))
}

# Find_nearest_active_site — pick the closest *still running* sensor to target site
find_nearest_active_site <- function(
    site_code = Sys.getenv("BL_SITE_CODE"),  # default: read from .env after load
    sensors_path = "data/raw/listSensors.json", # cached sensor list (run fetch_sensors.R)
    project_root = NULL,
    load_dotenv = TRUE,   # if TRUE, read .env so BL_SITE_CODE is set
    verbose = TRUE) {     # if TRUE, print a short summary to the console

  # "Active" = row in the API list where EndDate is missing (sensor not shut down).
  # Typical use: compare the community node (from .env) to a nearby reference site.
  # Returns a list with:
  #   $target       — metadata row for the BL_SITE_CODE
  #   $nearest      — closest other active site + dist_km column
  #   $active_sites — all active sites with distances (for maps / tables)

  # Remember current folder and restore it when the function exits (even on error)
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)

  if (is.null(project_root)) {
    project_root <- bl_project_root()
  }
  # Relative paths like "data/raw/..." only work from the project root
  setwd(project_root)

  # .env is NOT loaded automatically in R — we must call readRenviron()
  if (load_dotenv && file.exists(".env")) {
    readRenviron(".env")
    if (!nzchar(site_code)) {
      site_code <- Sys.getenv("BL_SITE_CODE")
    }
  }
  if (!nzchar(site_code)) {
    stop("site_code is empty — pass it or set BL_SITE_CODE in .env")
  }

  # JSON file shape: [[ {sensor1}, {sensor2}, ... ]] — [[1]] unwraps the inner list
  sensors <- as.data.frame(fromJSON(sensors_path)[[1]])

  # API uses "" for "still active"; treat empty string as NA for filtering
  sensors$EndDate <- na_if(sensors$EndDate, "")

  # Your report site (one row)
  target <- sensors %>% filter(SiteCode == site_code) %>% slice(1)
  if (nrow(target) == 0) {
    stop("No sensor found for site_code: ", site_code)
  }

  # Single numbers for the target site — earth_dist_km needs length-1 lat0/lon0 here
  lat0 <- as.numeric(target$Latitude[1])
  lon0 <- as.numeric(target$Longitude[1])

  # All other sensors that are still active; compute distance from the target site
  active_sites <- sensors %>%
    filter(is.na(EndDate), SiteCode != site_code) %>%
    mutate(
      dist_km = earth_dist_km(
        lat0, lon0,
        as.numeric(Latitude), as.numeric(Longitude)
      )
    )

  # Smallest distance = nearest neighbour
  nearest <- active_sites %>% arrange(dist_km) %>% slice(1)

  if (verbose) {
    cat("Nearest SiteCode to", site_code, "(active only):", nearest$SiteCode, "\n")
    cat("  At lat/lon:", nearest$Latitude, nearest$Longitude, "\n")
    cat("  Distance (km):", round(nearest$dist_km, 2), "\n")
  }

  list(
    site_code = site_code,
    target = target,
    nearest = nearest,
    active_sites = active_sites
  )
}


# Daily comparison plot — 4 bars per day (reference style: magenta NO2, grey PM2.5)

BL_COL_NO2 <- "#A31D64"
BL_COL_PM25 <- "#9E9E9E"
BL_WHO_NO2 <- 25
BL_WHO_PM25 <- 15

bl_ensure_project_root <- function() {
  root <- bl_project_root()
  setwd(root)
  invisible(root)
}

bl_source_api <- function() {
  bl_ensure_project_root()
  if (!exists("bl_fetch_readings", mode = "function")) {
    source("R/bl_api.R")
  }
  bl_load_env()
  invisible(TRUE)
}

fetch_site_daily_means <- function(site_code, start_time = NULL, end_time = NULL) {
  bl_source_api()
  raw <- bl_fetch_readings(
    site_code = site_code,
    start_time = start_time,
    end_time = end_time
  )
  no2 <- raw$no2 %>%
    mutate(
      day = as.Date(date),
      site = site_code,
      pollutant = "NO2",
      value = as.numeric(no2)
    ) %>%
    group_by(day, site, pollutant) %>%
    summarise(daily_mean = mean(value, na.rm = TRUE), .groups = "drop")

  pm25 <- raw$pm25 %>%
    mutate(
      day = as.Date(date),
      site = site_code,
      pollutant = "PM2.5",
      value = as.numeric(pm25)
    ) %>%
    group_by(day, site, pollutant) %>%
    summarise(daily_mean = mean(value, na.rm = TRUE), .groups = "drop")

  bind_rows(no2, pm25)
}

build_sensor_comparison_daily <- function(
    site_target = "CLDP0299",
    site_nearest = "CLDP0608",
    start_time = NULL,
    end_time = NULL,
    last_n_days = 6L) {
  if (!exists("bl_source_api", mode = "function")) {
    stop(
      "Functions not loaded. From project root run:\n",
      "  source('scripts/closest_sensor_to_target.R')\n",
      "  run_sensor_comparison_plot()",
      call. = FALSE
    )
  }
  bl_source_api()

  if (is.null(start_time) || is.null(end_time)) {
    end_day <- bl_env_report_dates()$quarter_end
    start_day <- end_day - as.integer(last_n_days) + 1L
    start_time <- bl_to_api_gmt_string(
      paste(format(start_day, "%d %b %Y"), "00:00:00 GMT")
    )
    end_time <- bl_to_api_gmt_string(
      paste(format(end_day, "%d %b %Y"), "23:00:00 GMT")
    )
  }

  combined <- bind_rows(
    fetch_site_daily_means(site_target, start_time, end_time),
    fetch_site_daily_means(site_nearest, start_time, end_time)
  )

  days_keep <- combined %>%
    distinct(day) %>%
    arrange(day) %>%
    slice_tail(n = last_n_days) %>%
    pull(day)

  series_levels <- c(
    paste("PM2.5", site_target, sep = " · "),
    paste("NO2", site_target, sep = " · "),
    paste("PM2.5", site_nearest, sep = " · "),
    paste("NO2", site_nearest, sep = " · ")
  )

  combined %>%
    filter(day %in% days_keep) %>%
    mutate(
      series = paste(pollutant, site, sep = " · "),
      series = factor(series, levels = series_levels),
      day_label = format(day, "%b %d"),
      day_label = factor(day_label, levels = unique(day_label[order(day)]))
    )
}

#' Bar width (x) → cap radius (y) so the semicircle looks as wide as the bar on screen.
pill_cap_radius_y <- function(w, value, n_x, y_upper, fig_width = 10, fig_height = 5) {
  r_y <- w * fig_width * y_upper / (n_x * fig_height)
  min(r_y, value / 2, value)
}

#' Pill bar: flat base + semicircular top (radius scaled to match bar width visually).
pill_bar_polygon <- function(
    x, w, value,
    n_x, y_upper,
    n_arc = 48,
    fig_width = 10,
    fig_height = 5) {
  if (!is.finite(value) || value <= 0) {
    return(NULL)
  }

  xc <- x
  r_x <- w / 2
  r_y <- pill_cap_radius_y(w, value, n_x, y_upper, fig_width, fig_height)

  # Short bar: semicircle dome on baseline
  if (value <= 2 * r_y) {
    r_y <- value / 2
    t <- seq(pi, 0, length.out = n_arc)
    return(data.frame(
      x = xc + r_x * cos(t),
      y = r_y + r_y * sin(t)
    ))
  }

  y_rect_top <- value - r_y
  t_top <- seq(pi, 0, length.out = n_arc)
  arc_top <- data.frame(
    x = xc + r_x * cos(t_top),
    y = y_rect_top + r_y * sin(t_top)
  )

  rbind(
    data.frame(x = xc - r_x, y = 0),
    data.frame(x = xc - r_x, y = y_rect_top),
    arc_top,
    data.frame(x = xc + r_x, y = 0)
  )
}

plot_df_to_pill_bars <- function(
    plot_df,
    dodge_w = 0.88,
    fig_width = 10,
    fig_height = 5) {
  n_series <- length(levels(plot_df$series))
  bar_w <- dodge_w / n_series
  n_x <- length(unique(plot_df$day_label))
  y_upper <- max(c(plot_df$daily_mean, BL_WHO_NO2, BL_WHO_PM25), na.rm = TRUE) * 1.08

  bars <- plot_df %>%
    mutate(
      x_num = as.numeric(day_label),
      series_i = as.integer(series),
      x = x_num + (series_i - (n_series + 1) / 2) * bar_w,
      w = bar_w,
      value = daily_mean,
      bar_id = interaction(day_label, series, drop = TRUE)
    )

  polys <- lapply(seq_len(nrow(bars)), function(i) {
    row <- bars[i, ]
    pts <- pill_bar_polygon(
      row$x, row$w, row$value,
      n_x = n_x,
      y_upper = y_upper,
      fig_width = fig_width,
      fig_height = fig_height
    )
    if (is.null(pts)) {
      return(NULL)
    }
    cbind(pts, bar_id = row$bar_id, series = as.character(row$series))
  })

  bind_rows(polys)
}

plot_sensor_comparison_daily <- function(plot_df) {
  fill_cols <- setNames(
    c(BL_COL_PM25, BL_COL_NO2, "#5A9A68", "#3D6EB5"),
    levels(plot_df$series)
  )

  dodge_w <- 0.88
  fig_width <- 10
  fig_height <- 5
  pill_df <- plot_df_to_pill_bars(
    plot_df,
    dodge_w = dodge_w,
    fig_width = fig_width,
    fig_height = fig_height
  )
  pill_df$series <- factor(pill_df$series, levels = levels(plot_df$series))

  ggplot() +
    geom_polygon(
      data = pill_df,
      aes(x = x, y = y, group = bar_id, fill = series),
      colour = NA,
      alpha = 0.95
    ) +
    scale_x_continuous(
      breaks = sort(unique(as.numeric(plot_df$day_label))),
      labels = levels(plot_df$day_label)
    ) +
    geom_hline(
      yintercept = BL_WHO_NO2,
      linetype = "dashed",
      colour = "grey55",
      linewidth = 0.4
    ) +
    annotate(
      "text",
      x = 0.6,
      y = BL_WHO_NO2,
      label = "WHO Guidelines NO\u2082 25 \u03bcg/m\u00b3",
      hjust = 0,
      vjust = -0.3,
      colour = BL_COL_NO2,
      size = 3.2
    ) +
    geom_hline(
      yintercept = BL_WHO_PM25,
      linetype = "dashed",
      colour = "grey55",
      linewidth = 0.4
    ) +
    annotate(
      "text",
      x = 0.6,
      y = BL_WHO_PM25,
      label = "PM2.5 15 \u03bcg/m\u00b3",
      hjust = 0,
      vjust = -0.3,
      colour = BL_COL_PM25,
      size = 3.2
    ) +
    scale_fill_manual(values = fill_cols, name = NULL) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
    labs(x = NULL, y = NULL) +
    theme_minimal(base_size = 11) +
    theme(
      panel.background = element_rect(fill = "white", colour = NA),
      plot.background = element_rect(fill = "white", colour = NA),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(),
      legend.position = "top",
      legend.text = element_text(size = 9),
      axis.text.x = element_text(colour = "grey40"),
      axis.text.y = element_blank(),
      axis.title = element_blank(),
      axis.ticks.y = element_blank()
    )
}

#' Run full pipeline: nearest site lookup, daily data, grouped bar plot.
run_sensor_comparison_plot <- function(
    site_target = NULL,
    site_nearest = NULL,
    last_n_days = 6L,
    save_png = TRUE,
    verbose = TRUE) {
  result <- find_nearest_active_site(verbose = verbose)
  if (is.null(site_target)) {
    site_target <- result$target$SiteCode[1]
  }
  if (is.null(site_nearest)) {
    site_nearest <- result$nearest$SiteCode[1]
  }

  comparison_daily_df <- build_sensor_comparison_daily(
    site_target = site_target,
    site_nearest = site_nearest,
    last_n_days = last_n_days
  )
  sensor_comparison_daily_plot <- plot_sensor_comparison_daily(comparison_daily_df)

  if (save_png) {
    dir.create("output", showWarnings = FALSE)
    ggsave(
      "output/sensor_comparison_daily.png",
      sensor_comparison_daily_plot,
      width = 10,
      height = 5,
      dpi = 150,
      bg = "white"
    )
    message("Saved output/sensor_comparison_daily.png")
  }

  list(
    result = result,
    comparison_daily_df = comparison_daily_df,
    plot = sensor_comparison_daily_plot
  )
}

# Rscript scripts/closest_sensor_to_target.R  → runs pipeline
# R console: source("scripts/closest_sensor_to_target.R"); run_sensor_comparison_plot()
if (!interactive()) {
  run_sensor_comparison_plot()
}
