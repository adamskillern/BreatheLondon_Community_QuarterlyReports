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
cat("Report quarter: Q", report_q$quarter, " ", report_q$year, "\n", sep = "")
cat("  all data fetch:  ", format(report_q$fetch_start), " to ", format(report_q$fetch_end), "\n", sep = "")
cat("  quarter overlay: ", format(report_q$start), " to ", format(report_q$end), "\n\n", sep = "")

cat("Sent to API:\n")
cat("  start:", bl_resolve_fetch_start(), "\n")
cat("  end:  ", bl_resolve_fetch_end(), "\n")
