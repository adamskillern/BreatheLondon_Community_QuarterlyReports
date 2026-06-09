#!/usr/bin/env Rscript
# Show API datetime strings (with weekday added automatically)

root <- getwd()
if (basename(root) == "scripts") {
  root <- normalizePath(file.path(root, ".."))
}
setwd(root)

source("R/bl_api.R", local = TRUE)
bl_load_env()

report_q <- bl_last_completed_quarter()
fetch <- bl_resolve_site_fetch_window()
cat("Site: ", fetch$site_code, "\n", sep = "")
cat("All data to date: ", format(fetch$start), " to ", format(fetch$end), "\n", sep = "")
cat("Report quarter: Q", report_q$quarter, " ", report_q$year,
    " (", format(report_q$start), " to ", format(report_q$end), ")\n", sep = "")
cat("\n")

cat("Sent to API:\n")
cat("  start:", bl_resolve_fetch_start(), "\n")
cat("  end:  ", bl_resolve_fetch_end(), "\n")
