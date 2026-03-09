## Prepare survey monkey 2022 data


# Prepare Survey Data -----------------------------------------------------

# Read SurveyMonkey Data
sm = readRDS("data/survey/CleanedSM_Weighted.rds")





##  Recode SM Data
sm = sm %>% 
  # Detailed hispanic variable
  mutate(hispanic_detail = case_when(
    !hispanic ~ "not hispanic",
    hispanic.mexico ~ "mexican",
    hispanic.pr & !hispanic.cuba ~ "puerto rican",
    !hispanic.pr & hispanic.cuba ~ "cuban",
    is.na(hispanic) | is.na(race) ~ NA_character_,
    TRUE ~ "other hispanic"
  )) %>% 
  mutate(race_detail = case_when(
    race == "hispanic" ~ hispanic_detail,
    TRUE ~ race
  )) %>% 
  mutate(
    
    # PID variables
    dem_pid = case_when(
      pid.out == "Democrat" ~ 1L,
      pid.out == "Republican" ~ 0L,
      pid.out == "Independent" ~ 0L,
      TRUE ~ NA_integer_),
    rep_pid = case_when(
      pid.out == "Democrat" ~ 0L,
      pid.out == "Republican" ~ 1L,
      pid.out == "Independent" ~ 0L,
      TRUE ~ NA_integer_),
    ind_pid = case_when(
      pid.out == "Democrat" ~ 0L,
      pid.out == "Republican" ~ 0L,
      pid.out == "Independent" ~ 1L,
      TRUE ~ NA_integer_),
    
    # Biden Approval
    biden_approve = case_when(
      biden.approval.out == "Approve Biden" ~ 1L,
      biden.approval.out == "Disapprove Biden" ~ 0L,
      TRUE ~ NA_integer_),
    
    # Trust
    mostlytrust = case_when(
      general.trust == "Always" ~ 1L,
      general.trust == "Most of the time" ~ 1L,
      general.trust == "Never" ~ 0L,
      general.trust == "Some of the time" ~ 0L,
      TRUE ~ NA_integer_),
    
    # Immigration
    immigrantshelp = case_when(
      immigration.effect == "Help the country" ~ 1L,
      immigration.effect == "Hurt the country" ~ 0L,
      TRUE ~ NA_integer_),
    
    # Vote choice variables
    presvote2020_twoparty = case_when(
      presvote2020 == "dem" ~ 1L,
      presvote2020 == "rep" ~ 0L,
      presvote2020 == "dnv/other" ~ NA_integer_,
      TRUE ~ NA_integer_),
    
    housevote2022_twoparty = case_when(
      generic.house.topline == "Democrat" | vote.national.house == "Democratic Party candidate" | house.vote.party == "dem" | house.pro.party == "dem" ~ 1L,
      generic.house.topline == "Republican" | vote.national.house == "Republican Party candidate" | house.vote.party == "rep" | house.pro.party == "rep" ~ 0L,
      TRUE ~ NA_integer_),
    senvote2022_twoparty = case_when(
      senate.topline == "Democrat" | vote.national.senate == "The Democratic candidate" | senate.vote.party == "dem" | senate.pro.party == "dem" ~ 1L,
      senate.topline == "Republican" | vote.national.senate == "The Republican candidate" | senate.vote.party == "rep" | senate.pro.party == "rep" ~ 0L,
      TRUE ~ NA_integer_),
    govvote2022_twoparty = case_when(
      governor.topline == "Democrat" | vote.national.governor == "The Democratic Party candidate" | governor.vote.party == "dem" | governor.pro.party == "dem" ~ 1L,
      governor.topline == "Republican" | vote.national.governor == "The Republican Party candidate" | governor.vote.party == "rep" | governor.pro.party == "rep" ~ 0L,
      TRUE ~ NA_integer_
    ),
    miprop3vote2022 = mi.p3.topline,
    sosvote2022_twoparty = case_when(
      sos.topline == "Democrat" ~ 1L,
      sos.topline == "Republican" ~ 0L,
      TRUE ~ NA_integer_
    ),
    
    animus_rep = ifelse(partisan.animus == "Republicans are a danger to our country and must be defeated at any cost", 1, 0),
    animus_dem = ifelse(partisan.animus == "Democrats are a danger to our country and must be defeated at any cost", 1, 0)
  )





## Add binary variables ----------------------------------------------------


## Pick out questions to use in IRT model
sm = sm %>% 
  mutate(
    pres2020_irt = presvote2020_twoparty,
    immig_help_irt = immigrantshelp,
    biden_appr_irt = ifelse(biden.approval.out == "Approve Biden", 1, 0),
    trump_appr_irt = ifelse(trump.approval == "Favorable", 0, 1),
    loan_forgive_irt = case_when(
      loan.forgive.approve %in% c("Somewhat approve", "Stronly approve") ~ 1L,
      loan.forgive.approve %in% c("Somewhat disapprove", "Stronly disapprove") ~ 0L,
      TRUE ~ NA_integer_),
    trans_sports_irt = case_when(
      transgender.sports == "Yes" ~ 1L,
      transgender.sports == "No" ~ 0L,
      TRUE ~ NA_integer_
    ),
    affirm_action_irt = case_when(
      affirm.action.approve %in% c("Strongly favor", "Somewhat favor")  ~ 1L,
      affirm.action.approve %in% c("Strongly oppose", "Somewhat oppose")  ~ 0L,
      TRUE ~ NA_integer_
    ),
    trust_elec_irt = case_when(
      trust.elections.fair %in% c("A good amount", "A great deal") ~ 1L,
      trust.elections.fair %in% c("Not very much", "Not at all") ~ 0L,
      TRUE ~ NA_integer_
    ),
    climate_concern_irt = case_when(
      climate.concern %in% c("Somewhat concerned", "Very concerned") ~ 1L,
      climate.concern %in% c("Not at all concerned", "Not so concerned") ~ 0L,
      TRUE ~ NA_integer_
    ),
    election_fair_irt = case_when(
      grepl("Not", election.rating) ~ 0L,
      is.na(election.rating) ~ NA_integer_,
      TRUE ~ 1L       
    ),
    biden_legitimate_irt = case_when(
      biden.legitimate == "Yes" ~1L,
      biden.legitimate == "No" ~ 0L
    ),
    blm_appr_irt = case_when(
      blm.approval %in% c("Somewhat approve", "Stronly approve") ~ 1L,
      blm.approval %in% c("Somewhat disapprove", "Stronly disapprove") ~ 0L,
      TRUE ~ NA_integer_
    ),
    ukrain_aid_irt = case_when(
      ukraine.aid %in% c("Somewhat approve", "Stronly approve") ~ 1L,
      ukraine.aid %in% c("Somewhat disapprove", "Stronly disapprove") ~ 0L,
      TRUE ~ NA_integer_
    ),
    semiauto_weapons_irt = ifelse(semiauto.weapons == "No", 1, 0)
  )

# Make sure all responses are positively correlated (1 = liberal response)
stopifnot(sm %>% 
            select(ends_with("irt")) %>%
            cor(use = "pair") %>% 
            min(na.rm = TRUE) %>%
            sign() == 1)
