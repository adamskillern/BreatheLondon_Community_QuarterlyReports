#!/usr/bin/env Rscript
# PM2.5 NWR polar plots on a Leaflet map (openairmaps::polarMap) for BLC CLDP sites.
#
# Uses the same data window and wind module as scripts/polar_plots.R.
# Builds one custom polar marker PNG per site (large N/E/S/W + wind-speed
# scale with an inline "ws" label), all sharing one colour scale, then places
# them on a CartoDB Voyager basemap with large SiteName labels.
#
# Run from project root:
#   Rscript scripts/polar_map_nwr.R
#
# Outputs:
#   output/polar_plots/pm25_nwr_polar_map.html
#   output/polar_plots/marker_<SiteCode>.png

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
BL_POLAR_MAP_HTML <- file.path(BL_POLAR_PLOT_DIR, "pm25_nwr_polar_map.html")

bl_ensure_pkg <- function(pkg, repos = NULL) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    return(invisible(TRUE))
  }
  message("Installing ", pkg, " ...")
  if (is.null(repos)) {
    repos <- c("https://cloud.r-project.org")
  }
  install.packages(pkg, repos = repos)
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Failed to install package: ", pkg, call. = FALSE)
  }
  invisible(TRUE)
}

bl_ensure_map_deps <- function() {
  bl_ensure_pkg("openair")
  bl_ensure_pkg("ggplot2")
  bl_ensure_pkg("scales")
  bl_ensure_pkg("leaflet")
  bl_ensure_pkg("htmlwidgets")
}

# Text sizing for the polar markers (openair::polarPlot fontsize + inline "ws").
# Markers are rendered at a fixed physical size (so the big fonts stay in
# proportion) and only downscaled for display on the map.
BL_MARKER_FONTSIZE <- 20
BL_MARKER_DPI <- 150
BL_MARKER_RENDER_IN <- 3.6
BL_MARKER_ICON_PX <- 230

bl_site_coords <- function(site_codes, sensors_path = "data/raw/listSensors.json") {
  sensors <- bl_read_sensors_json(sensors_path)
  out <- lapply(site_codes, function(sc) {
    row <- sensors[sensors$SiteCode == sc, , drop = FALSE][1, , drop = FALSE]
    if (!nrow(row)) {
      stop("Site not found in sensor list: ", sc, call. = FALSE)
    }
    data.frame(
      SiteCode = sc,
      SiteName = trimws(as.character(row$SiteName[1])),
      MapLabel = paste0(
        trimws(as.character(row$SiteName[1])),
        " - ",
        sc
      ),
      latitude = as.numeric(row$Latitude[1]),
      longitude = as.numeric(row$Longitude[1]),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(out)
}

# Build one transparent PNG polar marker per site, all sharing `limits`.
# Returns a named vector of PNG paths keyed by SiteCode plus the shared limits.
bl_build_marker_pngs <- function(site_dfs, outdir, fontsize = BL_MARKER_FONTSIZE) {
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  # Pass 1: shared colour limits across all sites (from the NWR surfaces).
  message("Computing NWR surfaces for ", length(site_dfs), " site(s) ...")
  z_range <- range(
    unlist(lapply(site_dfs, function(df) {
      o <- openair::polarPlot(df, pollutant = "pm25", statistic = "nwr", plot = FALSE)
      range(o$data$z, na.rm = TRUE)
    })),
    na.rm = TRUE
  )
  limits <- c(floor(z_range[1] * 2) / 2, ceiling(z_range[2] * 2) / 2)

  # Pass 2: render each marker with the shared colour scale applied directly.
  side_in <- BL_MARKER_RENDER_IN
  paths <- character(0)
  for (sc in names(site_dfs)) {
    obj <- openair::polarPlot(
      site_dfs[[sc]],
      pollutant = "pm25",
      statistic = "nwr",
      limits = limits,
      cols = "turbo",
      key.position = "none",
      fontsize = fontsize,
      annotate = TRUE,   # keeps the large N/E/S/W compass letters
      caption = "",       # drop the default "Radial axis shows ..." footer
      plot = FALSE
    )
    p <- obj$plot +
      ggplot2::annotate(
        "text",
        x = I(0.30), y = I(0.74),
        label = "ws", fontface = "bold", size = fontsize / 3
      ) +
      ggplot2::theme(
        plot.background = ggplot2::element_blank(),
        panel.background = ggplot2::element_blank(),
        plot.margin = grid::unit(rep(3, 4), "pt"),
        legend.position = "none"
      )
    f <- file.path(outdir, paste0("marker_", sc, ".png"))
    suppressMessages(suppressWarnings(
      ggplot2::ggsave(
        f, plot = p,
        width = side_in, height = side_in,
        dpi = BL_MARKER_DPI, bg = "transparent"
      )
    ))
    paths[sc] <- normalizePath(f)
  }

  list(paths = paths, limits = limits)
}

bl_add_site_labels <- function(p_map, coords, d_icon) {
  label_style <- list(
    "font-size" = "20px",
    "font-weight" = "700",
    "color" = "#101010",
    "background" = "rgba(255,255,255,0.6)",
    "padding" = "2px 8px",
    "border-radius" = "5px",
    "border" = "0px",
    "box-shadow" = "none",
    "white-space" = "nowrap",
    "text-shadow" =
      "-1px -1px 2px #fff, 1px -1px 2px #fff, -1px 1px 2px #fff, 1px 1px 2px #fff"
  )

  leaflet::addLabelOnlyMarkers(
    p_map,
    lng = coords$longitude,
    lat = coords$latitude,
    label = coords$MapLabel,
    labelOptions = leaflet::labelOptions(
      noHide = TRUE,
      direction = "top",
      # Sit just above the polar marker (smaller offset = closer).
      offset = c(0, -(d_icon / 2 - 28)),
      textOnly = TRUE,
      style = label_style
    )
  )
}

bl_save_polar_map <- function(site_dfs, coords, out_html) {
  bl_ensure_map_deps()

  d_icon <- BL_MARKER_ICON_PX
  markers <- bl_build_marker_pngs(site_dfs, dirname(out_html))
  message(
    "Shared NWR colour scale: ", markers$limits[1], " – ", markers$limits[2],
    " (mean PM2.5)"
  )

  turbo <- openair::openColours("turbo", 100)
  pal <- leaflet::colorNumeric(turbo, domain = markers$limits)

  p_map <- leaflet::leaflet()
  p_map <- leaflet::addProviderTiles(p_map, "CartoDB.Voyager")

  for (i in seq_len(nrow(coords))) {
    sc <- coords$SiteCode[i]
    if (is.na(markers$paths[sc])) next
    icon <- leaflet::makeIcon(
      iconUrl = markers$paths[[sc]],
      iconWidth = d_icon,
      iconHeight = d_icon,
      iconAnchorX = d_icon / 2,
      iconAnchorY = d_icon / 2
    )
    p_map <- leaflet::addMarkers(
      p_map,
      lng = coords$longitude[i],
      lat = coords$latitude[i],
      icon = icon,
      popup = paste0(
        "<b>", coords$SiteName[i], "</b><br>",
        coords$MapLabel[i]
      )
    )
  }

  p_map <- bl_add_site_labels(p_map, coords, d_icon)

  p_map <- leaflet::addLegend(
    p_map,
    position = "topright",
    pal = pal,
    values = markers$limits,
    title = "Mean PM<sub>2.5</sub>",
    opacity = 1
  )
  # Flip the continuous bar so high values sit at the top, without
  # rewriting the gradient colour string (that breaks on rgb(...)).
  p_map <- htmlwidgets::onRender(
    p_map,
    "
function(el, x) {
  var legend = el.querySelector('.legend');
  if (!legend) return;
  var grad = legend.querySelector('span[style*=\"linear-gradient\"]');
  var svg = legend.querySelector('svg');
  if (grad) {
    grad.style.transform = 'scaleY(-1)';
    grad.style.transformOrigin = 'center';
  }
  if (svg) {
    var texts = Array.prototype.slice.call(svg.querySelectorAll('text'));
    var labels = texts.map(function(t) { return t.textContent; });
    texts.forEach(function(t, i) {
      t.textContent = labels[labels.length - 1 - i];
    });
  }
}
"
  )
  p_map <- leaflet::fitBounds(
    p_map,
    lng1 = min(coords$longitude) - 0.02, lat1 = min(coords$latitude) - 0.02,
    lng2 = max(coords$longitude) + 0.02, lat2 = max(coords$latitude) + 0.02
  )

  dir.create(dirname(out_html), recursive = TRUE, showWarnings = FALSE)
  htmlwidgets::saveWidget(p_map, file = out_html, selfcontained = TRUE)
  message("Saved map: ", out_html)

  invisible(list(html = out_html, limits = markers$limits))
}

setwd(bl_find_project_root())
source("scripts/setup_BL.R")

if (!file.exists(BL_POLAR_RDATA)) {
  stop(
    "Polar analysis cache not found: ", BL_POLAR_RDATA, "\n",
    "Run first: Rscript scripts/polar_plots.R",
    call. = FALSE
  )
}

load(BL_POLAR_RDATA)
if (!exists("polar_data")) {
  stop("RData does not contain polar_data: ", BL_POLAR_RDATA, call. = FALSE)
}

missing <- setdiff(BL_POLAR_SITE_CODES, names(polar_data))
if (length(missing)) {
  stop("Missing site(s) in polar_data: ", paste(missing, collapse = ", "), call. = FALSE)
}

coords <- bl_site_coords(BL_POLAR_SITE_CODES)

site_dfs <- stats::setNames(
  lapply(BL_POLAR_SITE_CODES, function(sc) polar_data[[sc]]),
  BL_POLAR_SITE_CODES
)
empty <- vapply(site_dfs, function(df) is.null(df) || !nrow(df), logical(1))
if (any(empty)) {
  warning("Dropping site(s) with no data: ",
          paste(names(site_dfs)[empty], collapse = ", "), call. = FALSE)
  site_dfs <- site_dfs[!empty]
  coords <- coords[coords$SiteCode %in% names(site_dfs), , drop = FALSE]
}

message(
  "Sites on map: ", paste(names(site_dfs), collapse = ", "),
  " (", sum(vapply(site_dfs, nrow, integer(1))), " paired hourly rows total)"
)

bl_save_polar_map(site_dfs, coords, BL_POLAR_MAP_HTML)
