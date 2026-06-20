#!/usr/bin/env Rscript

if (!file.exists("QuarterlyAQtrends_git.Rmd")) {
  stop("Run from the project root (folder containing QuarterlyAQtrends_git.Rmd).")
}

args <- commandArgs(trailingOnly = TRUE)

source("R/bl_api.R", local = TRUE)
bl_load_env()

site_codes <- if (length(args)) {
  bl_parse_site_code_list(paste(args, collapse = ","))
} else {
  bl_resolve_report_site_codes()
}

output_dir <- file.path("output", "Test reports")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Rendering ", length(site_codes), " report(s): ", paste(site_codes, collapse = ", "))

for (site_code in site_codes) {
  output_file <- sprintf(
    "QuarterlyAQtrends_%s_%s.pdf",
    site_code,
    format(Sys.time(), "%Y%m%d_%H%M%S")
  )
  message("  ", site_code, " -> ", file.path(output_dir, output_file))
  rmarkdown::render(
    "QuarterlyAQtrends_git.Rmd",
    output_dir = output_dir,
    output_file = output_file,
    params = list(site_code = site_code),
    envir = new.env(parent = globalenv())
  )
}
