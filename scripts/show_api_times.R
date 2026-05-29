#!/usr/bin/env Rscript
# Show API datetime strings (with weekday added automatically)

root <- getwd()
if (basename(root) == "scripts") {
  root <- normalizePath(file.path(root, ".."))
}
setwd(root)

source("R/bl_api.R", local = TRUE)
bl_load_env()

cat("From .env (no weekday):\n")
cat("  BL_START_DATE:", bl_env("BL_START_DATE"), "\n")
cat("  BL_END_DATE:  ", bl_env("BL_END_DATE"), "\n\n")
cat("Sent to API:\n")
cat("  start:", bl_resolve_fetch_start(), "\n")
cat("  end:  ", bl_resolve_fetch_end(), "\n")
