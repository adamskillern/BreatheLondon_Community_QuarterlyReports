# Set project root and load bl_api.R (for interactive R console or other scripts).
# Usage (from project root or scripts/):
#   source("scripts/setup_BL.R")

bl_set_project_root <- function() {
  candidates <- c(
    Sys.getenv("BL_PROJECT_ROOT", unset = ""),
    getwd(),
    if (basename(getwd()) == "scripts") normalizePath("..", mustWork = FALSE)
  )
  for (root in unique(candidates[nzchar(candidates)])) {
    root <- normalizePath(root, mustWork = FALSE)
    if (file.exists(file.path(root, "R/bl_api.R"))) {
      setwd(root)
      return(invisible(root))
    }
  }
  stop(
    "Could not find project root (folder with R/bl_api.R).\n",
    "  setwd() to the repo root, or set BL_PROJECT_ROOT.",
    call. = FALSE
  )
}

bl_set_project_root()
source("scripts/load_env.R")
source("R/bl_api.R")
bl_load_env()
message("Project root: ", getwd())
