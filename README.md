# Breathe London Community Quarterly Reports

R Markdown quarterly air quality reports for Breathe London Community Programme nodes.

## Configure `.env`

Copy [`.env.example`](.env.example) to `.env` and set:

| Variable | Purpose |
|----------|---------|
| `year_of_report` | e.g. `2025` — used in `${year_of_report}` |
| `BL_START_DATE` / `BL_END_DATE` | Date/time **without weekday** (e.g. `01 Jan ${year_of_report} 00:00:00 GMT`) |
| `BL_SITE_CODE` | Sensor code |
| `BL_DATA_SOURCE` | `csv` or `api` |
| `BL_Q4_START` / `BL_Q4_END` | Quarter plot windows (`${year_of_report}-10-01`, etc.) |

Weekday (`Wed`, `Fri`, …) is added in R when calling the API. Preview: `Rscript scripts/show_api_times.R`

## Run a report

From the project root in Cursor terminal:

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

## Cursor tasks

**Tasks: Run Task** → `Breathe: Fetch readings` or add a render task.

## Dependencies

```bash
Rscript -e 'install.packages(c("httr2", "jsonlite", "rmarkdown", "knitr", "tidyverse", "cowplot", "lubridate"), repos="https://cloud.r-project.org")'
brew install pandoc
```

LaTeX (`pdflatex`) required for PDF output.

## API docs

[https://www.breathelondon-communities.org/developers](https://www.breathelondon-communities.org/developers)
