# Custom knit handler for QuarterlyAQtrends_git.Rmd (RStudio Knit button).
knit_quarterly_report <- function(inputFile, ...) {
  root <- dirname(normalizePath(inputFile))
  owd <- getwd()
  setwd(root)
  on.exit(setwd(owd), add = TRUE)

  output_dir <- file.path("output", "Test reports")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  fm <- rmarkdown::yaml_front_matter(inputFile)
  site_code <- fm$params$site_code
  if (is.null(site_code) || !nzchar(site_code)) {
    source("R/bl_api.R", local = TRUE)
    bl_load_env()
    site_code <- bl_env("BL_SITE_CODE", unset = "UNKNOWN")
  }

  output_file <- sprintf(
    "QuarterlyAQtrends_%s_%s.pdf",
    site_code,
    format(Sys.time(), "%Y%m%d_%H%M%S")
  )

  rmarkdown::render(
    inputFile,
    output_dir = output_dir,
    output_file = output_file,
    envir = new.env(parent = globalenv()),
    ...
  )
}
