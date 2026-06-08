# Breathe London Community Quarterly Reports

R Markdown quarterly air quality reports for Breathe London Community Programme nodes.

## Configure `.env`

Copy [`.env.example`](.env.example) to `.env` and set:

| Variable | Purpose |
|----------|---------|
| `year_of_report` | e.g. `2025` — used in `${year_of_report}` |
| `BL_SITE_CODE` | Sensor code |
| `BL_DATA_SOURCE` | `csv` or `api` |
| Report dates | **Automatic** — last completed calendar quarter (`Rscript scripts/show_api_times.R`) |

Weekday (`Wed`, `Fri`, …) is added in R when calling the API. Preview: `Rscript scripts/show_api_times.R`

### PM2.5 multi-site plot (optional)

Copy plot keys from [`.env.example`](.env.example) into `.env`:

| Variable | Purpose |
|----------|---------|
| `BL_PLOT_MODE` | `all` = every site in `listSensors.json`; `selected` = `BL_PLOT_SITE_CODES`; `single` = `BL_SITE_CODE` |
| `BL_PLOT_SITE_CODES` | Only for `selected` — ignored when mode is `all` |
| `BL_PLOT_USE_CACHE` | `1` = load `BL_PLOT_CACHE_CSV` and skip API |
| `BL_PLOT_CACHE_CSV` | Long-format cache (`SiteCode`, `date`, `pm25`) |
| `BL_PLOT_OUTPUT` | PNG path |
| `BL_PLOT_AGG` | `hourly` or `daily` (daily uses `openair::timeAverage`) |
| `BL_PLOT_START_DATE` / `BL_PLOT_END_DATE` | Plot-only window (same format as report dates). **Leave both empty** for per-site `StartDate`–`EndDate` from `listSensors.json` (formal decommission date, not bulletin sync) — does not use `BL_START_DATE` / `BL_END_DATE` |

```bash
Rscript scripts/fetch_sensors.R
Rscript scripts/generate_plots.R
```

Plot helpers live in `R/bl_plot_api.R` (sourced by `generate_plots.R`); `R/bl_api.R` is for reports and shared API access only.

Fetching all ~600 sites can take a long time; partial runs resume from the cache CSV.

## Run a report

From the project root in a terminal:

### Option A — CSV (recommended for re-knitting)

```bash
# 1. Fetch data (writes data/processed/*.csv)
Rscript scripts/fetch_readings.R

# 2. Ensure .env has BL_DATA_SOURCE=csv, then knit
Rscript -e 'rmarkdown::render("QuarterlyAQtrends_git.Rmd")'
```

### Option B — API direct (no CSV step)

In `.env` set `BL_DATA_SOURCE=api`, then:

```bash
Rscript -e 'rmarkdown::render("QuarterlyAQtrends_git.Rmd")'
```

The `.Rmd` calls the API during knit (slower; needs network and key).

## Editor tasks (optional)

Editors that support [VS Code tasks](https://code.visualstudio.com/docs/editor/tasks) (e.g. VS Code) can run the scripts from `.vscode/tasks.json` via **Terminal → Run Task**:

| Task | Command |
|------|---------|
| Fetch sensor list | `Rscript scripts/fetch_sensors.R` |
| Fetch readings | `Rscript scripts/fetch_readings.R` |
| Generate PM2.5 all-sites plot | `Rscript scripts/generate_plots.R` |
| Knit quarterly report (PDF) | `Rscript -e 'rmarkdown::render("QuarterlyAQtrends_git.Rmd")'` |

These match the terminal commands above; use whichever workflow you prefer.

## Dependencies

```bash
Rscript -e 'install.packages(c("httr2", "jsonlite", "rmarkdown", "knitr", "tidyverse", "cowplot", "lubridate", "openair"), repos="https://cloud.r-project.org")'
brew install pandoc
```

LaTeX (`pdflatex`) required for PDF output.

## API docs

[https://www.breathelondon-communities.org/developers](https://www.breathelondon-communities.org/developers)
