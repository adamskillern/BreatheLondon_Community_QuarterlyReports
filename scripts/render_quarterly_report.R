#!/usr/bin/env Rscript

if (!file.exists("QuarterlyAQtrends_git.Rmd")) {
  stop("Run from the project root (folder containing QuarterlyAQtrends_git.Rmd).")
}

output_dir <- file.path("output", "Test reports")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

output_file <- sprintf(
  "QuarterlyAQtrends_%s.pdf",
  format(Sys.time(), "%Y%m%d_%H%M%S")
)

rmarkdown::render(
  "QuarterlyAQtrends_git.Rmd",
  output_dir = output_dir,
  output_file = output_file
)
