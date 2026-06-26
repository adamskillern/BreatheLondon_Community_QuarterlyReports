# Breathe London Communities API client — shared by quarterly report scripts (not multi-site plots).
# Docs: https://www.breathelondon-communities.org/developers  |  Plot helpers: R/bl_plot_api.R

# --- .env storage and parsing ---
# Hidden environment object: stores .env values after ${year_of_report} expansion.
# Other functions read settings through bl_env() instead of parsing the file again.
.bl_env_expanded <- new.env(parent = emptyenv())

bl_parse_env_file <- function(path = ".env") {
  # Reads your .env file from disk into a named list of strings (KEY = value).
  # For example: R’s built-in readRenviron(".env") loads settings but
  # cannot expand ${year_of_report}.
  # This function is the first step so the project can read .env manually, then
  # expand placeholders in the next function.

  lines <- readLines(path, warn = FALSE)
  vars <- character()
  for (line in lines) {
    # Trim spaces so "  KEY=value  " is handled cleanly.
    line <- trimws(line)
    # Ignore empty lines and whole-line comments (lines starting with #).
    if (!nzchar(line) || startsWith(line, "#")) {
      next
    }
    # Ignore lines that are not KEY=value (no equals sign).
    if (!grepl("=", line, fixed = TRUE)) {
      next
    }
    key <- trimws(sub("=.*$", "", line))
    vars[[key]] <- sub("^[^=]*=", "", line)
  }
  vars
}

# --- .env ${variable} expansion ---
bl_expand_env_vars <- function(vars, max_passes = 20L) {
  # Substitutes ${other_key} inside values, e.g. BL_START_DATE uses ${year_of_report}.
  # Loops up to 20 passes chekcing if the ${name} needs to be replaced.
  # Errors if you reference a ${name} that doesn’t exist.
  
  out <- vars
  for (pass in seq_len(max_passes)) {
    prev <- out
    for (key in names(out)) {
      s <- out[[key]]
      # Find and replace each ${ref} in this value with vars[[ref]].
      repeat {
        hit <- regexpr("\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}", s, perl = TRUE)
        if (hit[1] == -1L) {
          break
        }
        ref <- sub("^.*\\$\\{([^}]+)\\}.*$", "\\1", regmatches(s, hit)[[1]])
        if (!ref %in% names(out)) {
          stop("Unknown .env variable: ${", ref, "}", call. = FALSE)
        }
        s <- sub(paste0("\\$\\{", ref, "\\}"), out[[ref]], s, perl = TRUE)
      }
      out[[key]] <- s
    }
    # Stop looping when one full pass changed nothing (all expansions done).
    if (identical(prev, out)) {
      break
    }
  }
  out
}

# --- Apply parsed .env to Sys.setenv and internal cache ---
bl_apply_env <- function(vars) {
  # Makes every .env variable visible to R via Sys.setenv() and .bl_env_expanded - this project’s cache.
  # Called after parse + expand so bl_env() and Sys.getenv() agree. - bl_load_env() calls it.
  rm(list = ls(envir = .bl_env_expanded), envir = .bl_env_expanded)
  for (n in names(vars)) {
    do.call(Sys.setenv, setNames(list(vars[[n]]), n))
    assign(n, vars[[n]], envir = .bl_env_expanded)
  }
  invisible(vars)
}

# --- Read expanded .env values ---
bl_env <- function(key, unset = "") {
  # Returns one setting by name (e.g. "BL_SITE_CODE"), with expanded ${...} already applied.
  # Falls back to Sys.getenv() if the key is missing or empty in the internal cache.
  if (exists(key, envir = .bl_env_expanded, inherits = FALSE)) {
    val <- get(key, envir = .bl_env_expanded)
    if (nzchar(val)) {
      return(val)
    }
  }
  Sys.getenv(key, unset = unset)
}

# --- Load .env from disk ---
bl_load_env <- function(path = ".env") {
  # Main entry point: load project .env (parse, expand, apply). Call at script startup.
  # Returns FALSE invisibly if the file does not exist; TRUE if load succeeded.
  if (!file.exists(path)) {
    return(invisible(FALSE))
  }
  bl_apply_env(bl_expand_env_vars(bl_parse_env_file(path)))
  invisible(TRUE)
}

# --- Report site codes (comma-separated list or single BL_SITE_CODE) ---
bl_parse_site_code_list <- function(x) {
  parts <- trimws(unlist(strsplit(as.character(x), ",", fixed = TRUE)))
  parts <- parts[nzchar(parts)]
  if (!length(parts)) {
    stop("No site codes in list.", call. = FALSE)
  }
  unique(parts)
}

bl_resolve_report_site_codes <- function() {
  if (!length(ls(envir = .bl_env_expanded))) {
    bl_load_env()
  }
  codes <- bl_env("BL_REPORT_SITE_CODES", "")
  if (nzchar(codes)) {
    return(bl_parse_site_code_list(codes))
  }
  single <- bl_env("BL_SITE_CODE", "")
  if (nzchar(single)) {
    return(single)
  }
  stop("Set BL_REPORT_SITE_CODES or BL_SITE_CODE in .env", call. = FALSE)
}

bl_use_site_code <- function(site_code) {
  if (is.null(site_code) || !nzchar(site_code)) {
    stop("site_code is empty", call. = FALSE)
  }
  assign("BL_SITE_CODE", site_code, envir = .bl_env_expanded)
  Sys.setenv(BL_SITE_CODE = site_code)
  invisible(site_code)
}

bl_report_csv_paths <- function(site_code = NULL) {
  site_code <- site_code %||% bl_env("BL_SITE_CODE")
  no2_site <- file.path("data/processed", paste0("no2_", site_code, ".csv"))
  pm25_site <- file.path("data/processed", paste0("pm25_", site_code, ".csv"))
  if (file.exists(no2_site) && file.exists(pm25_site)) {
    return(list(no2 = no2_site, pm25 = pm25_site))
  }
  list(
    no2 = bl_env("BL_NO2_CSV", "data/processed/no2.csv"),
    pm25 = bl_env("BL_PM25_CSV", "data/processed/pm25.csv")
  )
}

# --- API key and base URL ---
bl_api_key <- function() {
  # Returns your BREATHE_API_KEY from the environment (required on every API request).
  # Stops with a clear error if the key is missing — copy .env.example to .env first.
  key <- Sys.getenv("BREATHE_API_KEY", unset = "")
  if (!nzchar(key)) {
    stop(
      "BREATHE_API_KEY is not set. Copy .env.example to .env and add your API key.",
      call. = FALSE
    )
  }
  key
}

bl_api_base <- function() {
  # Returns the API root URL (default: breathelondon-communities.org/api).
  # Strips a trailing slash so paths can be pasted safely onto the base.
  base <- Sys.getenv(
    "BREATHE_API_BASE",
    unset = "https://api.breathelondon-communities.org/api"
  )
  sub("/$", "", base)
}

# --- Authenticated GET helper (httr2) ---
bl_api_get <- function(path, query = list()) {
  # Performs an authenticated HTTP GET and parses the JSON response into R objects.
  # Adds ?key=YOUR_API_KEY; use path like "/listSensors/" (see bl_list_sensors).
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Install httr2: install.packages('httr2')", call. = FALSE)
  }

  url <- paste0(bl_api_base(), path)
  resp <- httr2::request(url) |>
    httr2::req_url_query(key = bl_api_key(), !!!query) |>
    httr2::req_perform()

  # Treat HTTP 4xx/5xx as failure and include the URL in the error message.
  if (httr2::resp_status(resp) >= 400) {
    stop(
      "API request failed (HTTP ", httr2::resp_status(resp), "): ", url,
      call. = FALSE
    )
  }

  httr2::resp_body_json(resp, simplifyVector = TRUE)
}

# --- Sensor metadata (listSensors; filter JSON for one SiteCode) ---
bl_list_sensors <- function() {
  # Downloads metadata for all Breathe London Community nodes (SiteCode, lat/lon, dates, etc.).
  # Used by fetch_sensors.R to write data/raw/listSensors.json.
  bl_api_get("/listSensors/")
}

# --- Hourly pollutant readings (getClarityData) ---
bl_get_clarity_data <- function(
    site_code,
    species,
    start_time,
    end_time,
    averaging = "Hourly"
) {
  # Fetches hourly air-quality readings for one site between start and end (API path times).
  # species is the API code, e.g. "IPM25" (PM2.5) or "INO2" (NO2); averaging is usually "Hourly".
  start_enc <- utils::URLencode(as.character(start_time), reserved = TRUE)
  end_enc <- utils::URLencode(as.character(end_time), reserved = TRUE)
  path <- paste0(
    "/getClarityData/",
    site_code, "/",
    species, "/",
    start_enc, "/",
    end_enc, "/",
    averaging
  )
  bl_api_get(path)
}

# --- GMT date/time formatting for API path segments ---
bl_format_api_time <- function(x) {
  # Converts a POSIXct datetime to the exact string format the API expects in the URL.
  # Example output: "Mon 11 Apr 2022 11:00:00 GMT" (weekday + GMT timezone).
  if (!inherits(x, "POSIXt")) {
    x <- as.POSIXct(x, tz = "GMT")
  }
  paste0(format(x, "%a %d %b %Y %H:%M:%S", tz = "GMT"), " GMT")
}

bl_parse_gmt_datetime <- function(x) {
  # Parses a date/time string from .env into POSIXct (GMT/UTC).
  # Accepts with or without a leading weekday (e.g. "Wed" is optional in .env).
  x <- trimws(x)
  x <- sub("\\s+GMT\\s*$", "", x, ignore.case = TRUE)
  if (grepl("^[A-Za-z]{3} ", x)) {
    dt <- as.POSIXct(x, format = "%a %d %b %Y %H:%M:%S", tz = "GMT")
  } else {
    dt <- as.POSIXct(x, format = "%d %b %Y %H:%M:%S", tz = "GMT")
  }
  if (is.na(dt)) {
    stop("Could not parse date/time: ", x, call. = FALSE)
  }
  dt
}

bl_to_api_gmt_string <- function(x) {
  # Turns a .env date string into an API-ready path time (parse + format).
  # Used by bl_resolve_fetch_start/end for report date windows.
  bl_format_api_time(bl_parse_gmt_datetime(x))
}

# --- Quarterly report date helpers ---
bl_quarter_bounds <- function(quarter, year) {
  if (!requireNamespace("lubridate", quietly = TRUE)) {
    stop("Install lubridate", call. = FALSE)
  }
  starts <- c(1L, 4L, 7L, 10L)
  ends <- c(3L, 6L, 9L, 12L)
  sm <- starts[quarter]
  em <- ends[quarter]
  start <- lubridate::ymd(sprintf("%d-%02d-01", year, sm))
  end <- lubridate::ceiling_date(lubridate::ymd(sprintf("%d-%02d-01", year, em)), "month") - 1L
  list(quarter = quarter, year = year, start = start, end = end)
}

bl_quarter_api_range <- function(start_date, end_date) {
  if (!requireNamespace("lubridate", quietly = TRUE)) {
    stop("Install lubridate", call. = FALSE)
  }
  start_api <- bl_format_api_time(
    lubridate::as_datetime(paste0(start_date, " 00:00:00"), tz = "GMT")
  )
  end_api <- bl_format_api_time(
    lubridate::as_datetime(paste0(end_date, " 23:00:00"), tz = "GMT")
  )
  list(start_api = start_api, end_api = end_api)
}

bl_last_completed_quarter <- function(ref = Sys.Date()) {
  # Most recently finished calendar quarter relative to ref (default: today).
  if (!requireNamespace("lubridate", quietly = TRUE)) {
    stop("Install lubridate", call. = FALSE)
  }
  ref <- as.Date(ref)
  year <- lubridate::year(ref)
  current_q <- (lubridate::month(ref) - 1L) %/% 3L + 1L
  if (current_q == 1L) {
    quarter <- 4L
    year <- year - 1L
  } else {
    quarter <- current_q - 1L
  }

  bl_quarter_bounds(quarter, year)
}

# --- Report fetch window: full site deployment (StartDate → EndDate) ---
bl_resolve_site_fetch_window <- function(
    site_code = NULL,
    sensors_path = "data/raw/listSensors.json"
) {
  if (!exists("BL_SITE_CODE", envir = .bl_env_expanded)) {
    bl_load_env()
  }
  site_code <- site_code %||% bl_env("BL_SITE_CODE")
  if (!nzchar(site_code)) {
    stop("Set BL_SITE_CODE in .env", call. = FALSE)
  }
  sensors <- bl_read_sensors_json(sensors_path)
  rng <- bl_site_date_range(site_code, sensors)
  c(rng, list(site_code = site_code))
}

bl_resolve_fetch_start <- function(site_code = NULL, sensors_path = "data/raw/listSensors.json") {
  bl_resolve_site_fetch_window(site_code, sensors_path)$start_api
}

bl_resolve_fetch_end <- function(site_code = NULL, sensors_path = "data/raw/listSensors.json") {
  bl_resolve_site_fetch_window(site_code, sensors_path)$end_api
}

# --- Quarterly report quarter boundaries (always last completed calendar quarter) ---
bl_env_report_dates <- function(ref = Sys.Date(), site_code = NULL) {
  # Used by QuarterlyAQtrends_git.Rmd for bar-chart filters and headings.
  # All fetched rows = "All data to date"; quarter_start → quarter_end = last quarter overlay.
  report_q <- bl_last_completed_quarter(ref)
  fetch <- bl_resolve_site_fetch_window(site_code)
  list(
    report_year = as.character(report_q$year),
    report_quarter = report_q$quarter,
    quarter_start = report_q$start,
    quarter_end = report_q$end,
    fetch_start = fetch$start,
    fetch_end = fetch$end
  )
}

# --- Round pollutant values and treat zero as missing (invalid sensor reading) ---
bl_clean_pollutant_values <- function(df, value_col) {
  if (!value_col %in% names(df) || !nrow(df)) {
    return(df)
  }
  vals <- round(as.numeric(df[[value_col]]), digits = 0)
  vals[vals == 0] <- NA_real_
  df[[value_col]] <- vals
  df
}

# --- Slim getClarityData records to date + pollutant column ---
bl_clarity_to_df <- function(records, value_col, clean = TRUE) {
  # Shrinks raw API rows to two columns: date and pm25 or no2 (from DateTime and ScaledValue).
  # Drops SiteCode, DurationNS, etc. — those are handled elsewhere if needed.
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite", call. = FALSE)
  }

  # Empty API response → empty data.frame with correct column names.
  if (is.null(records) || length(records) == 0) {
    empty <- data.frame(
      date = character(),
      stringsAsFactors = FALSE
    )
    empty[[value_col]] <- numeric()
    return(empty)
  }

  # If JSON came back as a nested list, flatten to a standard data.frame first.
  if (!is.data.frame(records)) {
    records <- jsonlite::fromJSON(jsonlite::toJSON(records, auto_unbox = TRUE))
  }

  dt <- as.POSIXct(records$DateTime, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  out <- data.frame(
    date = format(dt, "%Y-%m-%d %H:%M:%S"),
    records$ScaledValue,
    stringsAsFactors = FALSE
  )
  names(out)[2] <- value_col
  out[[value_col]] <- as.numeric(out[[value_col]])
  if (clean) {
    bl_clean_pollutant_values(out, value_col)
  } else {
    out
  }
}

# --- Per-site API window from listSensors metadata ---
bl_read_sensors_json <- function(path = "data/raw/listSensors.json") {
  if (!file.exists(path)) {
    stop("Sensor list not found: ", path, "\nRun: Rscript scripts/fetch_sensors.R", call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite", call. = FALSE)
  }
  sensors <- jsonlite::fromJSON(path, simplifyVector = TRUE)[[1]]
  sensors$SiteCode <- as.character(sensors$SiteCode)
  sensors$EndDate <- as.character(sensors$EndDate)
  sensors$EndDate[sensors$EndDate == ""] <- NA_character_
  sensors
}

bl_site_date_range <- function(site, sensors) {
  row <- sensors[sensors$SiteCode == site, , drop = FALSE][1, , drop = FALSE]
  if (!nrow(row)) {
    stop("Site not found in sensor list: ", site, call. = FALSE)
  }
  start_dt <- as.POSIXct(row$StartDate, tz = "UTC")
  end_raw <- row$EndDate[1]
  if (is.na(end_raw) || !nzchar(end_raw)) {
    end_raw <- row$HourlyBulletinEnd[1]
  }
  if (is.na(end_raw) || !nzchar(as.character(end_raw))) {
    end_dt <- Sys.time()
  } else {
    end_dt <- as.POSIXct(end_raw, tz = "UTC")
  }
  list(
    start = as.Date(start_dt),
    end = as.Date(end_dt),
    start_api = bl_format_api_time(start_dt),
    end_api = bl_format_api_time(end_dt)
  )
}

bl_site_api_start <- function(site, sensors) {
  bl_site_date_range(site, sensors)$start_api
}

bl_site_api_end <- function(site, sensors) {
  bl_site_date_range(site, sensors)$end_api
}

bl_site_organisation_name <- function(
    site = NULL,
    sensors_path = "data/raw/listSensors.json"
) {
  if (!exists("BL_SITE_CODE", envir = .bl_env_expanded)) {
    bl_load_env()
  }
  site <- site %||% bl_env("BL_SITE_CODE")
  if (!nzchar(site)) {
    stop("Set BL_SITE_CODE in .env", call. = FALSE)
  }
  sensors <- bl_read_sensors_json(sensors_path)
  row <- sensors[sensors$SiteCode == site, , drop = FALSE][1, , drop = FALSE]
  if (!nrow(row)) {
    stop("Site not found in sensor list: ", site, call. = FALSE)
  }
  trimws(as.character(row$OrganisationName[1]))
}

bl_site_location <- function(
    site = NULL,
    sensors_path = "data/raw/listSensors.json"
) {
  if (!exists("BL_SITE_CODE", envir = .bl_env_expanded)) {
    bl_load_env()
  }
  site <- site %||% bl_env("BL_SITE_CODE")
  if (!nzchar(site)) {
    stop("Set BL_SITE_CODE in .env", call. = FALSE)
  }
  sensors <- bl_read_sensors_json(sensors_path)
  row <- sensors[sensors$SiteCode == site, , drop = FALSE][1, , drop = FALSE]
  if (!nrow(row)) {
    stop("Site not found in sensor list: ", site, call. = FALSE)
  }
  list(
    site_code = site,
    site_name = trimws(as.character(row$SiteName[1])),
    latitude = as.numeric(row$Latitude[1]),
    longitude = as.numeric(row$Longitude[1])
  )
}

bl_bind_site_readings <- function(parts) {
  parts <- Filter(function(x) !is.null(x) && nrow(x) > 0, parts)
  if (!length(parts)) {
    return(data.frame(
      SiteCode = character(),
      date = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, parts)
}

bl_fetch_site_species <- function(site, species, value_col, start, end) {
  tryCatch(
    {
      df <- bl_clarity_to_df(
        bl_get_clarity_data(site, species, start, end),
        value_col
      )
      if (nrow(df)) {
        cbind(SiteCode = site, df, stringsAsFactors = FALSE)
      } else {
        NULL
      }
    },
    error = function(e) {
      warning(site, " ", value_col, ": ", conditionMessage(e), call. = FALSE)
      NULL
    }
  )
}

# --- All-site NO2 + PM2.5 fetch (per-site StartDate → EndDate) and optional CSV save ---
bl_fetch_all_sites_readings <- function(
    sensors_path = "data/raw/listSensors.json",
    pm25_path = "data/processed/pm25_all_sites.csv",
    no2_path = "data/processed/no2_all_sites.csv",
    species_pm25 = NULL,
    species_no2 = NULL,
    sites = NULL,
    save = TRUE,
    verbose = TRUE
) {
  if (!exists("BL_SITE_CODE", envir = .bl_env_expanded)) {
    bl_load_env()
  }

  species_pm25 <- species_pm25 %||% bl_env("BL_SPECIES_PM25", "IPM25")
  species_no2 <- species_no2 %||% bl_env("BL_SPECIES_NO2", "INO2")

  sensors <- bl_read_sensors_json(sensors_path)
  if (is.null(sites)) {
    sites <- unique(sensors$SiteCode)
  } else {
    sites <- unique(as.character(sites))
  }

  if (verbose) {
    message(
      "Sites: ", length(sites),
      " (per-site StartDate → EndDate from listSensors.json)"
    )
  }

  pm25_parts <- vector("list", length(sites))
  no2_parts <- vector("list", length(sites))
  names(pm25_parts) <- sites
  names(no2_parts) <- sites

  for (i in seq_along(sites)) {
    site <- sites[[i]]
    start <- bl_site_api_start(site, sensors)
    end <- bl_site_api_end(site, sensors)
    if (verbose) {
      message("[", i, "/", length(sites), "] ", site, "  ", start, " → ", end)
    }

    pm25_parts[[site]] <- bl_fetch_site_species(site, species_pm25, "pm25", start, end)
    no2_parts[[site]] <- bl_fetch_site_species(site, species_no2, "no2", start, end)
  }

  pm25 <- bl_bind_site_readings(pm25_parts)
  no2 <- bl_bind_site_readings(no2_parts)
  if (!"pm25" %in% names(pm25)) {
    pm25$pm25 <- numeric()
  }
  if (!"no2" %in% names(no2)) {
    no2$no2 <- numeric()
  }

  if (save) {
    dir.create(dirname(pm25_path), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(pm25, pm25_path, row.names = FALSE)
    utils::write.csv(no2, no2_path, row.names = FALSE)
    if (verbose) {
      message("Wrote ", pm25_path, " (", nrow(pm25), " rows)")
      message("Wrote ", no2_path, " (", nrow(no2), " rows)")
    }
  }

  invisible(list(pm25 = pm25, no2 = no2))
}

# --- Single-site NO2 + PM2.5 fetch for quarterly report ---
bl_fetch_readings <- function(
    site_code = NULL,
    start_time = NULL,
    end_time = NULL,
    species_no2 = NULL,
    species_pm25 = NULL,
    clean = TRUE
) {
  # Fetches one site's hourly NO2 and PM2.5 for the quarterly report time window.
  # Used by fetch_readings.R; defaults come from .env when arguments are NULL.
  if (!exists("BL_SITE_CODE", envir = .bl_env_expanded)) {
    bl_load_env()
  }

  # Fill missing arguments from .env (see %||% at bottom of this file).
  site_code <- site_code %||% bl_env("BL_SITE_CODE")
  start_time <- start_time %||% bl_resolve_fetch_start()
  end_time <- end_time %||% bl_resolve_fetch_end()
  species_no2 <- species_no2 %||% bl_env("BL_SPECIES_NO2", "INO2")
  species_pm25 <- species_pm25 %||% bl_env("BL_SPECIES_PM25", "IPM25")

  if (!nzchar(site_code) || !nzchar(start_time) || !nzchar(end_time)) {
    stop(
      "Set BL_SITE_CODE in .env ",
      "(report dates default to last completed quarter via bl_resolve_fetch_start/end).",
      call. = FALSE
    )
  }

  no2_records <- bl_get_clarity_data(site_code, species_no2, start_time, end_time)
  pm25_records <- bl_get_clarity_data(site_code, species_pm25, start_time, end_time)

  list(
    no2 = bl_clarity_to_df(no2_records, "no2", clean = clean),
    pm25 = bl_clarity_to_df(pm25_records, "pm25", clean = clean)
  )
}

# --- Load report data from CSV or live API ---
bl_load_report_data <- function(source = NULL, site_code = NULL, clean = TRUE) {
  # Supplies NO2 + PM2.5 data.frames to QuarterlyAQtrends_git.Rmd (CSV or live API).
  # Controlled by BL_DATA_SOURCE: "csv" reads files; "api" calls bl_fetch_readings().
  bl_load_env()
  site_code <- site_code %||% bl_env("BL_SITE_CODE")
  source <- tolower(source %||% bl_env("BL_DATA_SOURCE", "csv"))

  if (identical(source, "api")) {
    return(bl_fetch_readings(site_code = site_code, clean = clean))
  }

  if (!identical(source, "csv")) {
    stop('BL_DATA_SOURCE must be "csv" or "api".', call. = FALSE)
  }

  paths <- bl_report_csv_paths(site_code)
  no2_path <- paths$no2
  pm25_path <- paths$pm25

  if (!file.exists(no2_path)) {
    stop("NO2 CSV not found: ", no2_path, call. = FALSE)
  }
  if (!file.exists(pm25_path)) {
    stop("PM2.5 CSV not found: ", pm25_path, call. = FALSE)
  }

  no2 <- utils::read.csv(no2_path, stringsAsFactors = FALSE)
  pm25 <- utils::read.csv(pm25_path, stringsAsFactors = FALSE)

  # Portal CSV export uses different column names; rename when BL_BREATHE_EXPORT=1.
  if (identical(bl_env("BL_BREATHE_EXPORT"), "1")) {
    if (!requireNamespace("dplyr", quietly = TRUE)) {
      stop("Install dplyr for BL_BREATHE_EXPORT column renaming.", call. = FALSE)
    }
    no2 <- no2 %>%
      dplyr::rename(date = Category, no2 = `Nitrogen dioxide`)
    pm25 <- pm25 %>%
      dplyr::rename(date = Category, pm25 = `PM<sub>2.5</sub> particulates`)
  }

  if (clean) {
    no2 <- bl_clean_pollutant_values(no2, "no2")
    pm25 <- bl_clean_pollutant_values(pm25, "pm25")
  } else {
    no2$no2 <- as.numeric(no2$no2)
    pm25$pm25 <- as.numeric(pm25$pm25)
  }

  list(no2 = no2, pm25 = pm25)
}

# --- Null/empty coalesce for optional arguments ---
# Infix operator: use the left value if it is non-empty, otherwise use the right (default).
# Example: site_code %||% bl_env("BL_SITE_CODE") means "use argument, else .env".
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(x[1])) y else x
}
