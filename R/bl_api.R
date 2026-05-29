# Breathe London Communities API client (https://www.breathelondon-communities.org/developers)

.bl_env_expanded <- new.env(parent = emptyenv())

bl_parse_env_file <- function(path = ".env") {
  lines <- readLines(path, warn = FALSE)
  vars <- character()
  for (line in lines) {
    line <- trimws(line)
    if (!nzchar(line) || startsWith(line, "#")) {
      next
    }
    if (!grepl("=", line, fixed = TRUE)) {
      next
    }
    key <- trimws(sub("=.*$", "", line))
    vars[[key]] <- sub("^[^=]*=", "", line)
  }
  vars
}

#' Expand ${year_of_report} and other ${var} references in .env values
bl_expand_env_vars <- function(vars, max_passes = 20L) {
  out <- vars
  for (pass in seq_len(max_passes)) {
    prev <- out
    for (key in names(out)) {
      s <- out[[key]]
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
    if (identical(prev, out)) {
      break
    }
  }
  out
}

bl_apply_env <- function(vars) {
  rm(list = ls(envir = .bl_env_expanded), envir = .bl_env_expanded)
  for (n in names(vars)) {
    do.call(Sys.setenv, setNames(list(vars[[n]]), n))
    assign(n, vars[[n]], envir = .bl_env_expanded)
  }
  invisible(vars)
}

#' Expanded .env value (after ${year_of_report} substitution)
bl_env <- function(key, unset = "") {
  if (exists(key, envir = .bl_env_expanded, inherits = FALSE)) {
    val <- get(key, envir = .bl_env_expanded)
    if (nzchar(val)) {
      return(val)
    }
  }
  Sys.getenv(key, unset = unset)
}

#' Load .env and expand ${...} placeholders
bl_load_env <- function(path = ".env") {
  if (!file.exists(path)) {
    return(invisible(FALSE))
  }
  bl_apply_env(bl_expand_env_vars(bl_parse_env_file(path)))
  invisible(TRUE)
}

bl_api_key <- function() {
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
  base <- Sys.getenv(
    "BREATHE_API_BASE",
    unset = "https://api.breathelondon-communities.org/api"
  )
  sub("/$", "", base)
}

bl_api_get <- function(path, query = list()) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Install httr2: install.packages('httr2')", call. = FALSE)
  }

  url <- paste0(bl_api_base(), path)
  resp <- httr2::request(url) |>
    httr2::req_url_query(key = bl_api_key(), !!!query) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    stop(
      "API request failed (HTTP ", httr2::resp_status(resp), "): ", url,
      call. = FALSE
    )
  }

  httr2::resp_body_json(resp, simplifyVector = TRUE)
}

#' List all sensors (GET /listSensors or /ListSensors)
bl_list_sensors <- function() {
  bl_api_get("/listSensors/")
}

#' Single sensor metadata (GET /Sensor/{site_code})
bl_get_sensor <- function(site_code) {
  bl_api_get(paste0("/Sensor/", site_code))
}

#' Hourly readings (GET /getClarityData/...)
bl_get_clarity_data <- function(
    site_code,
    species,
    start_time,
    end_time,
    averaging = "Hourly"
) {
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

#' Format API times for path segments (e.g. "Mon 11 Apr 2022 11:00:00 GMT")
bl_format_api_time <- function(x) {
  if (!inherits(x, "POSIXt")) {
    x <- as.POSIXct(x, tz = "GMT")
  }
  paste0(format(x, "%a %d %b %Y %H:%M:%S", tz = "GMT"), " GMT")
}

#' Parse date/time text (with or without leading weekday) to POSIXct GMT
bl_parse_gmt_datetime <- function(x) {
  x <- trimws(x)
  if (!grepl("GMT\\s*$", x, ignore.case = TRUE)) {
    x <- paste(x, "GMT")
  }
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

#' Build getClarityData path time: adds weekday from calendar (you omit it in .env)
bl_to_api_gmt_string <- function(x) {
  bl_format_api_time(bl_parse_gmt_datetime(x))
}

#' API start time from BL_START_DATE (preferred) or BL_START_TIME (legacy)
bl_resolve_fetch_start <- function() {
  raw <- trimws(bl_env("BL_START_DATE"))
  if (!nzchar(raw)) {
    raw <- trimws(bl_env("BL_START_TIME"))
  }
  if (!nzchar(raw)) {
    return("")
  }
  bl_to_api_gmt_string(raw)
}

bl_resolve_fetch_end <- function() {
  raw <- trimws(bl_env("BL_END_DATE"))
  if (!nzchar(raw)) {
    raw <- trimws(bl_env("BL_END_TIME"))
  }
  if (!nzchar(raw)) {
    return("")
  }
  bl_to_api_gmt_string(raw)
}

bl_env_report_dates <- function() {
  list(
    report_year = bl_env("BL_REPORT_YEAR", "2022"),
    q3_start = as.Date(bl_env("BL_Q3_START", "2022-07-01")),
    q3_end = as.Date(bl_env("BL_Q3_END", "2022-09-30")),
    q4_start = as.Date(bl_env("BL_Q4_START", "2022-10-01")),
    q4_end = as.Date(bl_env("BL_Q4_END", "2022-12-31"))
  )
}

#' Convert getClarityData JSON to report-ready data frame (date, value_col)
bl_clarity_to_df <- function(records, value_col) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite", call. = FALSE)
  }

  if (is.null(records) || length(records) == 0) {
    return(data.frame(
      date = character(),
      value = numeric(),
      stringsAsFactors = FALSE
    ))
  }

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
  out
}

#' Fetch hourly NO2 and PM2.5 as data frames (uses .env when args omitted)
bl_fetch_readings <- function(
    site_code = NULL,
    start_time = NULL,
    end_time = NULL,
    species_no2 = NULL,
    species_pm25 = NULL
) {
  if (!exists("BL_SITE_CODE", envir = .bl_env_expanded)) {
    bl_load_env()
  }

  site_code <- site_code %||% bl_env("BL_SITE_CODE")
  start_time <- start_time %||% bl_resolve_fetch_start()
  end_time <- end_time %||% bl_resolve_fetch_end()
  species_no2 <- species_no2 %||% bl_env("BL_SPECIES_NO2", "INO2")
  species_pm25 <- species_pm25 %||% bl_env("BL_SPECIES_PM25", "IPM25")

  if (!nzchar(site_code) || !nzchar(start_time) || !nzchar(end_time)) {
    stop(
      "Set BL_SITE_CODE and BL_START_DATE / BL_END_DATE in .env ",
      "(e.g. 01 Jan ${year_of_report} 00:00:00 GMT — weekday added automatically).",
      call. = FALSE
    )
  }

  no2_records <- bl_get_clarity_data(site_code, species_no2, start_time, end_time)
  pm25_records <- bl_get_clarity_data(site_code, species_pm25, start_time, end_time)

  list(
    no2 = bl_clarity_to_df(no2_records, "no2"),
    pm25 = bl_clarity_to_df(pm25_records, "pm25")
  )
}

#' Load report data from CSV files or API (BL_DATA_SOURCE=csv|api)
bl_load_report_data <- function(source = NULL) {
  bl_load_env()
  source <- tolower(source %||% bl_env("BL_DATA_SOURCE", "csv"))

  if (identical(source, "api")) {
    return(bl_fetch_readings())
  }

  if (!identical(source, "csv")) {
    stop('BL_DATA_SOURCE must be "csv" or "api".', call. = FALSE)
  }

  no2_path <- bl_env("BL_NO2_CSV", "data/processed/no2.csv")
  pm25_path <- bl_env("BL_PM25_CSV", "data/processed/pm25.csv")

  if (!file.exists(no2_path)) {
    stop("NO2 CSV not found: ", no2_path, call. = FALSE)
  }
  if (!file.exists(pm25_path)) {
    stop("PM2.5 CSV not found: ", pm25_path, call. = FALSE)
  }

  no2 <- utils::read.csv(no2_path, stringsAsFactors = FALSE)
  pm25 <- utils::read.csv(pm25_path, stringsAsFactors = FALSE)

  if (identical(bl_env("BL_BREATHE_EXPORT"), "1")) {
    if (!requireNamespace("dplyr", quietly = TRUE)) {
      stop("Install dplyr for BL_BREATHE_EXPORT column renaming.", call. = FALSE)
    }
    no2 <- no2 %>%
      dplyr::rename(date = Category, no2 = `Nitrogen dioxide`)
    pm25 <- pm25 %>%
      dplyr::rename(date = Category, pm25 = `PM<sub>2.5</sub> particulates`)
  }

  list(no2 = no2, pm25 = pm25)
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(x[1])) y else x
}
