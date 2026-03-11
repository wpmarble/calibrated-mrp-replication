# Replication Package

## Overview

**Paper:** "Improving Small-Area Estimates of Public Opinion by Calibrating to Known Population Quantities"
**Authors:** William Marble and Joshua Clinton
**Journal:** *Political Analysis* 
**Date:** March 11, 2026

This archive contains all code and data needed to reproduce the results in the paper.

## Data Availability

| Data Source | Provided | Notes |
|---|---|---|
| SurveyMonkey 2022  Sample | Yes | `data/survey/CleanedSM_Weighted.rds` |
| County-level election results | Yes | `data/elections/` |
| Michigan 2022 precinct results | Yes | `data/michigan-precincts/michigan22.csv` |
| ACS 5-Year Estimates (poststratification tables) | Yes | `data/poststrat/` (pre-processed from IPUMS USA) |
| County demographic data (NHGIS) | Yes | `data/census/nhgis*.csv` |
| County/state FIPS lookups | Yes | `data/census/*-fips.csv` |
| Cooperative Election Study (CES) | Downloaded on demand | Large files from Harvard Dataverse; see below |
| Frozen model fits | Yes | `data/frozen/` (pre-estimated `brms` model fits, can re-create if desired) |

### CES Data

CES files are too large to bundle. The script `data-raw/download-ces-data.R` downloads them automatically from Harvard Dataverse:

- CES Cumulative File (2006-2024): https://doi.org/10.7910/DVN/II2DB6
- CES Cumulative Policy Preferences: https://doi.org/10.7910/DVN/OSXDQO
- CCES 2022 Common Content: https://doi.org/10.7910/DVN/PR4L8P
- CCES 2023 Common Content: https://doi.org/10.7910/DVN/JQJTCC

### Data Sources Not Included

The following raw data sources were used to construct the processed datasets above. They are not required to run the replication but are documented for transparency. See `data-raw/README.md` for details.

- IPUMS USA (ACS 5-Year microdata)
- MIT Election Data + Science Lab (county presidential returns): https://doi.org/10.7910/DVN/VOQCHQ
- McDonald turnout data: https://www.electproject.org
- NHGIS (county and state demographic tables): https://nhgis.org

Scripts used to process these raw sources are included in `data-raw/` for transparency but are not run by `run.sh`.

## Computational Requirements

- **R version:** 4.3 or later
- **Stan/cmdstan:** Required backend for `brms`. Installed via `cmdstanr::install_cmdstan()`.
- **R packages:** The methods proposed in the paper are implemented in the `calibratedMRP`, available to install from GitHub: `wpmarble/calibratedMRP`. Other key packages: `brms`, `cmdstanr`, `tidyverse`, `kableExtra`, `fixest`, `texreg`. See `install.R` for the complete list. 
- **Memory:** at least 16 GB RAM recommended
- **Cores:** 4+ cores recommended
- **Replication environment:** We last ran this archive on a Mac Studio with Apple Silicon M4 Max process and 64GB memory. Our runtime estimates are based on this environment.
- **Estimated runtime:**
  - Full replication includes `--refit` and `--nsims 25` flags. This re-estimates all models from data and runs CES simulations (Appendix I, 25 reps per configuration). This takes roughly 17-18 hours.
  - With just `--refit` (re-estimate all Bayesian models, not including simulations): 2-3 hours
  - Default (frozen `brms` model fits): ~30 minutes

## Instructions

### 1. Install dependencies

```bash
Rscript install.R
```

### 2. Run replication

```bash
# Default: use frozen model fits, skip CES simulations
./run.sh

# Re-estimate all Bayesian models from scratch, don't conduct simulations
./run.sh --refit

# Full replication (re-estimate everything + simulations)
./run.sh --refit --nsims 25
```

All scripts are run from the `replication-files/` root directory. Output is written to `output/figures/` and `output/tables/`. A log file is saved to `log/replication-log.txt`.

### Frozen Model Fits

By default, pre-estimated model fits in `data/frozen/` are used to avoid long computation times. Pass `--refit` to re-estimate all Bayesian models. Results should be substantively identical.

## Code Description

### Shared Utilities

| File | Description |
|---|---|
| `code/functions.R` | Shared utility functions  |
| `code/prep-survey-data.R` | Prepare SurveyMonkey survey data |
| `code/prep-poststrat-tables.R` | Build poststratification tables from ACS data |

### Michigan Validation (Section 4 + Appendices B, E, F, G, H, J, K)

| File | Description |
|---|---|
| `code/michigan-validation/01-prep-data-michigan.R` | Assemble Michigan data (survey + poststrat + election results) |
| `code/michigan-validation/02-run-michigan.R` | Core Michigan analysis: fit multivariate model, calibrate, generate main text figures and tables |
| `code/michigan-validation/03-michigan-precinct.R` | Precinct-level calibration validation (Appendix H) |
| `code/michigan-validation/04-michigan-diagnostics.R` | Model diagnostics: traceplots and R-hat (Appendix B) |
| `code/michigan-validation/05-prior-sensitivity.R` | Prior sensitivity analysis (Appendix G) |
| `code/michigan-validation/06-plugin-vs-bayes.R` | Plugin vs. full Bayesian calibration comparison (validates footnote in Appendix I) |

### CES Simulations (Appendix I)

| File | Description |
|---|---|
| `code/ces-simulations/00-simulation-functions.R` | Simulation helper functions |
| `code/ces-simulations/01-prep-ces.R` | Prepare CES data for simulation study |
| `code/ces-simulations/02-ces-simulations.R` | Run CES simulation study (configurable N_SIMS) |
| `code/ces-simulations/03-summarize-ces-sims.R` | Summarize and plot simulation results |

### Data Provenance Scripts

| File | Description |
|---|---|
| `data-raw/download-ces-data.R` | Download CES files from Harvard Dataverse (run by `run.sh`) |
| `data-raw/TargetsACS.R` | ACS poststratification table construction (documentation only, not run by `run.sh`) |
| `data-raw/TargetsElections.R` | Election results processing (documentation only, not run by `run.sh`) |
| `data-raw/README.md` | Data source documentation |

## Output Mapping

### Main Text (Section 4)

| Paper Reference | Output File | Generating Script |
|---|---|---|
| Table 1 | `output/tables/michigan-model-correlations.tex` | `02-run-michigan.R` |
| Figure 1 | `output/figures/mi-elections.pdf` | `02-run-michigan.R` |
| Table 2 | `output/tables/michigan-calibration-error-reduction.tex` | `02-run-michigan.R` |
| Figure 2 | `output/figures/mi-calib-adjustment-by-gov-error.pdf` | `02-run-michigan.R` |

### Appendices

| Paper Reference | Output File | Generating Script |
|---|---|---|
| Figure B1 | `output/figures/model-diagnostics/mi-rhat-hist.pdf` | `04-michigan-diagnostics.R` |
| Figure B2 | `output/figures/model-diagnostics/mi-trace-lp.pdf` | `04-michigan-diagnostics.R` |
| Figure B3 | `output/figures/model-diagnostics/mi-trace-cty-intercept.pdf` | `04-michigan-diagnostics.R` |
| Table E1 | `output/tables/mrsp-error-reduction.tex` | `02-run-michigan.R` |
| Figure E4 | `output/figures/mrsp-comparison.pdf` | `02-run-michigan.R` |
| Table F2 (a–d) | `output/tables/michigan-modeled-covariances.tex`, `michigan-modeled-correlation.tex`, `michigan-empirical-covariances.tex`, `michigan-empirical-correlation.tex` | `02-run-michigan.R` |
| Figure G5 | `output/figures/michigan-prior-sensitivity-correlation.pdf` | `05-prior-sensitivity.R` |
| Figure G6 | `output/figures/michigan-prior-sensitivity-rmse.pdf` | `05-prior-sensitivity.R` |
| Figure H7 | `output/figures/mi-precinct-elections.pdf` | `03-michigan-precinct.R` |
| Table H3 | `output/tables/michigan-precinct-calibration-error-reduction.tex` | `03-michigan-precinct.R` |
| Table I4 | `output/tables/ces-sim-full-regression.tex` | `02-ces-simulations.R` |
| Figure I8 | `output/figures/ces-simulation-results.pdf` | `03-summarize-ces-sims.R` |
| Table I5 | `output/tables/ces-simulation-rmse-reduction.tex` | `03-summarize-ces-sims.R` |
| Figure J9 | `output/figures/mi-democratic-pid.pdf` | `02-run-michigan.R` |
| Figure K10 | `output/figures/mi-calib-adjustment-by-gov-results.pdf` | `02-run-michigan.R` |
| Figure K11 | `output/figures/mi-elections-error-reduction.pdf` | `02-run-michigan.R` |
| Figure K12 | `output/figures/mi-election-error-density.pdf` | `02-run-michigan.R` |
| Figure K13 | `output/figures/mi-precinct-election-error-density.pdf` | `03-michigan-precinct.R` |

### Inline Statistics

All files in `output/tables/numbers-in-text/` contain single numbers or short LaTeX fragments used for inline statistics in the paper. These are generated by `02-run-michigan.R`, `03-michigan-precinct.R`, and `02-ces-simulations.R`.
