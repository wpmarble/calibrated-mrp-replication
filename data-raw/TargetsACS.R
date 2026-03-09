
# Use ACS microdata to generate poststratification tables.

# Current poststratification cells:
#  - age group
#  - race/ethnicity
#  - state
#  - education
#  - gender
#  TODO: add ancestry for 2016. currently only includes ancestry for 2020.
#  TODO: add family income
#  TODO: county level -- requires mapping between PUMAs and counties

# Current years covered:
#   - 2020
#   - 2016
#   TODO: 2008, 2012


library(tidyverse)
library(tidylog)
library(questionr)


stfips = read.csv("data/state-fips.csv")


if (!dir.exists("data/census/microdata/")){
  stop(paste("to run this script you must have census microdata saved in the",
             "directory data/census/microdata. can't put this data on github",
             "b/c it's too large. copy folder from weighting/data/census/microdata."))
}






# Get Poststratification Weight from ACS Microdata ------------------------

for (y in c(2016, 2020)){
  
  
  
  
  
  
  # Read ACS microdata generated from IPUMS
  acs_init = haven::read_dta(paste0("data/census/microdata/acs_micro_", y, ".dta"))
  
  
  # Harmonize CCES and ACS variables/variable names.
  acs = acs_init %>%
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
      # race_simple = case_when(
      #   race_detail == "white" ~ "white",
      #   race_detail == "black/african american" ~ "black",
      #   race_detail %in% c("chinese", "japanese", "other asian or pacific islander") ~ "asian",
      #   is.na(race_detail) ~ NA_character_,
      #   
      # ),
      race = case_when(
        hispanic != "not hispanic" ~ "hispanic",
        race_detail == "black/african american" ~ "black",
        race_detail %in% c("chinese", "japanese", "other asian or pacific islander") ~ "asian",
        race_detail == "white" ~ "white",
        is.na(race_detail) ~ NA_character_,
        TRUE ~ "other"
      ),
      
      # Ancestry
      
    ) %>%
    
    # Geographic identifiers
    mutate(county_fips = paste0(formatC(statefip, width=2, flag = "0"), 
                                formatC(countyfip, width = 3, flag = "0")),
           puma = paste0(formatC(statefip, width = 2, flag = "0"), 
                         formatC(puma, width=5, flag = "0"))) 
  
  
  # Drop under-18
  acs = acs %>% 
    filter(age >= 18)
  
  
  # Add state abbreviations for consistency w CCES
  acs = left_join(acs %>% 
                    mutate(state = as_factor(statefip)), 
                 stfips %>% 
                    select(state = state.full, state.fips, state.abbr) %>% 
                    mutate(state = tolower(state)),
                  by = "state")
  acs = acs %>% 
    mutate(state= state.abbr)
  
  
  
  
  
  # Generate poststratification table ---------------------------------------
  
  
  # poststrat wts
  ps = acs %>%
    group_by(state, agegrp, gender, educ, race) %>%
    summarise(est_n = sum(perwt)) %>% 
    ungroup() %>%
    mutate(est_totn = sum(est_n),
           est_prop = est_n / est_totn)
  ps = ps %>% 
    mutate(year = y) %>% 
    relocate(year)
  
  saveRDS(ps,file= paste0("data/internal/ACS_poststrat_", y, ".rds"))
  
  
  ## Generate poststratification table with detailed Hispanic/Latino coding
  if (y == 2020){
    ps_detail = acs %>% 
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
    
    ps_detail = ps_detail %>% 
      mutate(year = y) %>% 
      relocate(year)
    
    saveRDS(ps_detail,file= paste0("data/internal/ACS_poststrat_", y, "_hispanic.rds"))
    
  }
  
  
  
  
  # Generate Marginals ------------------------------------------------------
  
  ## From Josh:
  
  # 1) ACS of over 18 using:Age, Race, Education, College, Race by Education (or, 
  # at least White by Education).  Maybe also Race by Education by age ? [WEIGHT 1]
  # - This will get us the VAP demographics (
  #   which is what CCES weights on — FYI Doug Rivers has some interesting recent 
  # tweets on weighting and discussing the NYT /  SIenna poll weighting being 
  # done right now by Nate Cohn).
  # 
  # 2) CCES 2020
  # - The CCES original weights are weighted to the VAP.  We confirm that weighting
  # to the weighted CCES variables listed in 1 get us similar results to confirm. [WEIGHT 2]
  
  # - If so, then we can add other variables — e.g., we could use PID3 (or PID7), 
  #   or other opinion variables to construct similar targets to see how much the 
  #   results change. [WEIGHT 3]
  # 
  # - Then we can use the CCES to try to model the electorate in 2020.  
  #   [Same procedure would be used to o 2018, 2016, 2014]
  
  # - Take CCES and then restrict to self - reported likely voters.  Then reweight 
  #   the weighted result to the actual national vote (could do this state by state ?
  # ) by multiplying the original weight by the appropriate fraction.  Then use the re -
  #   weighted weighted distribution of desmpgraphics to identify targets and
  #   weight results to those targets. That would be the likely 2020 electorate. [WEIGHT 4]
  
  # - We could also do the same thing but restricted to validated voters.  Take 
  #   data, subset to validated voter, reweight to match national popular vote 
  #   based on weighted self -
  
  #   report, compute re - weighted demographic targets, weight.  This would be the actual 2020 electorate. [WEIGHT 5]
  # - For each of these [WEIGHT 4, WEIGHT5] we can then add additional variables (e.g., libcon, pid, etc.) [WEIGHT 6, 7]
  
  age_margins = ps %>% 
    group_by(agegrp) %>% 
    summarise(prop = sum(est_prop)) %>% 
    mutate(variable = "agegrp") %>% 
    rename(level = agegrp)
  
  race_margins = ps %>% 
    group_by(race) %>% 
    summarise(prop = sum(est_prop)) %>% 
    mutate(variable = "race") %>% 
    rename(level = race)
  
  gender_margins = ps %>% 
    group_by(gender) %>% 
    summarise(prop = sum(est_prop)) %>% 
    mutate(variable = "gender") %>% 
    rename(level = gender)
  
  educ_margins = ps %>% 
    group_by(educ) %>% 
    summarise(prop = sum(est_prop)) %>% 
    mutate(variable = "educ") %>% 
    rename(level = educ)
  
  # race X educ
  race_educ_margins = ps %>% 
    group_by(educ, race) %>% 
    summarise(prop = sum(est_prop)) %>% 
    mutate(variable = "race_educ") %>% 
    mutate(level = paste0(educ, " - ", race)) %>% 
    ungroup() %>% 
    select(variable, level, prop)
    
  # nonwhite x educ x age
  nonwhite_educ_age_margins = ps %>% 
    mutate(white = ifelse(race == "white", "white", "nonwhite")) %>% 
    group_by(white, educ, agegrp) %>% 
    summarise(prop = sum(est_prop)) %>% 
    mutate(variable = "nonwhite_educ_agegrp") %>% 
    mutate(level = paste0(white, " - ", educ, " - ", agegrp)) %>% 
    ungroup() %>% 
    select(variable, level, prop)
  
  
  margins = bind_rows(age_margins, race_margins, educ_margins, 
                      gender_margins, race_educ_margins, nonwhite_educ_age_margins)
  margins = margins %>% 
    mutate(year = y) %>% 
    relocate(year)
  
  
  saveRDS(margins ,file= paste0("data/internal/ACS_margins_", y, ".rds"))





}


