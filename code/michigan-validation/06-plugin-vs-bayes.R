# See how similar plugin and full bayes estimates are. 
# Do calibration both ways then see correlation at PS cell level.


library(tidyverse)
library(lubridate)
library(brms)
library(ggplot2)
library(calibratedMRP)

TEST <- FALSE

set.seed(4052250) # from random.org

theme_set(theme_classic() + 
            theme(axis.text = element_text(size = 14), 
                  title = element_text(size = 16),
                  strip.text = element_text(size = 16),
                  legend.text = element_text(size = 14)))


# Prep data --------------------------------------------------------------

source("code/michigan-validation/01-prep-data-michigan.R")

# subset to data collected within 3 weeks of the election
sm <- subset(sm, date >= ymd("2022-10-18"))

# MI poststratification table and calibration targets
mi_ps <- ps_cty %>% filter(state == "MI")

# calibration targets
calib_target <- res22 %>% 
  filter(countyfips %in% mi_ps$countyfips)

# add county gov results to poststrat table and survey
mi_ps <- left_join(mi_ps, 
                   calib_target %>% 
                     select(countyfips, county_gov = gov), 
                   by = "countyfips")
sm <- sm %>% 
  left_join(calib_target %>% 
              select(countyfips, county_gov = gov), 
            by = "countyfips")





## Fit model for Michigan. We will model responses on the following questions:
#  governor and MI Abortion Prop 
outcomes_orig <- c("gov", "michprop3")
predictors <- c("gender", "agegrp", "race", "educ")
sm_mi <- sm %>% 
  filter(state == "MI") %>% 
  drop_na(all_of(c(outcomes_orig, predictors)))

outcomes <- str_remove_all(outcomes_orig, "_")




# Fit MV model ------------------------------------------------------------


## Define Formula ##
form <- bf(
  # outcomes
  mvbind(gov, michprop3) ~
    
    # individual-level predictors
    gender + as.integer(agegrp) + (1 | age | agegrp) + race + educ +
    (1 | raceeduc | race_educ) + (1 | educagewhite | nonwhite_educ_agegrp) + 
    
    # county-level predictors
    cty_pct_nonwhite_z +  cty_pct_hispanic_z +
    cty_pct_college_z + cty_med_inc_z + cty_dem2020_z +
    (1 | c | countyfips) 
)


gp <- get_prior(formula = form, data = sm_mi, family = bernoulli())
priors <- gp |>
  mutate(prior = ifelse(class == "b" & prior == "", "normal(0,5)", prior))

# fit model
mod <- brm(
  formula = form,
  data = sm_mi,
  family = bernoulli,
  prior = priors,
  cores = 4,
  chains = 4,
  iter = 800,
  backend = "cmdstanr",
  adapt_delta = .99,
  max_treedepth = 12
)



calib_bayes <- calibrate_mrp(
  model = mod,
  ps_table = mi_ps,
  weight = "est_n",
  geography = "countyfips",
  outcomes = outcomes,
  targets = calib_target %>% select(countyfips, gov),
  method = "bayes"
)

calib_plugin <- calibrate_mrp(
  model = mod,
  ps_table = mi_ps,
  weight = "est_n",
  geography = "countyfips",
  outcomes = outcomes,
  targets = calib_target %>% select(countyfips, gov),
  method = "plugin"
)

# summarize
sum_bayes <- calib_bayes$results |>
  summarize(bayes = mean(michprop3_calib), .by = c(.cellid, countyfips, est_n))

sum_plugin <- calib_plugin$results |>
  summarize(plugin = mean(michprop3_calib), .by = c(.cellid))

cell_est <- full_join(
  sum_bayes,
  sum_plugin,
  by = ".cellid"
)
lm(bayes ~ plugin, data = cell_est) |> summary()
cor(cell_est$bayes, cell_est$plugin)
