# simulations of MV calibration using CCES data as "population" 

library(tidyverse)
library(sjlabelled)
library(lme4)





# Data prep ---------------------------------------------------------------

## Poststrat table ----------------------------------------------------

source("code/functions.R")
source("code/prep-covariates.R")

## CCES ---------------------------------------------------------------

## Cumulative files
cces_policy <- rio::import("data/ces/cces-policy/cumulative_ces_policy_preferences.dta")
cces_cumul <- rio::import("data/ces/cces-cumulative/cumulative_2006-2024.feather")


## 2022
cces22 <- rio::import("data/ces/cces-2022/CCES22_Common_OUTPUT_vv_topost.dta")
cces22 <- cces22 %>% 
  select(case_id = caseid, 
         immig_legalize = CC22_331a,
         immig_border = CC22_331b,
         immig_reduce = CC22_331c,
         immig_wall = CC22_331d,
         abortion_always = CC22_332a,
         abortion_conditional = CC22_332b,
         abortion_20weeks = CC22_332c,
         abortion_prohibit = CC22_332f,
         spending_welfare = CC22_443_1,
         spending_healthcare = CC22_443_2,
         spending_education = CC22_443_3,
         spending_infrastructure = CC22_443_5,
         enviro_carbon = CC22_333a,
         enviro_renewable = CC22_333b,
         enviro_mpg_raise = CC22_333d
  ) %>% 
  mutate(year = 2022)

## 2023 
cces23 <- rio::import("data/ces/cces-2023/CCES23_Common_OUTPUT.dta")
cces23 <- cces23 %>% 
  select(case_id = caseid,
         immig_legalize = CC23_323a,
         immig_border = CC23_323b,
         immig_wall = CC23_323c,
         immig_dreamers = CC23_323d,
         enviro_carbon = CC23_326a,
         enviro_renewable = CC23_326b,
         abortion_always = CC23_324a,
         abortion_conditional = CC23_324b,
         abortion_prohibit = CC23_324c
  ) %>% 
  mutate(year = 2023)



## Combine
cces_policy <- bind_rows(cces_policy %>% mutate(case_id = as.integer(case_id)), 
                         cces22, cces23)

cces <- tidylog::left_join(cces_cumul, cces_policy %>% mutate(policy = 1), by = c("case_id", "year"))
table(cces$year, cces$policy, useNA="if")
cces$policy <- NULL

cces <- cces %>% 
  mutate(FIPS = as.numeric(county_fips))





## CCES demos -----------------------------------------------------------

cces <- cces %>% 
  mutate(
    pres_dem = case_when(
      voted_pres_20 == "Joe Biden" ~ 1L, 
      voted_pres_20 != "Joe Biden" ~ 0L,
      is.na(voted_pres_20) ~ 0L
    ),
    pres_rep = case_when(
      voted_pres_20 == "Donald Trump" ~ 1L, 
      voted_pres_20 != "Donald Trump" ~ 0L,
      is.na(voted_pres_20) ~ 0L
    ),
    pres_dnv = case_when(
      is.na(voted_pres_20) ~ 1L,
      voted_pres_20 != "Joe Biden" & voted_pres_20 != "Donald Trump" ~ 1L,
      TRUE ~ 0L
    ),
    party = as_label(pid3),
    college = educ >= 5,
    female = 1 - gender,
    age = year - birthyr,
    gender = case_when(gender == 1 ~ "male", gender == 2 ~ "female"),
    race = case_when(
      race_h == 1 ~ "white",
      race_h == 2 ~ "black",
      race_h == 3 ~ "hispanic",
      race_h == 4 ~ "asian",
      TRUE ~ "other"
    ),
    agegrp = case_when(
      age >= 18 & age <= 29 ~ "18-29", 
      age >= 30 & age <= 39 ~ "30-39", 
      age >= 40 & age <= 49 ~ "40-49",
      age >= 50 & age <= 64 ~ "50-64",
      age >= 65 & age <= 74 ~ "65-74",
      age >= 75 ~ "75+"
    ),
    educ2 = case_when(
      educ %in% c(1, 2) ~ "HS or less",
      educ %in% c(3, 4) ~ "some college",
      educ == 5 ~ "college",
      educ == 6 ~ "postgrad"
    )) %>% 
  mutate(educ2 = factor(educ2, c("HS or less", "some college", "college", "postgrad")),
         agegrp = fct_reorder(agegrp, age)) %>% 
  mutate(state = st) %>% 
  mutate(educ = educ2)


# recode income to midpoint of categories
cces <- cces %>%
  mutate(
    faminc_num = case_when(
      # ~10k increments
      faminc %in% c("Less than 10k", "Less than $10,000") ~ 5000,
      faminc %in% c("10k - 20k", "$10,000 - $19,999")     ~ 15000,
      faminc %in% c("20k - 30k", "$20,000 - $29,999")     ~ 25000,
      faminc %in% c("30k - 40k", "$30,000 - $39,999")     ~ 35000,
      faminc %in% c("40k - 50k", "$40,000 - $49,999")     ~ 45000,
      faminc %in% c("50k - 60k", "$50,000 - $59,999")     ~ 55000,
      faminc %in% c("60k - 70k", "$60,000 - $69,999")     ~ 65000,
      faminc %in% c("70k - 80k", "$70,000 - $79,999")     ~ 75000,
      faminc %in% c("80k - 100k", "$80,000 - $99,999")    ~ 90000,
      
      # 100k+ increments
      faminc %in% c("100k - 120k", "$100,000 - $119,999") ~ 110000,
      faminc %in% c("120k - 150k", "$120,000 - $149,999") ~ 135000,
      faminc == "150k+"                                   ~ 200000,
      faminc %in% c("$150,000 - $199,999")                ~ 175000,
      faminc %in% c("$200,000 - $249,999")                ~ 225000,
      faminc %in% c("$250,000 - $349,999")                ~ 300000,
      faminc %in% c("$350,000 - $499,999")                ~ 425000,
      faminc == "$500,000 or more"                        ~ 750000,
      
      # Non-response or missing
      faminc %in% c("Prefer not to say", "Skipped") ~ NA_real_,
      is.na(faminc)                                ~ NA_real_,
      
      # Default if something unexpected appears
      TRUE ~ NA_real_
    )
  )


setequal(na.omit(cces$gender), ps_cty$gender)
setequal(na.omit(cces$educ2), ps_cty$educ)
setequal(na.omit(cces$agegrp), ps_cty$agegrp)
setequal(na.omit(cces$race), ps_cty$race)


## CCES policy items ------------------------------

# to analyze
codebook <- tribble( ~ varname, ~ desc, ~ category, ~ binary,
                     "immig_legalize", "Grant legal status to undocumented", "immigration", 1,
                     "immig_border", "Increase border patrols", "immigration", 1, 
                     "immig_deport", "Deport illegal immigrants", "immigration", 1, 
                     "immig_reduce", "Reduce legal immigration by 50%", "immigration", 1, 
                     
                     "abortion_always", "Always legal", "abortion", 1, 
                     "abortion_conditional", "Legal only for rape, incest, health of mother", "abortion", 1, 
                     "abortion_20weeks", "Ban after 20 weeks", "abortion", 1, 
                     "abortion_prohibition", "Outlaw in all cases", "abortion", 1,
                     
                     "gaymarriage_legalize", "Legalize gay marriage", "lgbt", 1, 
                     
                     "affirmativeaction", "Oppose affirmative action*", "race", 0, 
                     
                     "spending_welfare", "Decrease spending on welfare*", "econ", 0,
                     "spending_healthcare", "Decrease spending on healthcare*", "econ", 0,
                     "spending_education", "Decrease spending on education*", "econ", 0,
                     "spending_infrastructure", "Decrease spending on infrastructure*", "econ", 0,
                     "incometax_vs_salestax", "Income vs. sales tax*", "econ", 0,
                     
                     "enviro_carbon", "Empower EPA to regulate CO2 emissions", "environment", 1, 
                     "enviro_renewable", "Mandate renewables in energy production", "environment", 1, 
                     "enviro_mpg_raise", "Improve MPG standards", "environment", 1,
                     
) %>% 
  mutate(desc = factor(desc, desc))

## Recode binary variables so 1 = support
cces <- cces %>% 
  mutate(across(all_of(codebook$varname[codebook$binary==1]),
                ~ case_when(.x == 2 ~ 0,
                            .x == 1 ~ 1))) %>% 
  mutate(incometax_vs_salestax = ifelse(incometax_vs_salestax > 100, NA, incometax_vs_salestax)) %>% 
  mutate(incometax_vs_salestax = incometax_vs_salestax / 100) %>% 
  mutate(incometax_vs_salestax = -1 * incometax_vs_salestax + 1)



# Merge state covariates -------------------------------------------------

cces <- left_join(cces, state_covs |> 
  select(state, st_demvs_2016_z, st_demvs_2020_z, st_pct_college_z, st_pct_nonwhite_z, st_med_inc_z),
 by = "state")



# Select variables for validation -----------------------------------------

# use 2020 election as calibration target, use all years before 2024 as 
# survey baseline

cces <- filter(cces, year >= 2020 & year < 2024)

# find variables with < 10% missingness
varmis <- sapply(cces, function(x) mean(is.na(x)))
varn   <- sapply(cces, function(x) sum(!is.na(x)))
vars <- data.frame(varname = names(varmis), 
                   miss = varmis,
                   n = varn)
vars <- left_join(codebook, vars, by = "varname")
vars <- vars %>% filter(miss < 0.5)


# see correlation with vote choice
for (v in vars$varname) {
  print(v)
  # print(prop.table(table(cces$pres_dem, cces[[v]]), 1))
  print(sprintf("cor = %s", round(cor(cces$pres_dem, cces[[v]], use = "pa"), 2)))
  print(sprintf("n = %s", sum(!is.na(cces[[v]]))))
  cat("\n\n")
}
prop.table(table(cces$enviro_carbon))


# spending_infrastructure seems promising but lots of missing data :(
cces$spending_infrastructure <- cces$spending_infrastructure >= 3
cces$spending_infrastructure <- -1 * cces$spending_infrastructure + 1






# Fit model for baseline probability -------------------------------------


# Pick three outcomes 
#   - abortion_conditional Legal only for rape, incest, health of mother, 
#         Cor w/ dem vote = -0.34
#   - enviro_carbon Empower EPA to regulate CO2 emissions. Cor w/ dem vote > .6
#   - spending_infrastructure - this is a 1-5 scale, dichotomozize at 3. Cor -0.18
cor(cces$spending_infrastructure, cces$pres_dem, use = "pa")

## Baseline models 
rhs <- ~ agegrp * race + gender * educ 

m1 <- glm(update.formula(enviro_carbon ~ ., rhs),
          weights = cces$weight_cumulative,
          data = cces,
          family = "binomial")
m2 <- glm(update.formula(spending_infrastructure ~ ., rhs),
          weights = cces$weight_cumulative,
          data = cces,
          family = "binomial")
m3 <- glm(update.formula(pres_dem ~ ., rhs),
          weights = cces$weight_cumulative,
          data = cces,
          family = "binomial")
m4 <- glm(update.formula(pres_rep ~ ., rhs),
          weights = cces$weight_cumulative,
          data = cces,
          family = "binomial")
m5 <- glm(update.formula(pres_dnv ~ ., rhs),
          weights = cces$weight_cumulative,
                    data = cces,
                    family = "binomial")

# generate baseline predicted values
predm1 <- predict(m1, newdata = cces, type = "response")
predm2 <- predict(m2, newdata = cces, type = "response")
predm3 <- predict(m3, newdata = cces, type = "response")
predm4 <- predict(m4, newdata = cces, type = "response")
predm5 <- predict(m5, newdata = cces, type = "response")

cces <- cces %>% 
  mutate(spending_infrastructure_pi = predm1,
         abortion_conditional_pi = predm2,
         pres_dem_pi = predm3,
         pres_rep_pi = predm4,
         pres_dnv_pi = predm5)



# Subset dataset to relevant vars  -----------------------------------------------

outcomes <- c("pres_dem", "pres_rep", "pres_dnv", "enviro_carbon", "spending_infrastructure", "abortion_conditional")
predictors <- c("agegrp", "race", "gender", "educ", "state")
context <- intersect(names(cces), names(state_covs))
others <- c("year", "case_id", "weight_cumulative")
dat <- cces |> select(all_of(c(others, predictors, context, outcomes)), ends_with("_pi"))




saveRDS(dat, "data/frozen/CES_for_simulation_frozen.rds")
