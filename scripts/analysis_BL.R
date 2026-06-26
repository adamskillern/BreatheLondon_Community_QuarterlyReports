# Interactive analysis workspace: community node(s) + Marylebone Road (MY1).
#
# R console (from anywhere under Desktop/Code):
#   source("BreatheLondon_Community_QuarterlyReports/scripts/analysis_BL.R")
#
# Terminal (from project root):
#   Rscript scripts/analysis_BL.R
#
# Sites come from BL_REPORT_SITE_CODES (or BL_SITE_CODE) in .env.
# Node data respects BL_DATA_SOURCE (api or csv). Marylebone uses RData cache when present.
# QA default: raw API values (no rounding, zeros kept). Reports still use cleaned data.
library(dplyr)


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
  ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(ofile) && nzchar(ofile)) {
    script_dir <- dirname(normalizePath(ofile, mustWork = FALSE))
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
  stop(
    "Could not find project root (scripts/setup_BL.R).\n",
    "  setwd() to the repo or set BL_PROJECT_ROOT.",
    call. = FALSE
  )
}

setwd(bl_find_project_root())
source("scripts/setup_BL.R")
# Re-source so an open R session always picks up bl_load_report_data(..., clean =).
source("R/bl_api.R")
source("R/bl_marylebone.R")
bl_load_env()

bl_ensure_analysis_api <- function() {
  if (!"clean" %in% names(formals(bl_load_report_data))) {
    source("R/bl_api.R")
  }
  if (!"clean" %in% names(formals(bl_load_marylebone_hourly))) {
    source("R/bl_marylebone.R")
  }
}

get_marylebone_openair <- function(
    json_path = "data/raw/listSensors.json") {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite: install.packages('jsonlite')", call. = FALSE)
  }
  sensors <- jsonlite::fromJSON(json_path, simplifyVector = TRUE)[[1]]
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


bl_load_analysis_data <- function(site_codes = NULL, raw = TRUE) {
  # Load node + Marylebone data for sites in .env (BL_REPORT_SITE_CODES or BL_SITE_CODE).
  # raw = TRUE (default): unrounded ScaledValue from API; zeros kept as 0 (not NA).
  # raw = FALSE: same cleaning as quarterly reports (round to whole µg/m³, 0 → NA).
  # Note: BL_DATA_SOURCE=csv reads files as stored — re-fetch via API for true raw values.
  bl_ensure_analysis_api()
  if (is.null(site_codes)) {
    site_codes <- bl_resolve_report_site_codes()
  }
  clean <- !raw
  if (raw) {
    message("QA mode: raw values (no rounding, zeros retained)")
  }
  message("Loading ", length(site_codes), " site(s): ", paste(site_codes, collapse = ", "))

  nodes <- stats::setNames(
    lapply(site_codes, function(sc) {
      bl_use_site_code(sc)
      bl_load_report_data(site_code = sc, clean = clean)
    }),
    site_codes
  )

  site_code <- site_codes[[1]]
  no2_df <- nodes[[site_code]]$no2
  pm25_df <- nodes[[site_code]]$pm25
  marylebone_df <- bl_load_marylebone_hourly(clean = clean)

  message(
    "Ready — site_code: ", site_code,
    " | no2: ", nrow(no2_df), " rows | pm25: ", nrow(pm25_df),
    " rows | marylebone: ", nrow(marylebone_df), " rows"
  )

  list(
    site_codes = site_codes,
    site_code = site_code,
    nodes = nodes,
    no2_df = no2_df,
    pm25_df = pm25_df,
    marylebone_df = marylebone_df
  )
}

bl_analysis <- bl_load_analysis_data(raw = TRUE)
site_codes <- bl_analysis$site_codes
site_code <- bl_analysis$site_code
nodes <- bl_analysis$nodes
no2_df <- bl_analysis$no2_df
pm25_df <- bl_analysis$pm25_df
marylebone_df <- bl_analysis$marylebone_df

# for (d in date_vector) strips Date to numeric; always index dates[i] instead.
bl_add_date_only <- function(df) {
  if ("date_only" %in% colnames(df)) {
    df$date_only <- as.Date(df$date_only)
    return(df)
  }
  if (inherits(df$date, "Date")) {
    df$date_only <- df$date
  } else {
    df$date_only <- as.Date(as.POSIXct(df$date, tz = "UTC"))
  }
  df
}

bl_format_plot_day <- function(d) {
  format(as.Date(d), "%Y-%m-%d")
}

plot_daily_non_positive_conc <- function(df, pollutant, site_code, outdir = NULL, n_max = 100) {
  #' Plot daily values with non-positive (<= 0) points highlighted, for a pollutant data frame
  #'
  #' @param df      Data frame with at least columns: date (POSIXct or character), and pollutant (e.g. pm25, no2)
  #' @param pollutant   Name of pollutant column as string ("pm25" or "no2")
  #' @param site_code   Sensor/site code, used in plot titles and filenames
  #' @param outdir      Output directory for plots (default: "output/[pollutant]_daily_plots")
  #' @param n_max       Maximum days to plot (default: 100)
  #'
  #' # Example usage for PM2.5:
  #' plot_daily_nonpos_pollutant(pm25_df, "pm25", site_code)
  #'
  #' # Example usage for NO2:
  #' plot_daily_nonpos_pollutant(no2_df, "no2", site_code)
  
  library(ggplot2)

  sum(df[[pollutant]] <= 0, na.rm = TRUE)
  sum(is.na(df[[pollutant]]))


  if (is.null(outdir)) {
    outdir <- file.path("output", paste0(pollutant, "_daily_plots"))
  }
  if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

  df <- bl_add_date_only(df)

  # Get all dates where at least one value is <= 0 (ignoring NAs)
  zero_days <- unique(df$date_only[!is.na(df[[pollutant]]) & df[[pollutant]] <= 0])
  zero_days <- sort(zero_days)

  message("Plotting ", pollutant, " at ", site_code, ": ", length(zero_days),
          " day(s) with at least one ", pollutant, " <= 0 (excluding NAs)...")

  # For each such day (up to n_max), plot all records for that date
  first_days <- head(zero_days, n_max)
  plotted <- character()

  for (i in seq_along(first_days)) {
    d <- first_days[i]
    d_label <- bl_format_plot_day(d)
    day_full <- df[df$date_only == d, , drop = FALSE]

    # Only plot if there is at least one value with pollutant <= 0 (and not NA)
    has_nonpos <- any(!is.na(day_full[[pollutant]]) & day_full[[pollutant]] <= 0)
    if (has_nonpos) {
      # Use only non-NA values for the pollutant
      plot_data <- day_full[!is.na(day_full[[pollutant]]), , drop = FALSE]
      if (nrow(plot_data) > 0) {
        # Mark points where pollutant <= 0 for highlighting
        plot_data$zero_flag <- plot_data[[pollutant]] <= 0

        pollutant_y <- paste0(toupper(pollutant), " (µg/m³)")
        p <- ggplot(plot_data, aes(x = as.POSIXct(date), y = .data[[pollutant]])) +
          geom_line() +
          geom_point(data = plot_data[!plot_data$zero_flag, ],
                     aes(x = as.POSIXct(date), y = .data[[pollutant]]),
                     color = "black", size = 2) +
          geom_point(data = plot_data[plot_data$zero_flag, ],
                     aes(x = as.POSIXct(date), y = .data[[pollutant]]),
                     color = "red", size = 3) +
          labs(
            title = paste0(toupper(pollutant), " for ", d_label, " at ", site_code),
            x = "Time",
            y = pollutant_y
          ) +
          scale_y_continuous(limits = c(0, NA)) +
          theme_minimal()
        fname <- file.path(outdir, paste0(pollutant, "_", site_code, "_", d_label, ".png"))
        ggsave(fname, p, width = 8, height = 5)
        plotted <- c(plotted, fname)
      }
    }
  }

  message("Saved ", length(plotted), " plot(s) to ", outdir)
  invisible(plotted)
}

plot_daily_non_positive_conc_all <- function(
    nodes,
    pollutant,
    site_codes = NULL,
    outdir = NULL,
    n_max = 100) {
  #' Run plot_daily_non_positive_conc() for every site in nodes / site_codes.
  if (is.null(site_codes)) {
    site_codes <- names(nodes)
  }
  all_plotted <- character()
  for (sc in site_codes) {
    site_outdir <- if (is.null(outdir)) {
      file.path("output", paste0(pollutant, "_daily_plots"), sc)
    } else {
      file.path(outdir, sc)
    }
    paths <- plot_daily_non_positive_conc(
      nodes[[sc]][[pollutant]],
      pollutant,
      sc,
      outdir = site_outdir,
      n_max = n_max
    )
    all_plotted <- c(all_plotted, paths)
  }
  invisible(all_plotted)
}

# Mark rows that belong to a run of min_repeat+ consecutive hourly readings
# with the same value (1-hour steps; a gap or value change breaks the run).
bl_flag_consecutive_identical_hours <- function(
    datetimes,
    values,
    min_repeat = 3L) {
  flagged <- rep(FALSE, length(values))
  if (length(values) < min_repeat) {
    return(flagged)
  }

  ord <- order(datetimes)
  dt <- datetimes[ord]
  val <- values[ord]
  n <- length(val)
  run_flag_ord <- rep(FALSE, n)

  i <- 1L
  while (i <= n) {
    if (is.na(val[i])) {
      i <- i + 1L
      next
    }
    j <- i
    while (j < n && !is.na(val[j + 1L])) {
      hour_gap <- as.numeric(difftime(dt[j + 1L], dt[j], units = "hours"))
      if (hour_gap != 1 || val[j + 1L] != val[j]) {
        break
      }
      j <- j + 1L
    }
    if (j - i + 1L >= min_repeat) {
      run_flag_ord[i:j] <- TRUE
    }
    i <- j + 1L
  }

  flagged[ord] <- run_flag_ord
  flagged
}

bl_summarize_consecutive_repeat_runs <- function(datetimes, values, flagged) {
  if (!any(flagged)) {
    return("")
  }
  ord <- order(datetimes)
  dt <- datetimes[ord]
  val <- values[ord]
  flg <- flagged[ord]
  runs <- character()
  i <- 1L
  n <- length(flg)
  while (i <= n) {
    if (!flg[i]) {
      i <- i + 1L
      next
    }
    j <- i
    while (j < n && flg[j + 1L]) {
      j <- j + 1L
    }
    runs <- c(
      runs,
      paste0(
        val[i], " for ", j - i + 1L, "h from ",
        format(dt[i], "%H:%M")
      )
    )
    i <- j + 1L
  }
  paste(runs, collapse = "; ")
}

plot_daily_repeated_conc <- function(
    df,
    pollutant,
    site_code,
    outdir = NULL,
    n_max = 100,
    min_repeat = 3) {
  #' Plot days with min_repeat+ consecutive hourly readings at the same value.
  #' Only those consecutive hours are highlighted in red.
  #'
  #' @param df          Data frame with date and pollutant columns
  #' @param pollutant   Column name, e.g. "no2" or "pm25"
  #' @param site_code   Sensor code for titles and filenames
  #' @param outdir      Output folder (default: output/[pollutant]_repeat_daily_plots)
  #' @param n_max       Maximum number of flagged days to plot
  #' @param min_repeat  Minimum consecutive identical hourly values (default: 3)
  #'
  #' # Example:
  #' plot_daily_repeated_conc(no2_df, "no2", site_code)
  #' plot_daily_repeated_conc(pm25_df, "pm25", site_code, min_repeat = 3)

  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Install ggplot2: install.packages('ggplot2')", call. = FALSE)
  }

  if (is.null(outdir)) {
    outdir <- file.path("output", paste0(pollutant, "_repeat_daily_plots"))
  }
  if (!dir.exists(outdir)) {
    dir.create(outdir, recursive = TRUE)
  }

  df <- bl_add_date_only(df)

  valid <- !is.na(df[[pollutant]]) & !is.na(df$date_only)
  if (!any(valid)) {
    message("No non-NA ", pollutant, " values to check for repeats.")
    return(invisible(character()))
  }

  all_days <- sort(unique(df$date_only[valid]))
  repeat_days <- as.Date(character(), origin = "1970-01-01")
  for (i in seq_along(all_days)) {
    d <- all_days[i]
    day_vals <- df[df$date_only == d & !is.na(df[[pollutant]]), , drop = FALSE]
    if (nrow(day_vals) < min_repeat) next
    flagged <- bl_flag_consecutive_identical_hours(
      as.POSIXct(day_vals$date, tz = "UTC"),
      day_vals[[pollutant]],
      min_repeat = min_repeat
    )
    if (any(flagged)) {
      repeat_days <- c(repeat_days, d)
    }
  }

  message(
    "Plotting ", pollutant, " at ", site_code, ": ", length(repeat_days),
    " day(s) with ", min_repeat, "+ consecutive identical hourly values..."
  )

  plotted <- character()
  days_to_plot <- head(repeat_days, n_max)
  for (i in seq_along(days_to_plot)) {
    d <- days_to_plot[i]
    d_label <- bl_format_plot_day(d)
    day_full <- df[df$date_only == d, , drop = FALSE]
    plot_data <- day_full[!is.na(day_full[[pollutant]]), , drop = FALSE]
    if (nrow(plot_data) < min_repeat) next

    plot_data <- plot_data[order(as.POSIXct(plot_data$date, tz = "UTC")), , drop = FALSE]
    plot_data$repeat_flag <- bl_flag_consecutive_identical_hours(
      as.POSIXct(plot_data$date, tz = "UTC"),
      plot_data[[pollutant]],
      min_repeat = min_repeat
    )
    if (!any(plot_data$repeat_flag)) next

    pollutant_y <- paste0(toupper(pollutant), " (µg/m³)")
    repeat_summary <- bl_summarize_consecutive_repeat_runs(
      as.POSIXct(plot_data$date, tz = "UTC"),
      plot_data[[pollutant]],
      plot_data$repeat_flag
    )

    repeat_pts <- plot_data[plot_data$repeat_flag, , drop = FALSE]
    repeat_zero <- repeat_pts[repeat_pts[[pollutant]] == 0, , drop = FALSE]
    repeat_nonzero <- repeat_pts[repeat_pts[[pollutant]] != 0, , drop = FALSE]

    p <- ggplot2::ggplot(
      plot_data,
      ggplot2::aes(x = as.POSIXct(date), y = .data[[pollutant]])
    ) +
      ggplot2::geom_line() +
      ggplot2::geom_point(
        data = plot_data[!plot_data$repeat_flag, , drop = FALSE],
        ggplot2::aes(x = as.POSIXct(date), y = .data[[pollutant]]),
        color = "black",
        size = 2
      ) +
      ggplot2::geom_point(
        data = repeat_nonzero,
        ggplot2::aes(x = as.POSIXct(date), y = .data[[pollutant]]),
        color = "red",
        size = 3
      ) +
      ggplot2::geom_point(
        data = repeat_zero,
        ggplot2::aes(x = as.POSIXct(date), y = .data[[pollutant]]),
        color = "red",
        shape = 1,
        size = 3,
        stroke = 1.2
      ) +
      ggplot2::labs(
        title = paste0(
          toupper(pollutant), " for ", d_label, " at ", site_code,
          " (", min_repeat, "+ consecutive identical hours)"
        ),
        subtitle = paste0("Consecutive runs: ", repeat_summary),
        x = "Time",
        y = pollutant_y
      ) +
      ggplot2::scale_y_continuous(limits = c(0, NA)) +
      ggplot2::theme_minimal()

    fname <- file.path(
      outdir,
      paste0(pollutant, "_repeat_", site_code, "_", d_label, ".png")
    )
    ggplot2::ggsave(fname, p, width = 8, height = 5)
    plotted <- c(plotted, fname)
  }

  message("Saved ", length(plotted), " plot(s) to ", outdir)
  invisible(plotted)
}

plot_daily_repeated_conc_all <- function(
    nodes,
    pollutant,
    site_codes = NULL,
    outdir = NULL,
    n_max = 100,
    min_repeat = 3) {
  #' Run plot_daily_repeated_conc() for every site in nodes / site_codes.
  if (is.null(site_codes)) {
    site_codes <- names(nodes)
  }
  all_plotted <- character()
  for (sc in site_codes) {
    site_outdir <- if (is.null(outdir)) {
      file.path("output", paste0(pollutant, "_repeat_daily_plots"), sc)
    } else {
      file.path(outdir, sc)
    }
    paths <- plot_daily_repeated_conc(
      nodes[[sc]][[pollutant]],
      pollutant,
      sc,
      outdir = site_outdir,
      n_max = n_max,
      min_repeat = min_repeat
    )
    all_plotted <- c(all_plotted, paths)
  }
  invisible(all_plotted)
}

# All sites (uses nodes + site_codes from bl_load_analysis_data):
# plot_daily_non_positive_conc_all(nodes, "no2", site_codes)
# plot_daily_non_positive_conc_all(nodes, "pm25", site_codes)
# plot_daily_repeated_conc_all(nodes, "no2", site_codes)
# plot_daily_repeated_conc_all(nodes, "pm25", site_codes)

# ---- Compare CLDP0391 API data with the website CSV export ----

# API data for CLDP0391 (date is a character string in UTC, e.g. "2023-01-27 19:00:00")
df_cldp0391_no2 <- nodes[["CLDP0391"]]$no2
df_cldp0391_pm25 <- nodes[["CLDP0391"]]$pm25
df_cldp0391_no2$date <- as.POSIXct(df_cldp0391_no2$date, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
df_cldp0391_pm25$date <- as.POSIXct(df_cldp0391_pm25$date, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")

df_cldp0391_no2$no2 <- round(df_cldp0391_no2$no2, 2)
df_cldp0391_pm25$pm25 <- round(df_cldp0391_pm25$pm25, 2)


# Website CSVs (date like "28/1/2023 0:00", recorded in Europe/London → convert to UTC)
read_website_csv <- function(path, value_col) {
  raw <- read.csv(path, stringsAsFactors = FALSE)
  colnames(raw) <- c("date", value_col)
  london <- as.POSIXct(raw$date, format = "%d/%m/%Y %H:%M", tz = "Europe/London")
  raw$date <- lubridate::with_tz(london, "UTC")
  raw[[value_col]] <- as.numeric(raw[[value_col]])
  raw
}

df_no2_from_website <- read_website_csv(
  "data/raw/from website - Breathe London - Clean Air for Southall and Hayes (CASH) - NO2.csv",
  "no2"
)
df_pm25_from_website <- read_website_csv(
  "data/raw/from website - Breathe London - Clean Air for Southall and Hayes (CASH) - PM2.5.csv",
  "pm25"
)

# Truncate to the date range present in all four data frames
common_start <- max(
  min(df_cldp0391_no2$date), min(df_cldp0391_pm25$date),
  min(df_no2_from_website$date), min(df_pm25_from_website$date)
)
common_end <- min(
  max(df_cldp0391_no2$date), max(df_cldp0391_pm25$date),
  max(df_no2_from_website$date), max(df_pm25_from_website$date)
)

truncate_to_window <- function(df) {
  df[df$date >= common_start & df$date <= common_end, , drop = FALSE]
}
df_cldp0391_no2 <- truncate_to_window(df_cldp0391_no2)
df_cldp0391_pm25 <- truncate_to_window(df_cldp0391_pm25)
df_no2_from_website <- truncate_to_window(df_no2_from_website)
df_pm25_from_website <- truncate_to_window(df_pm25_from_website)

# Inner join on date — only rows where both sides have non-NA concentrations
if (!requireNamespace("dplyr", quietly = TRUE)) {
  stop("Install dplyr: install.packages('dplyr')", call. = FALSE)
}

# One row per hour (drop duplicate timestamps if present)
dedupe_hour <- function(df) {
  dplyr::distinct(df, date, .keep_all = TRUE)
}

cmp_no2 <- dplyr::inner_join(
  dedupe_hour(dplyr::filter(df_cldp0391_no2, !is.na(no2))) |>
    dplyr::rename(no2_api = no2),
  dedupe_hour(dplyr::filter(df_no2_from_website, !is.na(no2))) |>
    dplyr::rename(no2_web = no2),
  by = "date"
) |>
  dplyr::mutate(no2_diff = no2_api - no2_web)

cmp_pm25 <- dplyr::inner_join(
  dedupe_hour(dplyr::filter(df_cldp0391_pm25, !is.na(pm25))) |>
    dplyr::rename(pm25_api = pm25),
  dedupe_hour(dplyr::filter(df_pm25_from_website, !is.na(pm25))) |>
    dplyr::rename(pm25_web = pm25),
  by = "date"
) |>
  dplyr::mutate(pm25_diff = pm25_api - pm25_web)

# All four pollutants on the same timestamp (non-NA in every column)
cmp_all <- dplyr::inner_join(cmp_no2, cmp_pm25, by = "date")

message(
  "Inner join (non-NA only) — NO2: ", nrow(cmp_no2),
  " | PM2.5: ", nrow(cmp_pm25),
  " | all four: ", nrow(cmp_all)
)
message(
  "NO2 diff: n_nonzero=", sum(cmp_no2$no2_diff != 0, na.rm = TRUE),
  " max_abs=", round(max(abs(cmp_no2$no2_diff), na.rm = TRUE), 3)
)
message(
  "PM2.5 diff: n_nonzero=", sum(cmp_pm25$pm25_diff != 0, na.rm = TRUE),
  " max_abs=", round(max(abs(cmp_pm25$pm25_diff), na.rm = TRUE), 3)
)

head(cmp_no2, 3)
head(cmp_pm25, 3)
head(cmp_all, 3)

sum(cmp_no2$no2_diff, na.rm = TRUE)
sum(cmp_pm25$pm25_diff, na.rm = TRUE)

# ---- Timestamp integrity QA ----
# See docs/data_quality_checks.md §4
# Checks: duplicate timestamps, backwards-in-time, irregular spacing, missing hours.

flag_timestamp_integrity <- function(
    df,
    pollutant,
    site_code,
    source) {
  empty <- tibble::tibble(
    date = as.POSIXct(character(), tz = "UTC"),
    site_code = character(),
    pollutant = character(),
    source = character(),
    check_name = character(),
    severity = character(),
    value = numeric(),
    detail = character()
  )
  if (!nrow(df) || !"date" %in% names(df)) {
    return(empty)
  }

  df <- df[order(df$date), , drop = FALSE]
  dates <- df$date
  values <- if (pollutant %in% names(df)) df[[pollutant]] else rep(NA_real_, nrow(df))
  flags <- list()
  add_flag <- function(idx, check_name, severity, detail) {
    flags[[length(flags) + 1L]] <<- tibble::tibble(
      date = dates[idx],
      site_code = site_code,
      pollutant = pollutant,
      source = source,
      check_name = check_name,
      severity = severity,
      value = values[idx],
      detail = detail
    )
  }

  dup_mask <- duplicated(dates) | duplicated(dates, fromLast = TRUE)
  if (any(dup_mask)) {
    dup_dates <- unique(dates[dup_mask])
    for (dt in dup_dates) {
      idx <- which(dates == dt)
      n <- length(idx)
      for (i in idx) {
        add_flag(
          i, "duplicate_timestamp", "fail",
          paste0(n, " row(s) at this timestamp")
        )
      }
    }
  }

  if (length(dates) > 1L) {
    gap_secs <- as.numeric(difftime(dates[-1L], dates[-length(dates)], units = "secs"))
    bad_order <- which(gap_secs < 0) + 1L
    for (i in bad_order) {
      add_flag(
        i, "out_of_order", "fail",
        paste0(
          "Timestamp goes backwards: ",
          format(dates[i], "%Y-%m-%d %H:%M:%S UTC"),
          " is before previous row ",
          format(dates[i - 1L], "%Y-%m-%d %H:%M:%S UTC")
        )
      )
    }
  }

  if (length(dates) > 1L) {
    gap_hours <- as.numeric(difftime(dates[-1L], dates[-length(dates)], units = "hours"))
    irregular <- which(abs(gap_hours - 1) > 1e-9 & abs(gap_hours) > 1e-9)
    for (j in irregular) {
      add_flag(
        j + 1L, "irregular_spacing", "warn",
        paste0(
          round(gap_hours[j], 2), " h since previous row (expected 1 h); ",
          format(dates[j], "%Y-%m-%d %H:%M:%S UTC"), " → ",
          format(dates[j + 1L], "%Y-%m-%d %H:%M:%S UTC")
        )
      )
    }
  }

  if (!length(flags)) {
    return(empty)
  }
  dplyr::bind_rows(flags)
}

run_timestamp_integrity_checks <- function(datasets, site_code) {
  out <- lapply(datasets, function(d) {
    flag_timestamp_integrity(d$df, d$pollutant, site_code, d$source)
  })
  dplyr::bind_rows(out)
}

summarize_timestamp_flags <- function(flags) {
  if (!nrow(flags)) {
    message("Timestamp integrity: no issues found.")
    return(invisible(tibble::tibble()))
  }
  summary <- flags |>
    dplyr::count(source, pollutant, check_name, severity, name = "n_flags") |>
    dplyr::arrange(source, pollutant, check_name)
  print(summary)
  invisible(summary)
}

list_timestamp_issues <- function(flags) {
  if (!nrow(flags)) {
    return(list())
  }
  flags <- flags |>
    dplyr::mutate(date_chr = format(date, "%Y-%m-%d %H:%M:%S UTC"))
  groups <- flags |>
    dplyr::group_by(source, pollutant, check_name, severity) |>
    dplyr::summarise(
      dates = list(sort(unique(date))),
      date_labels = list(sort(unique(date_chr))),
      n = dplyr::n(),
      details = list(unique(detail)),
      rows = list(dplyr::pick(dplyr::everything())),
      .groups = "drop"
    )
  out <- list()
  for (i in seq_len(nrow(groups))) {
    src <- groups$source[i]
    pol <- groups$pollutant[i]
    chk <- groups$check_name[i]
    if (is.null(out[[src]])) out[[src]] <- list()
    if (is.null(out[[src]][[pol]])) out[[src]][[pol]] <- list()
    out[[src]][[pol]][[chk]] <- list(
      severity = groups$severity[i],
      n = groups$n[i],
      dates = groups$dates[[i]],
      date_labels = groups$date_labels[[i]],
      details = groups$details[[i]],
      rows = groups$rows[[i]]
    )
  }
  out
}

print_timestamp_issues <- function(issues, max_dates = 10L) {
  if (!length(issues)) {
    message("No timestamp integrity issues.")
    return(invisible(NULL))
  }
  for (src in names(issues)) {
    cat("\n=== ", toupper(src), " ===\n", sep = "")
    for (pol in names(issues[[src]])) {
      cat("\n", toupper(pol), ":\n", sep = "")
      checks <- issues[[src]][[pol]]
      for (chk in names(checks)) {
        item <- checks[[chk]]
        cat(
          "  [", item$severity, "] ", chk,
          " (n=", item$n, ")\n", sep = ""
        )
        n_show <- min(length(item$date_labels), max_dates)
        if (n_show > 0) {
          cat("    dates:", paste(item$date_labels[seq_len(n_show)], collapse = ", "))
          if (length(item$date_labels) > max_dates) {
            cat(" ... +", length(item$date_labels) - max_dates, " more")
          }
          cat("\n")
        }
        if (length(item$details) && chk != "duplicate_timestamp") {
          cat("    e.g. ", item$details[[1]], "\n", sep = "")
        }
      }
    }
  }
  invisible(NULL)
}

describe_timestamp_coverage <- function(df, value_col, label, hourly_grid) {
  missing_timestamps <- sum(!hourly_grid %in% df$date)
  na_values <- sum(is.na(df[[value_col]]))
  message(
    label, ": ", nrow(df), " rows | ",
    missing_timestamps, " timestamps absent from grid | ",
    na_values, " NA concentration(s)"
  )
  invisible(data.frame(
    source = label,
    rows = nrow(df),
    missing_timestamps = missing_timestamps,
    na_values = na_values
  ))
}

# --- Run checks on CLDP0391 API vs website (truncated window) ---
hourly_grid <- seq(common_start, common_end, by = "hour")
message("Full hourly grid in window: ", length(hourly_grid), " timestamps")
coverage_summary <- rbind(
  describe_timestamp_coverage(df_cldp0391_no2, "no2", "API NO2", hourly_grid),
  describe_timestamp_coverage(df_cldp0391_pm25, "pm25", "API PM2.5", hourly_grid),
  describe_timestamp_coverage(df_no2_from_website, "no2", "Website NO2", hourly_grid),
  describe_timestamp_coverage(df_pm25_from_website, "pm25", "Website PM2.5", hourly_grid)
)
api_missing_no2_dates <- hourly_grid[!hourly_grid %in% df_cldp0391_no2$date]
api_missing_pm25_dates <- hourly_grid[!hourly_grid %in% df_cldp0391_pm25$date]

timestamp_integrity_flags <- run_timestamp_integrity_checks(
  list(
    list(df = df_cldp0391_no2, pollutant = "no2", source = "api"),
    list(df = df_cldp0391_pm25, pollutant = "pm25", source = "api"),
    list(df = df_no2_from_website, pollutant = "no2", source = "website"),
    list(df = df_pm25_from_website, pollutant = "pm25", source = "website")
  ),
  site_code = "CLDP0391"
)
timestamp_integrity_summary <- summarize_timestamp_flags(timestamp_integrity_flags)
timestamp_integrity_issues <- list_timestamp_issues(timestamp_integrity_flags)
print_timestamp_issues(timestamp_integrity_issues)

# Example: inspect website duplicate rows at DST dates (Oct 2023, 2024, 2025)
df_no2_from_website |>
  dplyr::filter(
    date %in% as.POSIXct(
      c("2025-10-26 00:00:00", "2024-10-27 00:00:00", "2023-10-29 00:00:00"),
      tz = "UTC"
    )
  )

# Browse: timestamp_integrity_issues$website$no2$duplicate_timestamp
#         timestamp_integrity_flags |> dplyr::filter(check_name == "out_of_order")  # empty

