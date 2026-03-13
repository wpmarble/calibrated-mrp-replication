




# Prepare Poststratification Table ----------------------------------------


# cesnsus region variables
cens.region <- read.csv("data/census/state-fips.csv")
cens.region <- cens.region %>% 
  select(state = state.abbr, census.region)


ps = readRDS("data/poststrat/ACS_poststrat_2020_hispanic.rds")
ps = left_join(ps, cens.region, "state")

## Add interaction variables to poststrat table
ps = ps %>% 
  mutate(race = case_when(
    race_detail %in% c("other hispanic", "cuban", "mexican", "puerto rican") ~ "hispanic",
    TRUE ~ race_detail
  )) %>% 
  mutate(hispanic_detail = case_when(
    race != "hispanic" ~ "not hispanic",
    TRUE ~ race_detail
  )) %>% 
  mutate(white = ifelse(race == "white", "white", "nonwhite")) %>% 
  mutate(race_educ = paste0(educ, " - ", race),
         nonwhite_educ_agegrp = paste0(white, " - ", educ, " - ", agegrp))


# county poststratification
ps_cty = readRDS("data/poststrat/ACS_poststrat_county_2020.rds")
ps_cty = ps_cty %>% 
  rename(countyfips = county) %>% 
  mutate(white = ifelse(race == "white", "white", "nonwhite")) %>% 
  mutate(race_educ = paste0(educ, " - ", race),
         nonwhite_educ_agegrp = paste0(white, " - ", educ, " - ", agegrp)) %>% 
  relocate(est_n, est_totn, est_prop, .after = everything())

ps_cty <- left_join(ps_cty, cens.region, by = "state")

# Prepare Geographic Predictors -------------------------------------------


###  County-Level Covariates ### 
# 2020 presidential vote
vote.county = readRDS("data/elections/ElectionsCountyVote.rds") %>%
  filter(year == 2020) %>% 
  mutate(countyfips = case_when(
    countyfips < 1e4 ~ paste0("0", countyfips), 
    TRUE ~ as.character(countyfips)
  ))

# Sociodemographic covariates
county_covs = read.csv("data/census/nhgis0106_ds249_20205_county.csv")
county_covs = county_covs %>% 
  filter(STATE != "Puerto Rico")
county_covs = county_covs %>% 
  mutate(countyfips = paste0(formatC(STATEA, width = 2, flag = "0"),
                             formatC(COUNTYA, width = 3, flag = "0"))) %>% 
  mutate(cty_pct_nonwhite_z = 1 - (AMPWE002 / AMPWE001),
         cty_pct_hispanic_z = AMP4E003 / AMP4E001,
         cty_pct_college_z = (AMRZE022 + AMRZE023 + AMRZE024 + AMRZE025) / AMRZE001,
         cty_med_inc_z = z_score2(AMR8E001)) %>% 
  mutate(across(cty_pct_nonwhite_z:cty_pct_college_z, ~ z_score2(.x))) %>% 
  select(state.name = STATE, state = STATEA, countyfips:cty_med_inc_z)

county_covs = left_join(
  county_covs, 
  vote.county %>% 
    mutate(cty_dem2020_z = z_score2(dem.two.pty)) %>% 
    select(countyfips, cty_dem2020_z, cty_dem2020 = dem.two.pty) %>% 
    mutate(countyfips = formatC(countyfips, width = 5, flag = "0")),
  by = c("countyfips")
)

# only non-matches are a bunch of Alaska "counties" and one county in hawaii that has 72 people in it





###  State-Level Covariates ### 
#  2020 presidential vote
vote.state  = readRDS("data/elections/ElectionsStateVote.rds")
vote.state = vote.state %>% 
  ungroup() %>% 
  filter(year %in% c(2020, 2016)) %>% 
  select(state, statefips, year, st_demvs = demvs.two.party, st_turnout = turnout.vap) 
vote.state = vote.state %>% 
  pivot_wider(id_cols = c("state", "statefips"),
              values_from = c("st_demvs", "st_turnout"),
              names_from = "year") %>% 
  mutate(across(c(st_demvs_2020, st_demvs_2016, st_turnout_2020, st_turnout_2016),
                .f = z_score2, 
                .names = "{.col}_z"))

## Generate state-level covariates: 
#  - presidential election vote share in 2020
#  - median household income in 2020
#  - state-level demographics:
#    - pct hispanic, pct nonwhite, pct with college degree, derived from PS table
inc = read.csv("data/census/nhgis0101_ds249_20205_state.csv")
inc = inc %>% 
  select(state = STUSAB, med_inc = AMR8E001) %>% 
  filter(state != "PR") %>% 
  mutate(st_med_inc_z = z_score2(med_inc)) %>% 
  rename(st_med_inc = med_inc)

state_covs = left_join(
  vote.state,
  ps %>% 
    group_by(state) %>% 
    summarise(st_pct_college_z = sum(as.numeric(educ %in% c("college", "postgrad")) * est_n),
              st_pct_hispanic_z = sum(as.numeric(race == "hispanic") * est_n),
              st_pct_nonwhite_z = sum(as.numeric(race != "white") * est_n),
              n = sum(est_n)) %>% 
    mutate(across(st_pct_college_z:st_pct_nonwhite_z, ~ .x / n)) %>% 
    select(-n) %>% 
    mutate(across(st_pct_college_z:st_pct_nonwhite_z, ~ z_score2(.x))),
  by = "state"
)
state_covs = left_join(
  state_covs, 
  inc, 
  by = "state"
)


# join with poststrat data
# Note: if cross-validate based on individual respondents, sample ps
ps = left_join(ps, state_covs, by = "state")




# county
ps_cty = left_join(ps_cty, 
                   county_covs %>% 
                     select(-state.name, -state), 
                   by = "countyfips")
ps_cty = left_join(ps_cty,
                   state_covs, 
                   by = "state")

