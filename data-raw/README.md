# Data Sources and Preparation

This directory contains scripts that document how the raw data were processed
into the analysis-ready files in `data/`. These scripts are provided for
transparency and are **not** run by `run.sh`.

## Raw Data Sources

### SurveyMonkey 2022 Survey Data
- **File**: `data/survey/CleanedSM_Weighted.rds`
- **Source**: SurveyMonkey river sample, Fall 2022
- **Cleaning script**: `code/prep-survey-data.R`

### ACS Poststratification Tables
- **Files**: `data/poststrat/ACS_poststrat_2020_hispanic.rds` (state-level),
  `data/poststrat/ACS_poststrat_county_2020.rds` (county-level)
- **Source**: American Community Survey 5-year estimates (2016-2020) via IPUMS USA
- **State-level creation**: `TargetsACS.R` creates state-level tables from ACS
  microdata, cross-tabulating age × race × gender × education × state.
- **County-level creation**: County-level poststratification tables were
  constructed from ACS microdata using PUMA-to-county crosswalks. PUMAs that
  span multiple counties were allocated proportionally by population. The
  resulting table cross-tabulates age × race × gender × education × county
  (240 cells per county for Michigan).
- **Note**: The county-level creation script requires IPUMS microdata extracts
  that are too large to redistribute. The processed `.rds` files are included
  directly.

### Election Results
- **Files**: `data/elections/ElectionsCountyVote.rds`,
  `data/elections/ElectionsStateVote.rds`, `data/elections/Elections2022-county.rds`
- **Sources**:
  - County-level presidential results (2000-2020): [MIT Election Data + Science
    Lab](https://doi.org/10.7910/DVN/VOQCHQ)
  - State-level turnout: [Michael McDonald's United States Elections
    Project](https://www.electproject.org/)
  - Michigan 2022 results: [Michigan Secretary of State](https://mielections.us/)
- **Processing script**: `TargetsElections.R`

### Census Demographics (NHGIS)
- **Files**: `data/census/nhgis0106_ds249_20205_county.csv`,
  `data/census/nhgis0101_ds249_20205_state.csv`
- **Source**: [NHGIS](https://www.nhgis.org/) — ACS 2016-2020 5-year estimates,
  Table B03002 (Hispanic/Latino origin by race)
- **Variables used**: Total population, voting-age population by race/ethnicity
  at county and state levels

### FIPS Code Lookups
- **Files**: `data/census/state-fips.csv`, `data/census/county-fips.csv`

### Michigan Precinct Results
- **File**: `data/michigan-precincts/michigan22.csv`
- **Source**: [Michigan Secretary of State](https://mvic.sos.state.mi.us/votehistory/) — 2022 general election precinct-level results

### Cooperative Election Study (CES)
- **Files**: Downloaded to `data/ces/` by `download-ces-data.R`
- **Not included** in the replication package due to size; downloaded on demand
  from Harvard Dataverse
- **Datasets**:
  - CES Cumulative File (2006-2024): <https://doi.org/10.7910/DVN/II2DB6>
  - CES Cumulative Policy Preferences: <https://doi.org/10.7910/DVN/OSXDQO>
  - CES 2022 Common Content: <https://doi.org/10.7910/DVN/PR4L8P>
  - CES 2023 Common Content: <https://doi.org/10.7910/DVN/JQJTCC>

## Scripts in This Directory

| Script | Purpose |
|--------|---------|
| `download-ces-data.R` | Downloads CES files from Harvard Dataverse |
| `TargetsACS.R` | Creates state-level poststratification tables from ACS microdata |
| `TargetsElections.R` | Processes election results into analysis-ready format |
