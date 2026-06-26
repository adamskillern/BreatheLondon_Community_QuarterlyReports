# Data quality checks — Breathe London community sensors

Ideas for automated QA on hourly NO₂ and PM₂.₅ data. Use alongside `scripts/analysis_BL.R` for interactive exploration and flagging.

---

## Already implemented (CLDP0391 example)


| Check                       | What it catches                                         | Where                                                                                                                                   |
| --------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Non-positive values**     | Concentrations ≤ 0 (invalid for air quality)            | `plot_daily_non_positive_conc()`                                                                                                        |
| **Consecutive flatline**    | Same value for 3+ consecutive hours                     | `plot_daily_repeated_conc()`                                                                                                            |
| **API vs website coverage** | API drops timestamps; website keeps hour with `NA`      | Coverage summary in `analysis_BL.R`                                                                                                     |
| **API vs website values**   | Mismatched concentrations on matched hours              | `cmp_no2`, `cmp_pm25`, `cmp_all`. All pollutants from CLDP0391 API and website CSV are inline. Only one value is -0.01 µg/m³ different. |
| **Timestamp integrity**     | Duplicate hours, backwards time, irregular spacing      | Only duplicates found with different concentration values. `timestamp_integrity_flags`, `timestamp_integrity_issues` in `analysis_BL.R` |
| **Duplicate timestamps**    | Duplicate timestamps with diffrent concentration values | Examples from website CSV export (CLDP0391): `2025-10-26 00:00:00`, `2024-10-27 00:00:00`, `2023-10-29 00:00:00`                        |
| **Out-of-order**            | Website NO₂ / PM₂.₅ datetime order                      | None found                                                                                                                              |
| **Irregular spacing**       | Website NO₂ / PM₂.₅ datetime order                      | None found                                                                                                                              |


---



## Suggested automated checks



### 1. Sensor limits and physical plausibility


| Check                     | Description                         | Example threshold                            |
| ------------------------- | ----------------------------------- | -------------------------------------------- |
| **Upper detection limit** | Outside of sensor confidence limits | NO₂ > 500–1000 µg/m³; PM₂.₅ > 500–1000 µg/m³ |


---



### 2. Temporal patterns


| Check                | Description                      | Example threshold           |
| -------------------- | -------------------------------- | --------------------------- |
| **Near-flatline**    | Values change by < ε for N hours | ε = 0.01 µg/m³, N = 3       |
| **Spike / jump**     | Large hour-to-hour change        |                             |
| **Low variance day** | Daily SD near zero               | SD < 0.5 µg/m³ for full day |


---



### 3. Completeness and coverage


| Check                                | Description                       | Example threshold                     |
| ------------------------------------ | --------------------------------- | ------------------------------------- |
| **Long period of missing data**      | Continuous missing run            | ≥ 12, or 24 consecutive missing hours |
| **Monthly / quarterly capture rate** | % of days meeting daily threshold | < 75% of days in month and quarter    |


---



## Related files

- `scripts/analysis_BL.R` — QA workspace, plots, API vs website comparison
- `R/bl_api.R` — `bl_clean_pollutant_values()` (round + 0 → `NA` for reports)
- `data/raw/listSensors.json` — per-site `StartDate`, `EndDate`
- `README.md` — rounding policy and report data rules

