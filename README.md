# Breathe London Community Quarterly Reports

R Markdown quarterly air quality reports for Breathe London Community Programme nodes.

## Configure `.env`

Copy [`.env.example`](.env.example) to `.env` and set:

| Variable | Purpose |
|----------|---------|
| `year_of_report` | e.g. `2025` — used in `${year_of_report}` |
| `BL_SITE_CODE` | Single sensor fallback |
| `BL_REPORT_SITE_CODES` | Optional temporary override (comma-separated). Leave blank to use `reportSensors.json` |
| `BL_REPORT_SENSORS_JSON` | Path to report site list (default `data/raw/reportSensors.json`) |
| `BL_DATA_SOURCE` | `csv` or `api` |
| Report dates | **Automatic** — last completed calendar quarter (`Rscript scripts/show_api_times.R`) |

**Report sites:** edit [`data/raw/reportSensors.json`](data/raw/reportSensors.json) — the canonical list for quarterly reports and report-related data. `BL_REPORT_SITE_CODES` overrides it only when set.

Weekday (`Wed`, `Fri`, …) is added in R when calling the API. Preview: `Rscript scripts/show_api_times.R`

## Analyse data (R console)

Load community node data and Marylebone Road (MY1) reference for interactive analysis with `scripts/analysis_BL.R`. Sites come from `reportSensors.json` (or `BL_REPORT_SITE_CODES` / `BL_SITE_CODE` if set). Node data respects `BL_DATA_SOURCE` (`api` or `csv`).

**QA default:** raw API values — no rounding, zeros kept as `0` (not `NA`). Quarterly reports still use cleaned data. Pass `bl_load_analysis_data(raw = FALSE)` for report-style cleaning. CSV files written by `fetch_readings.R` are already cleaned; use `BL_DATA_SOURCE=api` for true raw values.

From anywhere (e.g. a parent folder such as `Code`):

```r
source("BreatheLondon_Community_QuarterlyReports/scripts/analysis_BL.R")
```

That gives you:

| Object | What it is |
|--------|------------|
| `site_codes` | All sites from `reportSensors.json` (or `.env` override) |
| `site_code` | First site in that list, e.g. `CLDP0299` |
| `no2_df` / `pm25_df` | Hourly data for `site_code` (`date` + pollutant column) |
| `nodes` | Named list of all sites, e.g. `nodes[["CLDP0470"]]$no2` |
| `marylebone_df` | Marylebone Road (MY1) reference (`date`, `no2`, `pm2.5`) |

A typical run loads every site in `BL_REPORT_SITE_CODES` (~34k hourly rows per site for a full deployment history; Marylebone loads from `data/processed/marylebone.RData` when cached).

**Other sites:**

```r
no2_df  <- nodes[["CLDP0470"]]$no2
pm25_df <- nodes[["CLDP0470"]]$pm25
```

Or reload one site:

```r
bl_load_analysis_data("CLDP0470")
```

From the project root you can also run `Rscript scripts/analysis_BL.R` (same data load, non-interactive).

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

Always run commands from the **project root** in a terminal — the folder that contains `QuarterlyAQtrends_git.Rmd`, `R/bl_api.R`, and `.env`:

```bash
cd /path/to/BreatheLondon_Community_QuarterlyReports
```

### Report variants

There are two full quarterly PDF reports. They share the same data, summaries, and diurnal charts; only the **annual WHO exceedance** section differs:

| File | Annual exceedance visual |
|------|---------------------------|
| **`QuarterlyAQtrends_git.Rmd`** | Stacked **bar charts** (one per pollutant, before each “Summary of data to date” box) |
| **`QuarterlyAQtrends_lungs.Rmd`** | **Lung plot** (left = NO₂, right = PM₂.₅, one pair per calendar year) in a single section after the PM₂.₅ summary |

Plot code for the lungs variant lives in `R/bl_lung_exceedance_plot.R`.

### One sensor vs multiple sensors

| Goal | Bar-chart report | Lungs report |
|------|------------------|--------------|
| **One PDF** (single site) | **Knit** `QuarterlyAQtrends_git.Rmd`, or `Rscript scripts/render_quarterly_report.R CLDP0470` | **Knit** `QuarterlyAQtrends_lungs.Rmd`, or `Rscript scripts/render_lungs_report.R CLDP0470` |
| **Multiple PDFs** (one per site in `BL_REPORT_SITE_CODES`) | `Rscript scripts/render_quarterly_report.R` | `Rscript scripts/render_lungs_report.R` |

The Knit button renders **one** report (the first site in `BL_REPORT_SITE_CODES`, or `BL_SITE_CODE` if that list is unset). To generate a separate PDF for each sensor — e.g. `CLDP0299`, `CLDP0470`, and `CLDP0391` — set `BL_REPORT_SITE_CODES` in `.env`, open a terminal in this folder, and run:

```bash
# Bar charts (3 PDFs when BL_REPORT_SITE_CODES lists 3 sites)
Rscript scripts/render_quarterly_report.R

# Lungs plot (3 PDFs)
Rscript scripts/render_lungs_report.R
```

Each site gets its own file, e.g.:

- `output/Test reports/QuarterlyAQtrends_CLDP0470_20260620_161626.pdf`
- `output/Test reports/QuarterlyAQtrends_lungs_CLDP0470_20260620_161626.pdf`

### Option A — CSV (recommended for re-knitting)

```bash
# 1. Fetch data for all report sites (writes data/processed/no2_SITE.csv, pm25_SITE.csv)
Rscript scripts/fetch_readings.R

# 2. Ensure .env has BL_DATA_SOURCE=csv, then render all reports
Rscript scripts/render_quarterly_report.R
Rscript scripts/render_lungs_report.R

# Or render one site only:
Rscript scripts/render_quarterly_report.R CLDP0470
Rscript scripts/render_lungs_report.R CLDP0470
```

### Option B — API direct (no CSV step)

In `.env` set `BL_DATA_SOURCE=api`, then:

```bash
Rscript scripts/render_quarterly_report.R
Rscript scripts/render_lungs_report.R
```

The `.Rmd` files call the API during knit (slower; needs network and key).

### Summary boxes split across pages

The bordered summary boxes are emitted by `bl_emit_summary_box()` into the `blsummarybox` LaTeX environment defined in `R/bl_summary_box.tex`. It wraps the `framed` package's `\MakeFramed`, so a box that does not fit fills the remaining space on the current page and the leftover bullets continue inside a fresh, fully closed box at the top of the next page. This avoids the whole box being pushed onto the next page and leaving a large gap behind it.

Border colour is passed as the environment argument (`\begin{blsummarybox}{blno2quarterborder}`). Rule thickness and padding come from `\blsummaryrule` (3pt) and `\blsummarysep` (10pt).

### Summary-of-data-to-date logic

The **Summary of data to date** boxes only use measurements through the **end of the report quarter** (not the latest fetched row). This keeps the quarterly report internally consistent.

The annual exceedance breakdown in those boxes follows these rules:

| Report quarter | Report year in annual breakdown |
|----------------|----------------------------------|
| **Q1** | Omitted — that quarter already has its own summary box |
| **Q2–Q4** | Included — counts exceedances from 1 Jan through the end of the report quarter |

Prior calendar years always show the full year (within the available measurement period).

Each year line in the annual breakdown is formatted as `2022 → 122 days (44%)`. The day count is the number of exceedance days in that year. The percentage is the **share of all days with data in that calendar year** that exceeded the WHO daily mean guideline (exceedance days ÷ total days × 100, rounded to a whole number). These percentages are independent per year and do not sum to 100% across years.

### Rounding policy

All numeric values shown in the quarterly report PDF use **whole numbers** (no decimal places):

| What | When / where |
|------|----------------|
| **Hourly readings** | On load from CSV, API, or Marylebone RData — rounded to the nearest µg/m³; `0` is treated as missing (`NA`) because a zero concentration is not valid |
| **Summary text** | Average, minimum, and maximum concentrations in the bordered summary boxes |
| **Peak bullets** | Highest single-hour measurements |
| **Marylebone comparison** | Community and reference-site means in the narrative paragraphs |
| **Diurnal bar charts** | Mean concentration at each clock hour (weekday/weekend profiles) |
| **Annual exceedance %** | Percentage of days exceeding the WHO daily mean guideline per calendar year |

Rounding is controlled by `BL_REPORT_ROUND_DIGITS` (default `0`) in `QuarterlyAQtrends_git.Rmd`. Load-time cleaning is in `bl_clean_pollutant_values()` in `R/bl_api.R`.

**Exception — distances.** Concentrations use whole numbers, but the nearest-sensor distance is classified by magnitude:

| Distance | Unit | Rounding | Example |
|----------|------|----------|---------|
| **1 km or more** | kilometres | one decimal place | `1.24 km` → `1.2 km` |
| **Under 1 km** | metres | whole number | `0.8452 km` → `845 m` |

Implemented in `bl_format_distance()` in `QuarterlyAQtrends_lungs.Rmd`.

### Nearest sensor bullet

Each pollutant **Summary of Q1** (etc.) bordered box ends with a bullet naming the closest still-active Breathe London sensor. The “Summary of data to date” boxes do not include this text.

> Your nearest sensor is the Pembury Circus sensor that is 1.2 km away towards the south east. Please note that nearest sensors will have their own pollution sources and weather conditions that will affect their measurements.

| Part | Source |
|------|--------|
| **Sensor name** | `SiteName` of the nearest active site from `bl_nearest_active_site()` |
| **Distance** | Great-circle distance via `bl_earth_dist_km()`, formatted by the rule above |
| **Direction** | Initial bearing via `bl_earth_bearing_deg()`, snapped to **8 compass points** by `bl_compass_direction_8()` |

Direction wording is limited to eight values — `north`, `north east`, `east`, `south east`, `south`, `south west`, `west`, `north west` — so a bearing of 148.7° reads as “south east”. Bearings are measured from the community node to the nearest sensor.

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

**Which narrative is shown?** Evaluated **independently** per pollutant (NO₂ and PM₂.₅ may get different options). Selection logic in `R/bl_marylebone.R`:

1. **A** or **B** — if either passes the ±25% gate, use the one with the **higher cumulative load**
2. **Day-period spikes** — if neither A nor B qualifies, try morning / afternoon / evening / overnight (see below); same ±25% gate; highest cumulative load wins
3. **C** — catch-all when nothing above qualifies (no ±25% gate)

| Option | Period | ±25% gate? |
|--------|--------|------------|
| **A** | Whole-week morning rush (07:00–10:00) | Yes — community mean within 75–125% of MY1 |
| **B** | Whole-week afternoons (12:00–18:00), spike days in top 25% | Yes — same gate on spike-day means |
| **SPIKE** | One of four 6-hour day periods (all days, spike days in top 25%) | Yes — tried only when A and B both fail |
| **C** | Weekday school pick-up (15:00–16:30) | **No** — fallback |

**Day-period spike options (SPIKE)** partition the 24-hour clock (6 hours each, all days of the week):

| Period | Hours | Label in report text |
|--------|-------|----------------------|
| Morning | 06:00–11:59 | *mornings* |
| Afternoon | 12:00–17:59 | *afternoons* |
| Evening | 18:00–23:59 | *evenings* |
| Overnight | 00:00–05:59 | *overnights* |

SPIKE uses the same spike-day method as B (days in the top 25% by community mean during that period). Example bullet text:

> Short-term PM₂.₅ spikes can have important health impacts. On 8 evenings, the community sensor recorded a mean of 18 µg/m³, compared with 16 µg/m³ at Marylebone Road.

Example footnote:

> PM₂.₅ during Q1: mean paired hourly values for evenings (18:00–23:59) on the 8 days in the top 25% by community mean during that period, all days of the week.

Each comparative bullet carries a superscript footnote (numbered after the typical-peak footnote) explaining how that pollutant’s paragraph was calculated for the selected option.

Preview selection for the current site and quarter:

```bash
Rscript scripts/test_marylebone_narrative.R
```

### Report output location

Knitted PDFs are written to `output/Test reports/` with the site code and timestamp in the filename, e.g.:

- `QuarterlyAQtrends_CLDP0470_20260620_161626.pdf` (bar-chart report)
- `QuarterlyAQtrends_lungs_CLDP0470_20260620_161626.pdf` (lungs report)

This is configured in the `knit:` field at the top of each `.Rmd` (via `scripts/knit_quarterly_report.R`). Always knit from the **project root** (the folder containing `R/bl_api.R`).

| How you knit | Output path |
|--------------|-------------|
| **RStudio** — Knit button (Ctrl/Cmd+Shift+K) on `QuarterlyAQtrends_git.Rmd` or `QuarterlyAQtrends_lungs.Rmd` | **One** PDF only — first site in `BL_REPORT_SITE_CODES` |
| **VS Code** — Knit button | Same as RStudio (one PDF), if **smart knitting** is enabled (`r.rmarkdown.knit.useBackgroundProcess: true` in `.vscode/settings.json`) |
| **Terminal** — `Rscript scripts/render_quarterly_report.R` | **One PDF per site** (bar charts) |
| **Terminal** — `Rscript scripts/render_lungs_report.R` | **One PDF per site** (lungs plot) |

**Note:** Running `rmarkdown::render(...)` directly in the R console does **not** use the custom output path and will write a PDF next to the `.Rmd`. Use the Knit button or the `scripts/render_*.R` helpers instead.

## Editor tasks (optional)

Editors that support [VS Code tasks](https://code.visualstudio.com/docs/editor/tasks) (e.g. VS Code) can run the scripts from `.vscode/tasks.json` via **Terminal → Run Task**:

| Task | Command |
|------|---------|
| Fetch sensor list | `Rscript scripts/fetch_sensors.R` |
| Fetch readings | `Rscript scripts/fetch_readings.R` |
| Generate PM2.5 all-sites plot | `Rscript scripts/generate_plots.R` |
| Knit quarterly report — bar charts (PDF) | `Rscript scripts/render_quarterly_report.R` — **all** sites in `BL_REPORT_SITE_CODES` |
| Knit quarterly report — lungs plot (PDF) | `Rscript scripts/render_lungs_report.R` — **all** sites in `BL_REPORT_SITE_CODES` |

These match the terminal commands above; use whichever workflow you prefer.

## Lung plot preview (HTML)

**Quick HTML preview** (`mock_lung_exceedance.Rmd`) — standalone page for tweaking the lung plot before using it in the full PDF. Left = NO₂ exceedance %, right = PM₂.₅, one pair per calendar year (same data as the annual bar charts).

```bash
Rscript -e 'rmarkdown::render("mock_lung_exceedance.Rmd")'
```

Output: `mock_lung_exceedance.html`. For the full quarterly PDF with lungs, use `QuarterlyAQtrends_lungs.Rmd` and `scripts/render_lungs_report.R` (see above).

## Dependencies

```bash
Rscript -e 'install.packages(c("httr2", "jsonlite", "rmarkdown", "knitr", "tidyverse", "cowplot", "lubridate", "openair"), repos="https://cloud.r-project.org")'
brew install pandoc
```

LaTeX (`pdflatex`) required for PDF output.

## API docs

[https://www.breathelondon-communities.org/developers](https://www.breathelondon-communities.org/developers)
