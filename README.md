# Replication Package

## Overview

**Paper:** "Improving Small-Area Estimates of Public Opinion by Calibrating to Known Population Quantities"
**Authors:** William Marble and Joshua Clinton
**Journal:** *Political Analysis* (forthcoming)

This archive contains all code and data needed to reproduce the results in the paper.

## Data Availability

| Data Source | Provided | Notes |
|---|---|---|
| SurveyMonkey 2022 River Sample | Yes | `data/survey/CleanedSM_Weighted.rds` |
| ACS 5-Year Estimates (poststratification tables) | Yes | `data/poststrat/` (pre-processed from IPUMS USA) |
| County demographic data (NHGIS) | Yes | `data/census/nhgis*.csv` |
| County/state FIPS lookups | Yes | `data/census/*-fips.csv` |
| County-level election results | Yes | `data/elections/` |
| Michigan 2022 precinct results | Yes | `data/michigan-precincts/michigan22.csv` |
| Cooperative Election Study (CES) | Downloaded on demand | Large files from Harvard Dataverse; see below |
| Frozen model fits | Yes | `data/frozen/` (pre-estimated Bayesian models) |

### CES Data

CES files are too large to bundle. The script `data-raw/download-ces-data.R` downloads them automatically from Harvard Dataverse:

- CES Cumulative File (2006-2024): https://doi.org/10.7910/DVN/II2DB6
- CES Cumulative Policy Preferences: https://doi.org/10.7910/DVN/OSXDQO
- CCES 2022 Common Content: https://doi.org/10.7910/DVN/PR4L8P
- CCES 2023 Common Content: https://doi.org/10.7910/DVN/JQJTCC

### Data Sources Not Included

The following raw data sources were used to construct the processed datasets above. They are not required to run the replication but are documented for transparency. See `data-raw/README.md` for details.

- IPUMS USA (ACS 5-Year microdata): https://usa.ipums.org
- MIT Election Data + Science Lab (county presidential returns): https://doi.org/10.7910/DVN/VOQCHQ
- McDonald turnout data: https://www.electproject.org
- NHGIS (county and state demographic tables): https://nhgis.org

Scripts used to process these raw sources are included in `data-raw/` for transparency but are not run by `run.sh`.

## Computational Requirements

- **R version:** 4.3 or later
- **Stan/cmdstan:** Required backend for `brms`. Installed via `cmdstanr::install_cmdstan()`.
- **R packages:** See `install.R` for the complete list. Key packages: `brms`, `cmdstanr`, `calibratedMRP` (installed from GitHub: `wpmarble/calibratedMRP`), `tidyverse`, `kableExtra`, `fixest`, `texreg`.
- **Memory:** ~16 GB RAM recommended
- **Cores:** 4+ cores recommended (models use 4 parallel chains)
- **Estimated runtime:**
  - Default (frozen model fits): ~30 minutes
  - With `--refit` (re-estimate all Bayesian models): ~4-8 hours
  - With `--nsims 25` (run CES simulations, 25 reps per configuration): several days

## Instructions

### 1. Install dependencies

```bash
Rscript install.R
```

### 2. Run replication

```bash
# Default: use frozen model fits, skip CES simulations
./run.sh

# Re-estimate all Bayesian models from scratch
./run.sh --refit

# Run CES simulations with 25 replications per configuration
./run.sh --nsims 25

# Full replication (re-estimate everything + simulations)
./run.sh --refit --nsims 25
```

All scripts are run from the `replication-files/` root directory. Output is written to `output/figures/` and `output/tables/`. A log file is saved to `log/replication-log.txt`.

### Frozen Model Fits

By default, pre-estimated model fits in `data/frozen/` are used to avoid long computation times. Pass `--refit` to re-estimate all Bayesian models. Results should be substantively identical (minor MCMC variation expected).

## Code Description

### Shared Utilities

| File | Description |
|---|---|
| `code/functions.R` | Shared utility functions (z-scoring, raking weights) |
| `code/prep-survey-data.R` | Prepare SurveyMonkey survey data |
| `code/prep-poststrat-tables.R` | Build poststratification tables from ACS data |

### Michigan Validation (Section 4 + Appendices C, D, E, G, H, J)

| File | Description |
|---|---|
| `code/michigan-validation/01-prep-data-michigan.R` | Assemble Michigan data (survey + poststrat + election results) |
| `code/michigan-validation/02-run-michigan.R` | Core Michigan analysis: fit multivariate model, calibrate, generate main text figures and tables |
| `code/michigan-validation/03-michigan-precinct.R` | Precinct-level calibration validation (Appendix H) |
| `code/michigan-validation/04-michigan-diagnostics.R` | Model diagnostics: traceplots and R-hat (Appendix C) |
| `code/michigan-validation/05-prior-sensitivity.R` | Prior sensitivity analysis (Appendix G) |
| `code/michigan-validation/06-plugin-vs-bayes.R` | Plugin vs. full Bayesian calibration comparison (Appendix J) |

### CES Simulations (Appendix I)

| File | Description |
|---|---|
| `code/ces-simulations/00-simulation-functions.R` | Simulation helper functions |
| `code/ces-simulations/01-prep-ces.R` | Prepare CES data for simulation study |
| `code/ces-simulations/02-ces-simulations.R` | Run CES simulation study (configurable N_SIMS) |
| `code/ces-simulations/03-summarize-ces-sims.R` | Summarize and plot simulation results |

### Data Provenance Scripts (not run by `run.sh`)

| File | Description |
|---|---|
| `data-raw/download-ces-data.R` | Download CES files from Harvard Dataverse |
| `data-raw/TargetsACS.R` | ACS poststratification table construction (documentation) |
| `data-raw/TargetsElections.R` | Election results processing (documentation) |
| `data-raw/README.md` | Data source documentation |

## Output Mapping

### Main Text

| Paper Reference | Output File | Generating Script |
|---|---|---|
| Figure 1 | `output/figures/mi-elections.pdf` | `02-run-michigan.R` |
| Figure 2 | `output/figures/mi-elections-error-reduction.pdf` | `02-run-michigan.R` |
| Figure 3 | `output/figures/mi-election-error-density.pdf` | `02-run-michigan.R` |
| Figure 4 | `output/figures/mi-calib-adjustment-by-gov-results.pdf` | `02-run-michigan.R` |
| Figure 5 | `output/figures/mi-calib-adjustment-by-gov-error.pdf` | `02-run-michigan.R` |
| Figure 6 | `output/figures/mi-democratic-pid.pdf` | `02-run-michigan.R` |
| Table 1 | `output/tables/michigan-calibration-error-reduction.tex` | `02-run-michigan.R` |
| Table 2 | `output/tables/michigan-model-correlations.tex` | `02-run-michigan.R` |

### Appendices

| Paper Reference | Output File | Generating Script |
|---|---|---|
| Figure C.1 | `output/figures/model-diagnostics/mi-rhat-hist.pdf` | `04-michigan-diagnostics.R` |
| Figure C.2 | `output/figures/model-diagnostics/mi-trace-lp.pdf` | `04-michigan-diagnostics.R` |
| Figure C.3 | `output/figures/model-diagnostics/mi-trace-cty-intercept.pdf` | `04-michigan-diagnostics.R` |
| Tables D.1-D.4 | `output/tables/michigan-empirical-*.tex`, `michigan-modeled-*.tex` | `02-run-michigan.R` |
| Figures E.1-E.2 | `output/figures/mrsp-*.pdf` | `02-run-michigan.R` |
| Table E.1 | `output/tables/mrsp-error-reduction.tex` | `02-run-michigan.R` |
| Figures G.1-G.2 | `output/figures/michigan-prior-sensitivity-*.pdf` | `05-prior-sensitivity.R` |
| Figure H.1 | `output/figures/mi-precinct-elections.pdf` | `03-michigan-precinct.R` |
| Figure H.2 | `output/figures/mi-precinct-election-error-density.pdf` | `03-michigan-precinct.R` |
| Table H.1 | `output/tables/michigan-precinct-calibration-error-reduction.tex` | `03-michigan-precinct.R` |
| Figure I.1 | `output/figures/ces-simulation-results.pdf` | `03-summarize-ces-sims.R` |
| Table I.1 | `output/tables/ces-simulation-rmse-reduction.tex` | `03-summarize-ces-sims.R` |
| Table I.2 | `output/tables/ces-population-correlations.tex` | `02-ces-simulations.R` |

### Inline Statistics

All files in `output/tables/numbers-in-text/` contain single numbers or short LaTeX fragments used for inline statistics in the paper. These are generated by `02-run-michigan.R`, `03-michigan-precinct.R`, and `02-ces-simulations.R`.
