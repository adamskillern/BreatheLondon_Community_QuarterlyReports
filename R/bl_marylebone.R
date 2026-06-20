# Marylebone Road (AURN MY1) reference data and quarterly narrative selection.
# Used by QuarterlyAQtrends_git.Rmd to compare the community node with MY1.

BL_MARYLEBONE_RDATA_DEFAULT <- "data/processed/marylebone.RData"

# Time windows for narrative options A/B/C (hours inclusive).
# A and B use all days of the week; C is weekdays only (school pick-up).
BL_MARYLEBONE_WINDOW_A <- c(7L, 10L)   # morning rush 07:00–10:00
BL_MARYLEBONE_WINDOW_B <- c(12L, 18L)  # afternoon 12:00–18:00
BL_MARYLEBONE_WINDOW_C <- c(15L, 16L)  # school pick-up 15:00–16:30 (hours 15–16)

bl_format_marylebone_hour_range <- function(hour_range) {
  sprintf(
    "%02d:00–%02d:00",
    as.integer(hour_range[[1]]),
    as.integer(hour_range[[2]])
  )
}

bl_format_marylebone_footnote <- function(
    selection,
    pollutant_label,
    quarter_label) {
  if (is.null(selection)) {
    return(NULL)
  }

  window_a <- bl_format_marylebone_hour_range(BL_MARYLEBONE_WINDOW_A)
  window_b <- bl_format_marylebone_hour_range(BL_MARYLEBONE_WINDOW_B)
  window_c <- bl_format_marylebone_hour_range(BL_MARYLEBONE_WINDOW_C)

  switch(
    selection$option,
    A = sprintf(
      paste0(
        "%s during %s: mean paired hourly values (community sensor vs Marylebone Road) ",
        "for %s, all days of the week."
      ),
      pollutant_label, quarter_label, window_a
    ),
    B = sprintf(
      paste0(
        "%s during %s: mean paired hourly values for afternoons (%s) on the %d day%s ",
        "in the top 25\\%% by community afternoon mean."
      ),
      pollutant_label,
      quarter_label,
      window_b,
      selection$n_spike_days,
      if (identical(selection$n_spike_days, 1L)) "" else "s"
    ),
    C = sprintf(
      paste0(
        "%s during %s: mean paired weekday hourly values (community sensor vs Marylebone Road) ",
        "for %s (school pick-up)."
      ),
      pollutant_label, quarter_label, window_c
    ),
    NULL
  )
}

bl_marylebone_within_25pct <- function(community_val, marylebone_val) {
  if (is.na(community_val) || is.na(marylebone_val) || marylebone_val <= 0) {
    return(FALSE)
  }
  ratio <- community_val / marylebone_val
  ratio >= 0.75 && ratio <= 1.25
}

bl_parse_community_datetime <- function(df, value_col) {
  df %>%
    dplyr::mutate(
      datetime = lubridate::ymd_hms(sub("\\..*", "", .data$date), quiet = TRUE),
      value = as.numeric(.data[[value_col]])
    ) %>%
    dplyr::filter(!is.na(datetime), !is.na(value)) %>%
    dplyr::transmute(
      datetime = datetime,
      hour = lubridate::hour(datetime),
      weekday = lubridate::wday(datetime),
      community = value
    )
}

bl_normalize_marylebone_df <- function(df) {
  out <- as.data.frame(df)
  if (!"date" %in% names(out)) {
    stop("Marylebone data must include a date column.", call. = FALSE)
  }
  out$datetime <- as.POSIXct(out$date, tz = "UTC")
  if ("pm2.5" %in% names(out) && !"pm25" %in% names(out)) {
    out$pm25 <- as.numeric(out[["pm2.5"]])
  }
  if ("no2" %in% names(out)) {
    out <- bl_clean_pollutant_values(out, "no2")
  }
  if ("pm25" %in% names(out)) {
    out <- bl_clean_pollutant_values(out, "pm25")
  }
  out
}

# Load MY1 hourly data.
# Priority: if marylebone.RData exists at BL_MARYLEBONE_RDATA, load it and do NOT
# call openair. When the file is missing, fetch once via openair::importUKAQ(),
# save as marylebone.RData, then use that cache for all later reports (mass runs).
bl_load_marylebone_hourly <- function(
    rdata_path = NULL,
    json_path = "data/raw/listSensors.json") {
  if (!exists("bl_env", mode = "function")) {
    stop("Source R/bl_api.R before R/bl_marylebone.R", call. = FALSE)
  }
  rdata_path <- rdata_path %||% bl_env("BL_MARYLEBONE_RDATA", BL_MARYLEBONE_RDATA_DEFAULT)

  if (file.exists(rdata_path)) {
    env <- new.env(parent = emptyenv())
    load(rdata_path, envir = env)
    if (!exists("marylebone", envir = env)) {
      stop(
        "Expected object 'marylebone' in ", rdata_path,
        ". Re-save with save(marylebone, file = '...').",
        call. = FALSE
      )
    }
    message(
      "Marylebone reference: loaded from RData (no API call): ", rdata_path
    )
    return(bl_normalize_marylebone_df(env$marylebone))
  }

  message(
    "Marylebone reference: ", rdata_path,
    " not found — fetching MY1 via openair (will save cache for future reports)"
  )
  marylebone <- bl_fetch_marylebone_openair(json_path = json_path)
  rdata_dir <- dirname(rdata_path)
  if (nzchar(rdata_dir)) {
    dir.create(rdata_dir, recursive = TRUE, showWarnings = FALSE)
  }
  save(marylebone, file = rdata_path)
  message("Marylebone reference: saved cache to ", rdata_path)
  bl_normalize_marylebone_df(marylebone)
}

bl_fetch_marylebone_openair <- function(
    json_path = "data/raw/listSensors.json") {
  if (!requireNamespace("openair", quietly = TRUE)) {
    stop("Install openair to fetch Marylebone Road data.", call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite to read listSensors.json.", call. = FALSE)
  }

  earliest_start <- Sys.Date() - 365 * 5
  if (file.exists(json_path)) {
    sensors <- jsonlite::fromJSON(json_path, simplifyVector = TRUE)[[1]]
    earliest_start <- min(as.Date(sensors$StartDate), na.rm = TRUE)
  }

  end_year <- as.integer(format(Sys.Date(), "%Y"))
  raw <- openair::importUKAQ(
    site = "my1",
    year = lubridate::year(earliest_start):end_year,
    pollutant = c("no2", "pm2.5"),
    progress = FALSE
  )
  raw[raw$date >= earliest_start, ]
}

bl_prepare_marylebone_hourly <- function(marylebone_df, value_col, quarter_start, quarter_end) {
  col <- if (identical(value_col, "pm25") && "pm2.5" %in% names(marylebone_df)) {
    "pm2.5"
  } else {
    value_col
  }
  if (!col %in% names(marylebone_df)) {
    stop("Marylebone data missing column: ", col, call. = FALSE)
  }

  marylebone_df %>%
    dplyr::mutate(
      datetime = as.POSIXct(.data$date, tz = "UTC"),
      value = as.numeric(.data[[col]])
    ) %>%
    dplyr::filter(
      !is.na(datetime),
      !is.na(value),
      as.Date(datetime) >= quarter_start,
      as.Date(datetime) <= quarter_end
    ) %>%
    dplyr::transmute(
      datetime = datetime,
      hour = lubridate::hour(datetime),
      weekday = lubridate::wday(datetime),
      marylebone = value
    )
}

bl_prepare_hourly_pair <- function(
    community_df,
    marylebone_df,
    value_col,
    quarter_start,
    quarter_end) {
  community <- bl_parse_community_datetime(community_df, value_col) %>%
    dplyr::filter(
      as.Date(datetime) >= quarter_start,
      as.Date(datetime) <= quarter_end
    )
  reference <- bl_prepare_marylebone_hourly(
    marylebone_df, value_col, quarter_start, quarter_end
  )

  dplyr::inner_join(
    dplyr::select(community, datetime, hour, weekday, community),
    dplyr::select(reference, datetime, marylebone),
    by = "datetime"
  )
}

bl_filter_hour_window <- function(pair_df, hour_range) {
  pair_df %>%
    dplyr::filter(
      hour >= hour_range[[1]],
      hour <= hour_range[[2]]
    )
}

bl_filter_weekday_window <- function(pair_df, hour_range) {
  pair_df %>%
    dplyr::filter(
      weekday %in% 2:6,
      hour >= hour_range[[1]],
      hour <= hour_range[[2]]
    )
}

bl_marylebone_option_a_metrics <- function(pair_df) {
  window_df <- bl_filter_hour_window(pair_df, BL_MARYLEBONE_WINDOW_A)
  if (!nrow(window_df)) {
    return(NULL)
  }
  comm <- mean(window_df$community, na.rm = TRUE)
  mary <- mean(window_df$marylebone, na.rm = TRUE)
  list(
    option = "A",
    headline_community = comm,
    headline_marylebone = mary,
    cumulative_load = sum(window_df$community, na.rm = TRUE),
    within_25pct = bl_marylebone_within_25pct(comm, mary),
    n_spike_days = NA_integer_
  )
}

bl_marylebone_option_b_metrics <- function(pair_df) {
  afternoon <- bl_filter_hour_window(pair_df, BL_MARYLEBONE_WINDOW_B)
  if (!nrow(afternoon)) {
    return(NULL)
  }

  by_day <- afternoon %>%
    dplyr::mutate(day = as.Date(datetime)) %>%
    dplyr::group_by(day) %>%
    dplyr::summarise(
      community = mean(community, na.rm = TRUE),
      marylebone = mean(marylebone, na.rm = TRUE),
      .groups = "drop"
    )

  if (nrow(by_day) < 2L) {
    return(NULL)
  }

  threshold <- stats::quantile(by_day$community, probs = 0.75, na.rm = TRUE)
  spike_days <- by_day %>% dplyr::filter(community >= threshold)
  if (!nrow(spike_days)) {
    return(NULL)
  }

  comm <- mean(spike_days$community, na.rm = TRUE)
  mary <- mean(spike_days$marylebone, na.rm = TRUE)
  list(
    option = "B",
    headline_community = comm,
    headline_marylebone = mary,
    spike_marylebone = mary,
    cumulative_load = sum(afternoon$community, na.rm = TRUE),
    within_25pct = bl_marylebone_within_25pct(comm, mary),
    n_spike_days = nrow(spike_days)
  )
}

bl_marylebone_option_c_metrics <- function(pair_df) {
  window_df <- bl_filter_weekday_window(pair_df, BL_MARYLEBONE_WINDOW_C)
  if (!nrow(window_df)) {
    return(NULL)
  }
  comm <- mean(window_df$community, na.rm = TRUE)
  mary <- mean(window_df$marylebone, na.rm = TRUE)
  list(
    option = "C",
    headline_community = comm,
    headline_marylebone = mary,
    cumulative_load = sum(window_df$community, na.rm = TRUE),
    within_25pct = NA,
    n_spike_days = NA_integer_
  )
}

# Per pollutant: pick A or B if either passes ±25% (highest cumulative load wins);
# otherwise use C (catch-all, no ±25% gate). NO2 and PM2.5 are independent.
bl_select_marylebone_narrative <- function(
    community_df,
    marylebone_df,
    value_col,
    quarter_start,
    quarter_end) {
  pair_df <- bl_prepare_hourly_pair(
    community_df,
    marylebone_df,
    value_col,
    quarter_start,
    quarter_end
  )
  if (!nrow(pair_df)) {
    return(NULL)
  }

  metrics <- list(
    A = bl_marylebone_option_a_metrics(pair_df),
    B = bl_marylebone_option_b_metrics(pair_df),
    C = bl_marylebone_option_c_metrics(pair_df)
  )

  eligible_ab <- metrics[names(metrics) %in% c("A", "B")]
  eligible_ab <- eligible_ab[!vapply(eligible_ab, is.null, logical(1))]
  eligible_ab <- eligible_ab[vapply(
    eligible_ab,
    function(m) isTRUE(m$within_25pct),
    logical(1)
  )]

  if (length(eligible_ab)) {
    loads <- vapply(eligible_ab, function(m) m$cumulative_load, numeric(1))
    return(eligible_ab[[which.max(loads)]])
  }

  metrics$C
}
