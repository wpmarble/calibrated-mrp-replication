

# Standardize validation data for the 2000-2020 elections:
#   - NC precinct results 
#   - election results from MIT Election Lab
#   - turnout 
#   - poststratification tables from ACS microdata



library(dplyr)
library(tidyr)
library(tidylog)
select <- dplyr::select



# North Carolina Precinct Results -----------------------------------------


# source("code/cleaning-prep/PrecinctResultsNC.R")



# State- and National-Level Results --------------------------------------------


## State-Level Results -------------------------------------------------------

state.res = read.csv("data/elecresults/state/1976-2020-president.csv")
state.res = state.res %>% 
  filter(year >= 2000, party_simplified %in% c("DEMOCRAT", "REPUBLICAN")) %>% 
  select(year, state = state_po, statefips = state_fips, party = party_simplified, candidatevotes, totalvotes, writein) %>%
  mutate(party = recode(party, DEMOCRAT = "dem", REPUBLICAN = "rep"))

# AZ and MD separate writein votes for major cands in 2016.... 
state.res = state.res %>% 
  group_by(year, state, statefips, party, totalvotes) %>% 
  summarise(candidatevotes = sum(candidatevotes))


# make wide
state.res = pivot_wider(
  state.res,
  id_cols = c("year", "state", "statefips", "totalvotes"),
  values_from = "candidatevotes",
  names_from = "party"
)
state.res = state.res %>% 
  mutate(demvs = dem / totalvotes,
         repvs = rep / totalvotes) %>% 
  mutate(demvs.two.party = demvs / (demvs + repvs))



## National-Level Results -------------------------------------------------------

year.res = state.res %>% 
  group_by(year) %>% 
  summarise(dem = sum(dem), rep = sum(rep), totalvotes = sum(totalvotes)) %>% 
  mutate(demvs = dem / totalvotes,
         repvs = rep / totalvotes) %>% 
  mutate(demvs.two.party = demvs / (demvs + repvs))







## Turnout Rates -------------------------------------------------------

# Get VAP turnout rates from McDonald
# https://election.lab.ufl.edu/dataset/1980-2022-general-election-turnout-rates/
tout <- read.csv("data/elecresults/turnout/Turnout_1980_2022_v1.0.csv")


turnout_state <- tout %>% 
  filter(STATE != "United States") %>% 
  select(state = STATE_ABV,
         year = YEAR,
         pres_votes = VOTE_FOR_HIGHEST_OFFICE,
         tot_votes = TOTAL_BALLOTS_COUNTED,
         vap = VAP,
         TOUT = VAP_TURNOUT_RATE) %>% 
  mutate(across(c(pres_votes, tot_votes, vap, TOUT), ~ as.numeric(gsub(",|\\%", "", .x)))) %>% 
  mutate(turnout.vap = case_when(
    !is.na(pres_votes) ~ pres_votes / vap,
    !is.na(tot_votes) ~ tot_votes / vap,
    TRUE ~ NA_real_
  ))
cor(turnout_state$turnout.vap, turnout_state$TOUT, use = "pa")

turnout_state <- turnout_state %>% 
  select(year, state, turnout.vap)



# National-Level Turnout
turnout_nat <- tout %>% 
  filter(STATE == "United States") %>% 
  select(state = STATE_ABV,
         year = YEAR,
         pres_votes = VOTE_FOR_HIGHEST_OFFICE,
         tot_votes = TOTAL_BALLOTS_COUNTED,
         vap = VAP,
         TOUT = VAP_TURNOUT_RATE) %>% 
  mutate(across(c(pres_votes, tot_votes, vap, TOUT), ~ as.numeric(gsub(",|\\%", "", .x)))) %>% 
  mutate(turnout.vap = case_when(
    !is.na(pres_votes) ~ pres_votes / vap,
    !is.na(tot_votes) ~ tot_votes / vap,
    TRUE ~ NA_real_
  ))
cor(turnout_nat$turnout.vap, turnout_nat$TOUT, use = "pa")

turnout_nat <- turnout_nat %>% 
  select(year, turnout.vap)


## Join with Election Results
state.res <- left_join(
  state.res,
  turnout_state,
  by = c("year", "state")
)

year.res <- left_join(
  year.res,
  turnout_nat,
  by = c("year")
)



saveRDS(year.res, "data/internal/elections/ElectionsPopularVote.rds")
saveRDS(state.res, "data/internal/elections/ElectionsStateVote.rds")





# County-Level Results ----------------------------------------------------




# Election data from MIT elec project
county.res = read.csv("data/elecresults/county/countypres_2000-2020.csv") 
county.res$county_fips[county.res$state_po=="DC"] = 11001
county.res = rename(county.res, countyfips = county_fips)


# Drop third parties
county.res = county.res %>% 
  filter(party %in% c("DEMOCRAT", "REPUBLICAN"))




# get totals and not mode breakouts. only happens in 2020 when there are mode 
# for some states splits. 

# UT has rows for state mode splits but no actual data except for Salt Lake.
# Drop these.
county.res = county.res %>% 
  filter(!(year == 2020 & state == "UTAH" & county_name != "SALT LAKE" & mode != "TOTAL"))

county.res = county.res %>% 
  group_by(countyfips, year) %>%
  mutate(nmode = length(unique(mode))) %>% 
  mutate(tocollapse = nmode > 1 & !any(mode == "TOTAL"))


# counties not to collapse
dontmod = subset(county.res, !tocollapse) 

# counties to collapse
tomod = county.res %>% 
  filter(tocollapse) %>% 
  group_by(year, countyfips, county_name, state, state_po, office, candidate, party, totalvotes) %>% 
  summarise(candidatevotes = sum(candidatevotes)) %>% 
  mutate(tocollapse = TRUE)
county.res = bind_rows(dontmod, tomod) 


county.res = county.res %>% 
  ungroup() %>% 
  mutate(voteshare = candidatevotes / totalvotes) %>% 
  filter(!is.na(countyfips)) 

# Recode county FIPS for Ogala Lakota county, SD
county.res = county.res %>% 
  mutate(countyfips = ifelse(countyfips == 46113, 46102, countyfips))


# Convert to wide format to match state res
county.res.wide = full_join(
  county.res %>% 
    filter(party == "DEMOCRAT") %>% 
    select(year, countyfips, totalvotes, demvs = voteshare)
  ,
  county.res %>% 
    filter(party == "REPUBLICAN") %>% 
    select(year, countyfips, repvs = voteshare),
  by = c("year", "countyfips")
)
county.res.wide = county.res.wide %>% 
  mutate(statefips = as.integer(case_when(
    countyfips < 10000 ~ substr(as.character(countyfips), 1, 1),
    TRUE ~ substr(as.character(countyfips), 1, 2)
  ))) %>% 
  mutate(dem.two.pty = demvs / (demvs + repvs)) %>% 
  relocate(year, statefips, countyfips)




saveRDS(county.res, "data/internal/elections/ElectionsCountyVote_long.rds")
saveRDS(county.res.wide, "data/internal/elections/ElectionsCountyVote.rds")





## Check discrepancies between county.res and state.res 
county.check = county.res.wide %>% 
  group_by(statefips, year) %>% 
  summarise(demvs.check = weighted.mean(demvs, totalvotes),
            totalvotes.check = sum(totalvotes))
  

check = left_join(
  state.res,
  county.check %>% 
    mutate(statefips = as.integer(statefips)),
  by = c("statefips", "year")
)
check = check  %>% 
  mutate(totalvote_diff = totalvotes - totalvotes.check,
         demvs_diff = demvs - demvs.check) %>% 
  mutate(totalvote_diff_pct = 100*totalvote_diff / totalvotes)

quantile(100*check$demvs_diff, seq(0, 1, .1))
quantile(check$totalvote_diff, seq(0, 1, .1))
quantile(check$totalvote_diff_pct, seq(0, 1, .1))

hist(100*(check$totalvotes- check$totalvotes.check) / check$totalvotes,
     main = "Discrepancy between state total votes\nfrom state and aggregated county files",
     xlab = "Percent of state total")
hist(100*(check$demvs- check$demvs.check),
     main = "Discrepancy between Dem vote share\nfrom state and aggregated county files",
     xlab = "Percentage points")




# Voter Turnout -----------------------------------------------------------

#  voter turnout from McDonald 
turnout = read.csv("data/elecresults/turnout/ElectProject_2020.csv")
turnout = turnout %>% 
  mutate(across(c(total_ballots, votes_pres, vep, vap, prison:overseas_eligible), 
                ~ as.numeric(gsub(",", "", .))))

turnout = turnout %>% 
  mutate(turnout.vap_pres = votes_pres / vap,
         turnout_vep_pres = as.numeric(gsub("%", "", turnout_vep_pres, fixed = TRUE)) / 100,
         year = 2020) %>% 
  select(year, state, state_abbr, turnout_vep_pres, turnout.vap_pres)
saveRDS(turnout, "data/internal/elections/Turnout2020.rds")



# 2022 Results (from Neat) ------------------------------------------------

# not sure if we can actually use this Neat data in publications but it's convenient

res22 = readRDS("data/elecresults/Neat-results-2022-11-08.RDS")

# get two-party vote share for each race in 2022
res22_sum = res22$cand %>% 
  filter(major.party %in% c("Dem", "Rep")) %>% 
  group_by(race.id) %>% 
  mutate(n_dems = sum(major.party == "Dem"),
         n_reps = sum(major.party == "Rep")) %>% 
  filter(n_dems == 1, n_reps == 1) %>% 
  ungroup() %>% 
  pivot_wider(id_cols = c("race.id"), 
              values_from = "vote", 
              names_from = "major.party") %>% 
  mutate(race_type = str_split(race.id, "~") %>% map(3) %>% unlist,
         dist_id = str_split(race.id, "~") %>% map(2) %>% unlist) %>% 
  mutate(office = case_when(
    race_type == "H" ~ "house",
    race_type == "S" ~ "senate", 
    race_type == "G" ~ "governor",
    race_type == "A" ~ "attorney general",
    race_type == "SS" ~ "secretary of state",
    race_type == "L" ~ "lt. governor",
    race_type == "S2" ~ "senate 2"
  )) %>% 
  mutate(
    cd = case_when(# wow that's ugly
      office == "house" ~ paste0(substr(dist_id, 1, 2), formatC(
        as.numeric(substr(dist_id, 3, nchar(dist_id))), width = 2, flag = "0"
      )),
      TRUE ~ NA_character_
    ),
    state = substr(dist_id, 1, 2)
  ) %>% 
  mutate(dem_vs_2pty = Dem / (Rep + Dem))


# Get county-level results for each race in 2022
cnty22 <- res22$cnty$cand %>% 
  mutate(county.code = as.integer(county.code))
cnty22 <- left_join(
  cnty22,
  res22$cnty$meta %>%
    select(race.id, county.code, fips.code),
  by = c("race.id", "county.code")
)


# Keep races with a single dem and single rep, plus MI prop 3
cnty22 <- cnty22 %>% 
  filter(party %in% c("Dem", "Rep") | race.id == 	"2022-11-08~MI~I1") %>% 
  group_by(race.id, fips.code) %>% 
  mutate(n_dems = sum(party == "Dem"),
         n_reps = sum(party == "Rep")) %>% 
  filter((n_dems == 1 & n_reps == 1) | race.id == "2022-11-08~MI~I1") %>% 
  ungroup() %>% 
  pivot_wider(id_cols = c("race.id", "fips.code"), 
              values_from = "vote", 
              names_from = "party") %>% 
  mutate(race_type = str_split(race.id, "~") %>% map(3) %>% unlist,
         dist_id = str_split(race.id, "~") %>% map(2) %>% unlist) %>% 
  mutate(office = case_when(
    race_type == "H" ~ "house",
    race_type == "S" ~ "senate", 
    race_type == "G" ~ "governor",
    race_type == "A" ~ "attorney general",
    race_type == "SS" ~ "secretary of state",
    race_type == "L" ~ "lt. governor",
    race_type == "S2" ~ "senate 2",
    race_type == "I1" ~ "michprop3"
  ))

saveRDS(res22_sum, "data/internal/elections/Elections2022.rds")
saveRDS(cnty22, "data/internal/elections/Elections2022-county.rds")
