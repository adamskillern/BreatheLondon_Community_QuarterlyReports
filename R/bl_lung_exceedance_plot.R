# Lung-outline exceedance plot (mock / experimental).
# Left lung  = NO2 exceedance % per year; right lung = PM2.5 (same data as annual bar charts).
# Each lung is "water-filled" from the base up to the exceedance % height.

# --- Smooth a closed polygon through control points (periodic Catmull-Rom) ---
bl_catmull_rom_closed <- function(px, py, n_per = 26L) {
  n <- length(px)
  xs <- numeric(0)
  ys <- numeric(0)
  tt <- seq(0, 1, length.out = n_per + 1L)[-(n_per + 1L)]
  for (i in seq_len(n)) {
    i0 <- ((i - 2L) %% n) + 1L
    i1 <- ((i - 1L) %% n) + 1L
    i2 <- (i %% n) + 1L
    i3 <- ((i + 1L) %% n) + 1L
    x0 <- px[i0]; x1 <- px[i1]; x2 <- px[i2]; x3 <- px[i3]
    y0 <- py[i0]; y1 <- py[i1]; y2 <- py[i2]; y3 <- py[i3]
    xs <- c(xs, 0.5 * ((2 * x1) + (-x0 + x2) * tt +
      (2 * x0 - 5 * x1 + 4 * x2 - x3) * tt^2 +
      (-x0 + 3 * x1 - 3 * x2 + x3) * tt^3))
    ys <- c(ys, 0.5 * ((2 * y1) + (-y0 + y2) * tt +
      (2 * y0 - 5 * y1 + 4 * y2 - y3) * tt^2 +
      (-y0 + 3 * y1 - 3 * y2 + y3) * tt^3))
  }
  data.frame(x = xs, y = ys)
}

# --- Control points for the right lung (viewer's right); left lung mirrors x -> 1 - x ---
bl_lung_control_points <- function(side = c("right", "left")) {
  side <- match.arg(side)
  # Clockwise from apex. Apex leans toward centre; outer edge bulges; base wide/rounded;
  # inner edge near the midline with a small concave bronchus notch.
  px <- c(0.555, 0.640, 0.760, 0.875, 0.935, 0.940, 0.905, 0.820,
          0.690, 0.585, 0.560, 0.560, 0.530, 0.548)
  py <- c(0.795, 0.850, 0.840, 0.760, 0.600, 0.420, 0.250, 0.140,
          0.110, 0.150, 0.330, 0.520, 0.620, 0.710)
  if (identical(side, "left")) {
    px <- 1 - px
  }
  list(x = px, y = py)
}

bl_lung_outline <- function(side) {
  cp <- bl_lung_control_points(side)
  bl_catmull_rom_closed(cp$x, cp$y)
}

# --- Clip a closed polygon to the half-plane y <= y_thresh (Sutherland-Hodgman) ---
bl_clip_polygon_below <- function(df, y_thresh) {
  x <- df$x
  y <- df$y
  n <- length(x)
  if (n < 3L) {
    return(NULL)
  }
  ox <- numeric(0)
  oy <- numeric(0)
  for (i in seq_len(n)) {
    cx <- x[i]; cy <- y[i]
    j <- if (i == 1L) n else i - 1L
    pxv <- x[j]; pyv <- y[j]
    cur_in <- cy <= y_thresh
    prev_in <- pyv <= y_thresh
    if (cur_in) {
      if (!prev_in) {
        t <- (y_thresh - pyv) / (cy - pyv)
        ox <- c(ox, pxv + t * (cx - pxv)); oy <- c(oy, y_thresh)
      }
      ox <- c(ox, cx); oy <- c(oy, cy)
    } else if (prev_in) {
      t <- (y_thresh - pyv) / (cy - pyv)
      ox <- c(ox, pxv + t * (cx - pxv)); oy <- c(oy, y_thresh)
    }
  }
  if (length(ox) < 3L) {
    return(NULL)
  }
  data.frame(x = ox, y = oy)
}

# --- Trachea ladder + bronchi as line segments (drawn in every facet) ---
bl_lung_trachea_segments <- function() {
  rail_l <- 0.478
  rail_r <- 0.522
  top <- 0.985
  split <- 0.855
  rungs <- seq(split + 0.02, top - 0.005, length.out = 4L)

  segs <- data.frame(
    x = c(rail_l, rail_r),
    xend = c(rail_l, rail_r),
    y = c(split, split),
    yend = c(top, top)
  )
  rung_df <- data.frame(
    x = rail_l, xend = rail_r, y = rungs, yend = rungs
  )
  segs <- rbind(segs, rung_df)
  segs
}

bl_lung_bronchi_paths <- function() {
  # Two short curves from the trachea base into each lung apex.
  right <- data.frame(
    x = c(0.500, 0.512, 0.540, 0.553),
    y = c(0.855, 0.815, 0.780, 0.760),
    grp = "bronchus_r"
  )
  left <- data.frame(
    x = 1 - c(0.500, 0.512, 0.540, 0.553),
    y = c(0.855, 0.815, 0.780, 0.760),
    grp = "bronchus_l"
  )
  rbind(right, left)
}

bl_lung_exceedance_year_df <- function(no2_stats, pm25_stats) {
  no2 <- no2_stats$exceed_days_by_year
  pm25 <- pm25_stats$exceed_days_by_year
  if (is.null(no2) || is.null(pm25) || !nrow(no2) || !nrow(pm25)) {
    return(NULL)
  }

  years <- sort(unique(c(no2$year, pm25$year)))
  dplyr::bind_rows(lapply(years, function(yr) {
    n_row <- no2[no2$year == yr, , drop = FALSE]
    p_row <- pm25[pm25$year == yr, , drop = FALSE]
    if (!nrow(n_row) || !nrow(p_row)) {
      return(NULL)
    }
    data.frame(
      year = as.character(yr),
      no2_pct = as.numeric(n_row$exceed_pct[1]),
      no2_days = as.integer(n_row$exceed_days[1]),
      pm25_pct = as.numeric(p_row$exceed_pct[1]),
      pm25_days = as.integer(p_row$exceed_days[1])
    )
  }))
}

bl_lung_plot_text_sizes <- function(
    year = 13,
    pct = 5,
    days = 3.4,
    pollutant = 4,
    title = 11,
    subtitle = 11) {
  list(
    year = year, pct = pct, days = days, pollutant = pollutant,
    title = title, subtitle = subtitle
  )
}

BL_LUNG_PLOT_TEXT_SIZES_DEFAULT <- bl_lung_plot_text_sizes()

bl_resolve_lung_plot_text_sizes <- function(text_sizes = NULL) {
  if (is.null(text_sizes)) {
    return(BL_LUNG_PLOT_TEXT_SIZES_DEFAULT)
  }
  modifyList(BL_LUNG_PLOT_TEXT_SIZES_DEFAULT, as.list(text_sizes))
}

bl_plot_lung_exceedance <- function(
    no2_stats,
    pm25_stats,
    site_code = NULL,
    no2_color = "#7e0052",
    pm25_color = "black",
    text_sizes = NULL,
    plot_title = NULL,
    plot_subtitle = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Install ggplot2 for lung exceedance plot.", call. = FALSE)
  }

  sizes <- bl_resolve_lung_plot_text_sizes(text_sizes)

  plot_df <- bl_lung_exceedance_year_df(no2_stats, pm25_stats)
  if (is.null(plot_df) || !nrow(plot_df)) {
    return(NULL)
  }
  plot_df$year <- factor(plot_df$year, levels = plot_df$year)

  outlines <- list(left = bl_lung_outline("left"), right = bl_lung_outline("right"))
  centroids <- lapply(outlines, function(o) mean(range(o$x)))
  yranges <- lapply(outlines, function(o) range(o$y))

  grey_layers <- list()
  fill_layers <- list()
  outline_layers <- list()

  for (i in seq_len(nrow(plot_df))) {
    row <- plot_df[i, ]
    yr <- as.character(row$year)
    sides <- list(
      list(side = "left", pct = row$no2_pct, col = no2_color),
      list(side = "right", pct = row$pm25_pct, col = pm25_color)
    )
    for (s in sides) {
      outline <- outlines[[s$side]]
      yr_rng <- yranges[[s$side]]

      grey <- outline
      grey$year <- yr
      grey$grp <- paste(yr, s$side, "grey")
      grey_layers[[length(grey_layers) + 1L]] <- grey

      ol <- outline
      ol$year <- yr
      ol$grp <- paste(yr, s$side, "outline")
      outline_layers[[length(outline_layers) + 1L]] <- ol

      y_thresh <- yr_rng[1] + (yr_rng[2] - yr_rng[1]) * max(0, min(100, s$pct)) / 100
      fill <- bl_clip_polygon_below(outline, y_thresh)
      if (!is.null(fill)) {
        fill$year <- yr
        fill$grp <- paste(yr, s$side, "fill")
        fill$fill_col <- s$col
        fill_layers[[length(fill_layers) + 1L]] <- fill
      }
    }
  }

  grey_df <- dplyr::bind_rows(grey_layers)
  outline_df <- dplyr::bind_rows(outline_layers)
  fill_df <- dplyr::bind_rows(fill_layers)
  grey_df$year <- factor(grey_df$year, levels = levels(plot_df$year))
  outline_df$year <- factor(outline_df$year, levels = levels(plot_df$year))
  fill_df$year <- factor(fill_df$year, levels = levels(plot_df$year))

  cx_left <- centroids[["left"]]
  cx_right <- centroids[["right"]]
  yr_left <- yranges[["left"]]
  yr_right <- yranges[["right"]]

  label_df <- plot_df %>%
    dplyr::mutate(
      cx_left = cx_left,
      cx_right = cx_right,
      no2_days_y = yr_left[2] + 0.06,
      pm25_days_y = yr_right[2] + 0.06,
      no2_name_y = yr_left[1] - 0.05,
      pm25_name_y = yr_right[1] - 0.05,
      no2_fill_top = yr_left[1] + (yr_left[2] - yr_left[1]) * no2_pct / 100,
      pm25_fill_top = yr_right[1] + (yr_right[2] - yr_right[1]) * pm25_pct / 100,
      pct_label_gap = 0.055,
      no2_pct_y = no2_fill_top + pct_label_gap,
      pm25_pct_y = pm25_fill_top + pct_label_gap,
      no2_pct_label = paste0(no2_pct, "%"),
      pm25_pct_label = paste0(pm25_pct, "%"),
      no2_days_label = paste0(no2_days, " days"),
      pm25_days_label = paste0(pm25_days, " days"),
      no2_name_label = "NO[2]",
      pm25_name_label = "PM[2.5]"
    )

  trachea <- bl_lung_trachea_segments()
  bronchi <- bl_lung_bronchi_paths()

  p <- ggplot2::ggplot() +
    ggplot2::geom_polygon(
      data = grey_df,
      ggplot2::aes(x = x, y = y, group = grp),
      fill = "grey90", colour = NA
    ) +
    ggplot2::geom_polygon(
      data = fill_df,
      ggplot2::aes(x = x, y = y, group = grp, fill = fill_col),
      colour = NA
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::geom_path(
      data = outline_df,
      ggplot2::aes(x = x, y = y, group = grp),
      colour = "grey25", linewidth = 0.8
    ) +
    ggplot2::geom_segment(
      data = trachea,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
      colour = "grey25", linewidth = 0.8
    ) +
    ggplot2::geom_path(
      data = bronchi,
      ggplot2::aes(x = x, y = y, group = grp),
      colour = "grey25", linewidth = 0.8
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = cx_left, y = no2_pct_y, label = no2_pct_label),
      colour = no2_color, fontface = "bold", size = sizes$pct
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = cx_right, y = pm25_pct_y, label = pm25_pct_label),
      colour = pm25_color, fontface = "bold", size = sizes$pct
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = cx_left, y = no2_days_y, label = no2_days_label),
      size = sizes$days
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = cx_right, y = pm25_days_y, label = pm25_days_label),
      size = sizes$days
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = cx_left, y = no2_name_y, label = no2_name_label),
      colour = no2_color, fontface = "bold", size = sizes$pollutant,
      parse = TRUE
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = cx_right, y = pm25_name_y, label = pm25_name_label),
      colour = pm25_color, fontface = "bold", size = sizes$pollutant,
      parse = TRUE
    ) +
    ggplot2::facet_wrap(~year, nrow = 1) +
    ggplot2::coord_fixed(ratio = 1, xlim = c(0, 1), ylim = c(0.02, 1.06), clip = "off")

  if (!is.null(plot_title) || !is.null(plot_subtitle)) {
    p <- p + ggplot2::labs(title = plot_title, subtitle = plot_subtitle)
  }

  label_theme <- list(
    strip.text = ggplot2::element_text(face = "bold", size = sizes$year),
    plot.margin = ggplot2::margin(12, 12, 12, 12)
  )
  if (!is.null(plot_title)) {
    label_theme$plot.title <- ggplot2::element_text(
      face = "bold", size = sizes$title
    )
  }
  if (!is.null(plot_subtitle)) {
    label_theme$plot.subtitle <- ggplot2::element_text(size = sizes$subtitle)
  }

  p +
    ggplot2::theme_void(base_size = 12) +
    ggplot2::theme(!!!label_theme)
}
