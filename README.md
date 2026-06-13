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
Rscript scripts/render_quarterly_report.R
```

### Option B — API direct (no CSV step)

In `.env` set `BL_DATA_SOURCE=api`, then:

```bash
Rscript scripts/render_quarterly_report.R
```

The `.Rmd` calls the API during knit (slower; needs network and key).

### Summary-of-data-to-date logic

The **Summary of data to date** boxes only use measurements through the **end of the report quarter** (not the latest fetched row). This keeps the quarterly report internally consistent.

The annual exceedance breakdown in those boxes follows these rules:

| Report quarter | Report year in annual breakdown |
|----------------|----------------------------------|
| **Q1** | Omitted — that quarter already has its own summary box |
| **Q2–Q4** | Included — counts exceedances from 1 Jan through the end of the report quarter |

Prior calendar years always show the full year (within the available measurement period).

Each year line in the annual breakdown is formatted as `2022 122 days (43.7%)`. The day count is the number of exceedance days in that year. The percentage is the **share of all days with data in that calendar year** that exceeded the WHO daily mean guideline (exceedance days ÷ total days × 100, rounded to one decimal place). These percentages are independent per year and do not sum to 100% across years.

### Marylebone Road comparison paragraphs

Each pollutant **Summary of Q1** (etc.) bordered box may include a final bullet comparing the community node with **Marylebone Road (AURN MY1)**. The “Summary of data to date” boxes do not include this text.

**Reference data loading (RData first — no API when cached):**

If `data/processed/marylebone.RData` exists (or the path in `BL_MARYLEBONE_RDATA`), the report **loads that file and does not call openair**. The file must contain an object named `marylebone` with hourly `date`, `no2`, and `pm2.5` columns.

When the RData file is **missing**, the first report knit fetches MY1 via `openair::importUKAQ()` and **automatically saves** `data/processed/marylebone.RData`. Later reports (including mass generation across many sites) reuse the cache and do not call openair again.

```bash
# Optional: refresh the cache manually (delete the RData file first, or overwrite)
source("scripts/analysis_BL.R")
marylebone <- get_marylebone_openair()
save(marylebone, file = "data/processed/marylebone.RData")
```

**Which narrative (A, B, or C) is shown?** Evaluated **independently** per pollutant (both may be C, or A for NO₂ and B for PM₂.₅, etc.):

| Option | Period | ±25% gate? |
|--------|--------|------------|
| **A** | Whole-week morning rush (07:00–10:00) | Yes — community mean within 75–125% of MY1 |
| **B** | Whole-week afternoons (12:00–18:00), spike days in top 25% | Yes — same gate on spike-day means |
| **C** | Weekday school pick-up (15:00–16:30) | **No** — catch-all when neither A nor B qualifies |

If A or B passes the gate, the one with the **higher cumulative load** (sum of hourly community concentrations in that window over the report quarter) is used. If neither passes, **C** is shown.

Each comparative bullet carries a superscript footnote (numbered after the typical-peak footnote) explaining how that pollutant’s paragraph was calculated for the selected option.

Preview selection for the current site and quarter:

```bash
Rscript scripts/test_marylebone_narrative.R
```

### Report output location

Knitted PDFs are written to `output/Test reports/` with a timestamp in the filename, e.g. `QuarterlyAQtrends_20250612_143052.pdf`.

This is configured in the `knit:` field at the top of `QuarterlyAQtrends_git.Rmd`. Always knit from the **project root** (the folder containing `R/bl_api.R`).

| How you knit | Output path |
|--------------|-------------|
| **RStudio** — Knit button (Ctrl/Cmd+Shift+K) | `output/Test reports/QuarterlyAQtrends_YYYYMMDD_HHMMSS.pdf` |
| **VS Code** — Knit button | Same as RStudio, if **smart knitting** is enabled (`r.rmarkdown.knit.useBackgroundProcess: true` in `.vscode/settings.json`) |
| **Terminal / VS Code task** — `Rscript scripts/render_quarterly_report.R` | Same as above |

**Note:** Running `rmarkdown::render("QuarterlyAQtrends_git.Rmd")` directly in the R console does **not** use the custom output path and will write `QuarterlyAQtrends_git.pdf` next to the `.Rmd`. Use the Knit button or `scripts/render_quarterly_report.R` instead.

## Editor tasks (optional)

Editors that support [VS Code tasks](https://code.visualstudio.com/docs/editor/tasks) (e.g. VS Code) can run the scripts from `.vscode/tasks.json` via **Terminal → Run Task**:

| Task | Command |
|------|---------|
| Fetch sensor list | `Rscript scripts/fetch_sensors.R` |
| Fetch readings | `Rscript scripts/fetch_readings.R` |
| Generate PM2.5 all-sites plot | `Rscript scripts/generate_plots.R` |
| Knit quarterly report (PDF) | `Rscript scripts/render_quarterly_report.R` |

These match the terminal commands above; use whichever workflow you prefer.

## Dependencies

```bash
Rscript -e 'install.packages(c("httr2", "jsonlite", "rmarkdown", "knitr", "tidyverse", "cowplot", "lubridate", "openair"), repos="https://cloud.r-project.org")'
brew install pandoc
```

LaTeX (`pdflatex`) required for PDF output.

## API docs

[https://www.breathelondon-communities.org/developers](https://www.breathelondon-communities.org/developers)
