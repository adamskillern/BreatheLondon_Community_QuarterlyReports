# Pollutant summary stats shared by the quarterly report and mock plots.

BL_REPORT_ROUND_DIGITS <- 0L

bl_pollutant_summary <- function(df, value_col, threshold, start_date = NULL, end_date = NULL) {
  period_df <- df %>%
    dplyr::mutate(day = as.Date(sub(" .*", "", gsub("\\..*", "", date))))

  if (!is.null(start_date)) {
    period_df <- period_df %>% dplyr::filter(day >= start_date)
  }
  if (!is.null(end_date)) {
    period_df <- period_df %>% dplyr::filter(day <= end_date)
  }

  values <- period_df[[value_col]]
  values <- values[!is.na(values)]

  daily <- period_df %>%
    dplyr::group_by(day) %>%
    dplyr::summarise(
      daily_mean = round(mean(.data[[value_col]], na.rm = TRUE), BL_REPORT_ROUND_DIGITS),
      .groups = "drop"
    )

  if (!length(values)) {
    return(list(
      exceed_days = 0L,
      exceed_days_by_year = data.frame(
        year = integer(),
        exceed_days = integer(),
        total_days = integer(),
        exceed_pct = numeric()
      ),
      mean = NA_real_,
      min = NA_real_,
      max = NA_real_
    ))
  }

  exceed_days_by_year <- daily %>%
    dplyr::mutate(year = lubridate::year(day)) %>%
    dplyr::group_by(year) %>%
    dplyr::summarise(
      exceed_days = sum(daily_mean > threshold, na.rm = TRUE),
      total_days = sum(!is.na(daily_mean)),
      .groups = "drop"
    ) %>%
    dplyr::arrange(year)

  list(
    exceed_days = sum(daily$daily_mean > threshold, na.rm = TRUE),
    exceed_days_by_year = exceed_days_by_year,
    mean = round(mean(values), BL_REPORT_ROUND_DIGITS),
    min = min(values),
    max = max(values)
  )
}

bl_add_annual_exceedance_year_pct <- function(by_year) {
  if (!nrow(by_year)) {
    return(by_year)
  }
  by_year$exceed_pct <- ifelse(
    by_year$total_days > 0L,
    round(100 * by_year$exceed_days / by_year$total_days, BL_REPORT_ROUND_DIGITS),
    0
  )
  by_year
}

bl_to_date_pollutant_summary <- function(
    df,
    value_col,
    threshold,
    quarter_end,
    report_year,
    report_quarter) {
  stats <- bl_pollutant_summary(df, value_col, threshold, end_date = quarter_end)
  by_year <- stats$exceed_days_by_year
  if (!is.null(by_year) && nrow(by_year) && report_quarter == 1L) {
    by_year <- by_year %>% dplyr::filter(year != as.integer(report_year))
  }
  stats$exceed_days_by_year <- bl_add_annual_exceedance_year_pct(by_year)
  stats
}
