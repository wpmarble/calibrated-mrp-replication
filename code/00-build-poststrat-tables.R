## Build ACS poststratification tables from IPUMS microdata
##
## This script is NOT run by run.sh. It documents how the poststratification
## tables in data/poststrat/ were created from ACS microdata. To re-run it,
## you need an IPUMS USA extract saved at ../data/census/microdata/acs_micro_2020.dta
## (i.e., one level up from the replication-files/ directory).
##
## Required IPUMS variables: age, sex, race, hispan, educd, perwt, statefip,
##                           countyfip, puma
##
## Outputs:
##   data/poststrat/ACS_poststrat_2020_hispanic.rds  (state-level, detailed Hispanic)
##   data/poststrat/ACS_poststrat_county_2020.rds    (county-level)

library(tidyverse)
library(tidylog)


# Load lookup tables --------------------------------------------------------

stfips <- read.csv("data/census/state-fips.csv")

## PUMA to county crosswalk (2010 Census PUMAs, population-based allocation factors)
pumacty <- read_csv("data/census/puma2010-to-county.csv",
                    skip = 2,
                    col_names = names(read_csv("data/census/puma2010-to-county.csv", n_max = 0)))
pumacty <- pumacty %>%
  mutate(puma = paste0(state, puma12))


# Read ACS microdata -------------------------------------------------------

# Path is relative to replication-files/ root. The microdata live one level
# up, in the main project's data directory.
acs_init <- haven::read_dta("../data/census/microdata/acs_micro_2020.dta")


# Recode variables ----------------------------------------------------------

acs <- acs_init %>%
  mutate(

    # Education
    educ = case_when(
      educd %in% c(000, 001, 002, 010, 011, 012, 013,
                   014, 015, 016, 017, 020, 021, 022,
                   023, 024, 025, 026, 030, 040, 050, 060, 061) ~ "HS or less",
      educd %in% c(062, 063, 064) ~ "HS or less",
      educd %in% c(065, 070, 071, 080, 081, 082, 083, 090, 100) ~ "some college",
      educd %in% c(101, 110, 111, 112, 113) ~ "college",
      educd %in% c(114, 115, 116) ~ "postgrad",
      educd == 999 ~ NA_character_
    ),
    educ_degree = ifelse(educ %in% c("college", "post-grad"), 1, 0),

    # Gender
    gender = case_when(sex == 1 ~ "male", sex == 2 ~ "female"),

    # Age
    age = as_factor(age),
    age = case_when(
      age == "less than 1 year old" ~ 1,
      age == "90 (90+ in 1980 and 1990)" ~ 90,
      age == "100 (100+ in 1960-1970)" ~ 100,
      age == "112 (112+ in the 1980 internal data)" ~ 112,
      age == "115 (115+ in the 1990 internal data)" ~ 115,
      is.na(age) ~ NA_real_,
      TRUE ~ as.numeric(age)
    ),
    agegrp = factor(case_when(
      age >= 0 & age <= 29  ~ "18-29",
      age >= 30 & age <= 39 ~ "30-39",
      age >= 40 & age <= 49 ~ "40-49",
      age >= 50 & age <= 64 ~ "50-64",
      age >= 65 & age <= 74 ~ "65-74",
      age >= 74 & age <= Inf ~ "75+",
      TRUE ~ NA_character_
    ), c("18-29", "30-39", "40-49",
         "50-64", "65-74", "75+")),

    # Race/Ethnicity
    hispanic = as_factor(hispan),
    race_detail = as_factor(race),
    race = case_when(
      hispanic != "not hispanic" ~ "hispanic",
      race_detail == "black/african american" ~ "black",
      race_detail %in% c("chinese", "japanese", "other asian or pacific islander") ~ "asian",
      race_detail == "white" ~ "white",
      is.na(race_detail) ~ NA_character_,
      TRUE ~ "other"
    ),

  ) %>%

  # Geographic identifiers
  mutate(county_fips = paste0(formatC(statefip, width=2, flag = "0"),
                              formatC(countyfip, width = 3, flag = "0")))


# Filter to voting-age population
acs <- acs %>%
  filter(age >= 18)


# Add state abbreviations
acs <- left_join(acs %>%
                   mutate(state = as_factor(statefip)),
                 stfips %>%
                   select(state = state.full, state.fips, state.abbr) %>%
                   mutate(state = tolower(state)),
                 by = "state")
acs <- acs %>%
  mutate(state = state.abbr)



# State-level PS table (detailed Hispanic) ----------------------------------

ps_detail <- acs %>%
  mutate(race_detail = case_when(
    hispanic == "not hispanic" ~ race,
    hispanic == "other" ~ "other hispanic",
    TRUE ~ as.character(hispanic)
  )) %>%
  group_by(state, agegrp, gender, educ, race_detail) %>%
  summarise(est_n = sum(perwt)) %>%
  ungroup() %>%
  mutate(est_totn = sum(est_n),
         est_prop = est_n / est_totn)

ps_detail <- ps_detail %>%
  mutate(year = 2020) %>%
  relocate(year)

saveRDS(ps_detail, file = "data/poststrat/ACS_poststrat_2020_hispanic.rds")
cat("Saved: data/poststrat/ACS_poststrat_2020_hispanic.rds\n")



# County-level PS table -----------------------------------------------------

acs_puma <- acs %>%
  mutate(id = row_number()) %>%
  select(id, state.fips, puma,
         agegrp, gender, educ, race,
         contains("wt")) %>%
  mutate(state.fips = formatC(state.fips, width = 2, format = "fg", flag = "0"),
         puma = formatC(puma, width = 5, format = "fg", flag = "0")) %>%
  mutate(puma2 = paste0(state.fips, puma))

acs_puma <- left_join(acs_puma,
                      pumacty,
                      by = c("puma2" = "puma"))

# Poststrat weights by county
ps_cty <- acs_puma %>%
  group_by(stab, state.fips, county, agegrp, gender, educ, race) %>%
  summarise(est_n = sum(perwt * afact)) %>%
  ungroup() %>%
  mutate(est_totn = sum(est_n),
         est_prop = est_n / est_totn) %>%
  rename(state = stab)
ps_cty <- ps_cty %>%
  mutate(year = 2020) %>%
  relocate(year)

saveRDS(ps_cty, file = "data/poststrat/ACS_poststrat_county_2020.rds")
cat("Saved: data/poststrat/ACS_poststrat_county_2020.rds\n")

cat("Done.\n")
