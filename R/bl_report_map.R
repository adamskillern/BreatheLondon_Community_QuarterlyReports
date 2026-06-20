# Sensor location map for quarterly report title page (OpenStreetMap tiles + PNG icon).
# Site coordinates come from listSensors.json via bl_site_location() in R/bl_api.R.
#
# Approach: stitch OSM tiles, find the sensor's exact pixel, crop a square centred
# on that pixel, then composite the icon at the centre. This keeps the sensor at
# the true map centre and the icon visually centred, for any location/zoom/icon.

bl_lon_to_tile_x <- function(lon, zoom) {
  floor((lon + 180) / 360 * 2^zoom)
}

bl_lat_to_tile_y <- function(lat, zoom) {
  lat_rad <- lat * pi / 180
  floor((1 - log(tan(lat_rad) + 1 / cos(lat_rad)) / pi) / 2 * 2^zoom)
}

# Global Web Mercator pixel coordinates (256 px tiles) for a lon/lat at this zoom.
bl_lonlat_to_global_px <- function(lon, lat, zoom, tile_px = 256) {
  n <- 2^zoom
  lat_rad <- lat * pi / 180
  px <- (lon + 180) / 360 * n * tile_px
  py <- (1 - log(tan(lat_rad) + 1 / cos(lat_rad)) / pi) / 2 * n * tile_px
  c(px = px, py = py)
}

# Download a grid of tiles around the sensor and stitch into one image.
# Returns the stitched image plus the sensor's pixel position within it.
bl_build_osm_mosaic <- function(lon, lat, zoom = 16L, tile_radius = 2L, tile_px = 256) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop("Install magick for the sensor location map.", call. = FALSE)
  }
  xc <- bl_lon_to_tile_x(lon, zoom)
  yc <- bl_lat_to_tile_y(lat, zoom)
  xs <- (xc - tile_radius):(xc + tile_radius)
  ys <- (yc - tile_radius):(yc + tile_radius)

  tile_list <- list()
  for (y in ys) {
    for (x in xs) {
      url <- sprintf("https://tile.openstreetmap.org/%d/%d/%d.png", zoom, x, y)
      tmp <- tempfile(fileext = ".png")
      utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
      tile_list[[length(tile_list) + 1L]] <- list(
        img = magick::image_read(tmp),
        x = x,
        y = y
      )
    }
  }

  row_imgs <- lapply(ys, function(y) {
    row_tiles <- Filter(function(t) t$y == y, tile_list)
    row_tiles <- row_tiles[order(vapply(row_tiles, function(t) t$x, numeric(1)))]
    imgs <- lapply(row_tiles, function(t) t$img)
    do.call(c, imgs) |> magick::image_append(stack = FALSE)
  })
  mosaic <- do.call(c, row_imgs) |> magick::image_append(stack = TRUE)

  # Sensor pixel within the mosaic = global px minus the mosaic's top-left origin.
  origin_px <- min(xs) * tile_px
  origin_py <- min(ys) * tile_px
  sensor_global <- bl_lonlat_to_global_px(lon, lat, zoom, tile_px)
  list(
    image = mosaic,
    sensor_px = sensor_global[["px"]] - origin_px,
    sensor_py = sensor_global[["py"]] - origin_py
  )
}

# Render the sensor map to a PNG file: rectangular crop centred on the sensor with
# the icon composited at the centre. aspect_ratio is width / height (>1 = landscape,
# so the short sides are vertical). Returns the output path (for include_graphics).
bl_render_sensor_location_map <- function(
    latitude,
    longitude,
    icon_png = "figure/Sensor-blue-V1.png",
    out_path = NULL,
    zoom = 16L,
    tile_radius = 2L,
    crop_fraction = 0.62,
    aspect_ratio = 16 / 9,
    icon_scale = 0.12
) {
  if (!file.exists(icon_png)) {
    stop("Sensor icon not found: ", icon_png, call. = FALSE)
  }
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop("Install magick for the sensor location map.", call. = FALSE)
  }

  mosaic <- bl_build_osm_mosaic(longitude, latitude, zoom, tile_radius)
  info <- magick::image_info(mosaic$image)
  sx <- mosaic$sensor_px
  sy <- mosaic$sensor_py

  # Largest rectangle (width:height = aspect_ratio) centred on the sensor that fits
  # inside the mosaic, scaled down by crop_fraction for context around the sensor.
  half_w_max <- min(sx, info$width - sx)
  half_h_max <- min(sy, info$height - sy)
  half_h <- min(half_h_max, half_w_max / aspect_ratio) * crop_fraction
  half_w <- half_h * aspect_ratio
  width <- floor(2 * half_w)
  height <- floor(2 * half_h)
  x_off <- round(sx - half_w)
  y_off <- round(sy - half_h)

  cropped <- magick::image_crop(
    mosaic$image,
    geometry = sprintf("%dx%d+%d+%d", width, height, x_off, y_off)
  )

  # Icon sized as a fraction of the cropped map height, composited dead-centre.
  icon <- magick::image_read(icon_png) |> magick::image_trim()
  icon_w <- max(1L, round(height * icon_scale))
  icon <- magick::image_resize(icon, sprintf("%dx", icon_w))
  composed <- magick::image_composite(cropped, icon, gravity = "center")

  if (is.null(out_path)) {
    out_path <- tempfile(fileext = ".png")
  }
  magick::image_write(composed, path = out_path, format = "png")
  out_path
}

# Render map for BL_SITE_CODE using Latitude/Longitude from listSensors.json.
bl_render_site_location_map <- function(
    site = NULL,
    sensors_path = "data/raw/listSensors.json",
    icon_png = "figure/Sensor-blue-V1.png",
    ...
) {
  loc <- bl_site_location(site = site, sensors_path = sensors_path)
  bl_render_sensor_location_map(
    latitude = loc$latitude,
    longitude = loc$longitude,
    icon_png = icon_png,
    ...
  )
}
