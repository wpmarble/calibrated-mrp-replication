
## Prep Data for Michigan Validation

# Loads:
# 2022 SurveyMonkey dataset w/ a bunch of binary policy questions labeled _irt
# res22: county-level election results from Neat for 2022
# ps_cty: county-level poststratification table for 2020
# ps: state-level poststratification table for 2020
# state_covs, county_covs: county and state level covariates


library(tidyverse)

# devtools::install_github("wpmarble/calibratedMRP@v0.1.9")
library(calibratedMRP)


source("code/functions.R")
source("code/prep-survey-data.R")
source("code/prep-covariates.R")








# Join survey data with covariates -------------------------------------------


# Join SM data with county and state covariates
sm <- left_join(sm %>%
                  rename(countyfips = county.fips),
                county_covs %>% select(-state.name, -state),
                by = "countyfips")
sm <- left_join(sm, state_covs %>% select(-statefips), by = "state")

sm <- sm %>%
  rename(house = housevote2022_twoparty,
         sen = senvote2022_twoparty,
         gov = govvote2022_twoparty,
         sos = sosvote2022_twoparty,
         michprop3 = miprop3vote2022,
         pres2020 = pres2020_irt)



# Load and format election results ----------------------------------------

## load county-level 2022 elections results
res22 <- readRDS("data/elections/Elections2022-county.rds")
res22 <- res22 %>%
  rename(countyfips = fips.code)

# get rid of CA and OK senate bc there were two elections
res22 <- res22 %>%
  filter(!race.id %in% c("2022-11-08P~CA~S", "2022-11-08~CA~S",
                         "2022-11-08~OK~S2", "2022-11-08~OK~S"))

# collapse house votes by county
res22 <- res22 %>%
  group_by(countyfips, race_type, office) %>%
  summarise(dem = sum(Dem), rep = sum(Rep),
            yes = sum(Yes), no = sum(No)) %>%
  mutate(office = case_when(
    office == "house" ~ "house",
    office == "attorney general" ~ "ag",
    office == "governor" ~ "gov",
    office == "senate" ~ "sen",
    office == "secretary of state" ~ "sos",
    office == "lt. governor" ~ "ltgov",
    TRUE ~ office
  )) %>%
  mutate(dem_twoparty = dem / (dem + rep),
         yes_twoparty = yes / (yes + no)) %>%
  ungroup()

res22 <- res22 %>%
  select(-c(dem, rep, race_type, yes, no)) %>%
  pivot_wider(values_from = c(dem_twoparty, yes_twoparty),
              names_from = office)

res22 <- res22 %>%
  select(where(~ !all(is.na(.x)))) %>%
  rename_with(~ gsub("dem_twoparty_|yes_twoparty_", "", .x),
              c(starts_with("dem_twoparty"), starts_with("yes_twoparty")))




## Combine with 2020 county results --------------------------------------

res22 <- left_join(vote.county %>%
                     select(countyfips, pres2020 = dem.two.pty),
                   res22,
                   by = "countyfips")



