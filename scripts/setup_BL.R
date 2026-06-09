# Set project root and load bl_api.R (for interactive R console or other scripts).
# Usage from anywhere:
#   source("~/Desktop/Code/BreatheLondon_Community_QuarterlyReports/scripts/setup_BL.R")

bl_set_project_root <- function() {
  candidates <- c(
    Sys.getenv("BL_PROJECT_ROOT", unset = ""),
    getwd(),
    if (basename(getwd()) == "scripts") normalizePath("..", mustWork = FALSE),
    file.path(getwd(), "BreatheLondon_Community_QuarterlyReports"),
    "~/Desktop/Code/BreatheLondon_Community_QuarterlyReports"
  )
  for (root in unique(candidates[nzchar(candidates)])) {
    root <- normalizePath(path.expand(root), mustWork = FALSE)
    if (file.exists(file.path(root, "R/bl_api.R"))) {
      setwd(root)
      return(invisible(root))
    }
  }
  stop(
    "Could not find project root (folder with R/bl_api.R).\n",
    "  setwd('~/Desktop/Code/BreatheLondon_Community_QuarterlyReports')",
    call. = FALSE
  )
}

bl_set_project_root()
source("scripts/load_env.R", local = TRUE)
source("R/bl_api.R", local = TRUE)
bl_load_env()
message("Project root: ", getwd())
