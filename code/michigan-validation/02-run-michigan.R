# Michigan validation exercise

library(tidyverse)
library(lubridate)
library(brms)
library(future)
library(furrr)
# library(ggdist)
library(kableExtra)
library(ggplot2)
library(calibratedMRP)

## Parse command-line arguments for refit flag
args <- commandArgs(trailingOnly = TRUE)
REFIT <- ! "--no-refit" %in% args

source("code/michigan-validation/01-prep-data-michigan.R")

if (parallel::detectCores() > 8) {
  future::plan(multisession, workers = 8)
} else {
  future::plan(multisession, workers = 4)
}
options(future.globals.maxSize = 1024 * 1024^2) 

set.seed(4052250) # from random.org

theme_set(theme_classic() + 
            theme(axis.text = element_text(size = 14), 
                  title = element_text(size = 16),
                  strip.text = element_text(size = 16),
                  legend.text = element_text(size = 14)))


rerun <- REFIT # re-estimate models?
limit_draw_ids <- FALSE

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




# Fit outcome model ------------------------------------------------------------


## Fit model for Michigan. We will model responses on the following questions:
#  1. governor, SOS, and Michigran Abortion Prop vote
#  2. Biden approval 
#  3. Whether Biden is the legitimate president
#  4. Whether elections in MI are conducted fairly 
outcomes_orig <- c("gov", "sos", "michprop3",
              "biden_legitimate_irt", 
              "biden_appr_irt", 
              "election_fair_irt",
              "dem_pid",
              "ind_pid",
              "rep_pid")
predictors <- c("gender", "agegrp", "race", "educ")
sm_mi <- sm %>% 
  filter(state == "MI") %>% 
  drop_na(all_of(c(outcomes_orig, predictors)))
sm_mi %>% nrow %>% prettyNum(big.mark = ",") %>% cat(file = "output/tables/numbers-in-text/michigan-sample-size.txt")
outcomes <- str_remove_all(outcomes_orig, "_")


## Raw results ------------------------------------------------------------

cat(100 * round(mean(sm_mi$gov), 3), file = "output/tables/numbers-in-text/raw-mi-gov-percent.tex")
cat(100 * round(mean(sm_mi$sos), 3), file = "output/tables/numbers-in-text/raw-mi-sos-percent.tex")
cat(100 * round(mean(sm_mi$michprop3 == "Yes"), 3), file = "output/tables/numbers-in-text/raw-mi-prop3-percent.tex")



## Define formula ---------------------------------------------------------

form <- bf(
  # outcomes
  mvbind(gov, sos, michprop3,
         biden_legitimate_irt,
         biden_appr_irt,
         election_fair_irt,
         dem_pid, 
         ind_pid, 
         rep_pid) ~
    
    # individual-level predictors
    gender + as.integer(agegrp) + (1 | age | agegrp) + race + educ +
    (1 | raceeduc | race_educ) + (1 | educagewhite | nonwhite_educ_agegrp) + 
    
    # county-level predictors
    cty_pct_nonwhite_z +  cty_pct_hispanic_z +
    cty_pct_college_z + cty_med_inc_z + cty_dem2020_z +
    (1 | c | countyfips) 
)

## Set priors ---------------------------------------------------------------
gp <- get_prior(formula = form, data = sm_mi, family = bernoulli())
mvpriors <- gp |>
  dplyr::mutate(prior = ifelse(class == "b" & prior == "", "normal(0,5)", prior)) 


## Run Model --------------------------------------------------------------
if (rerun) {
  mvmod <- brm(formula = form, 
             data = sm_mi,
             family = bernoulli,
             prior = mvpriors,
             chains = 4, 
             cores = 4,
             iter = 1200,
             backend = "cmdstanr",
             adapt_delta = .97,
             max_treedepth = 12)
  saveRDS(mvmod, "data/frozen/michigan-model-fit_frozen.rds")
} else {
  mvmod <- readRDS("data/frozen/michigan-model-fit_frozen.rds")
}

if (limit_draw_ids){
  draw_ids <- sample(1:ndraws(mvmod), 100) 
} else {
  draw_ids <- 1:ndraws(mvmod)
}


rhats <- rhat(mvmod)
if (max(rhats) > 1.02) rlang::warn("Some parameters have r-hat values above 1.02")
rstan::check_hmc_diagnostics(mvmod$fit)
neff <- neff_ratio(mvmod)
if (mean(neff) < 0.5 || min(neff) < 0.1) rlang::warn("Some parameters have low neff ratios")





# Fit individual models for MRsP ---------------------------------------------

unipriors <- prior(normal(0, 5), class = b)

govform <- form$forms$gov
prop3form <- form$forms$michprop3
prop3formgov <- update(prop3form, . ~ . + gov) # add gov vote
prop3formgovgeo <- update(prop3form, . ~ . + county_gov)

if (rerun){
  govmod <- brm(formula = govform, 
                data = sm_mi,
                family = bernoulli,
                prior = unipriors,
                chains = 4, cores = 4,
                iter = 1200,
                backend = "cmdstanr",
                adapt_delta = .97,
                max_treedepth = 12)
  
  prop3mod <- brm(formula = prop3form, 
                  data = sm_mi,
                  family = bernoulli,
                  prior = unipriors,
                  chains = 4, cores = 4,
                  iter = 1200,
                  backend = "cmdstanr",
                  adapt_delta = .97,
                  max_treedepth = 12)
  
  prop3govmod <- brm(formula = prop3formgov,
                     data = sm_mi,
                     family = bernoulli,
                     prior = unipriors,
                     chains = 4,
                     cores = 4,
                     iter = 1200,
                     backend = "cmdstanr",
                     adapt_delta = .97,
                     max_treedepth = 12)
  
  prop3govgeomod <- brm(formula = prop3formgovgeo,
                        data = sm_mi,
                        family = bernoulli,
                        prior = unipriors,
                        chains = 4,
                        cores = 4,
                        iter = 1200,
                        backend = "cmdstanr",
                        adapt_delta = .97,
                        max_treedepth = 12)

  save(govmod, prop3mod, prop3govmod, prop3govgeomod, 
       file = "data/frozen/michigan-mrsp-model-fits_frozen.rda")
  
  
  # run model diagnostics
  for (m in c("govmod", "prop3mod", "prop3govmod", "prop3govgeomod")) {
    sprintf("Diagnostics for model: %s", m)
    m <- get(m)
    rhats <- rhat(m)
    if (max(rhats) > 1.02) print("Some parameters have r-hat values above 1.02")
    rstan::check_hmc_diagnostics(m$fit)
    neff <- neff_ratio(m)
    if (mean(neff) < 0.5 || min(neff) < 0.1) print("Some parameters have low neff ratios")
  }
  
  
} else {
  load("data/frozen/michigan-mrsp-model-fits_frozen.rda")
}


# Calibrate cell-level estimates ----------------------------------------------


# Generate uncalibrated estimates
calib_0_draws <- generate_cell_estimates(
  model = mvmod,
  outcomes = outcomes,
  ps_table = mi_ps,
  summarize = FALSE,
  draw_ids = draw_ids
)


# Reset parallel plan
future::plan("sequential")
future::plan("multisession", workers = 4)

# Calibrate three times, using just governor results, then gov + sos, then all three
calib_1 <- calibrate_mrp(
  model = mvmod,
  ps_table = mi_ps,
  weight = "est_n",
  geography = "countyfips",
  outcomes = outcomes,
  targets = calib_target %>% select(countyfips, gov),
  method = "bayes", 
  posterior_summary = FALSE,
  draw_ids = draw_ids
)

# Reset parallel plan
future::plan("sequential")
future::plan("multisession", workers = 4)

calib_2 <- calibrate_mrp(
  model = mvmod,
  ps_table = mi_ps,
  weight = "est_n",
  geography = "countyfips",
  outcomes = outcomes,
  targets = calib_target %>% select(countyfips, gov, sos),
  method = "bayes", 
  posterior_summary = FALSE,
  draw_ids = draw_ids
)

# Reset parallel plan
future::plan("sequential")
future::plan("multisession", workers = 4)

calib_3 <- calibrate_mrp(
  model = mvmod,
  ps_table = mi_ps,
  weight = "est_n",
  geography = "countyfips",
  outcomes = outcomes,
  targets = calib_target %>% select(countyfips, gov, sos, michprop3),
  method = "bayes", 
  posterior_summary = FALSE,
  draw_ids = draw_ids
)



# Poststratify estimates within draw then summarize posterior -------------

## Poststratify uncalibrated estimates ------------------------------


res <- list()
for (i in seq_along(draw_ids)) {
  tmp <- calib_0_draws[i,,]
  tmp <- mi_ps %>% select(countyfips, est_n) %>% 
    bind_cols(as.data.frame(tmp))
  tmp <- poststratify(tmp, outcomes = all_of(outcomes), by = countyfips, weight = est_n)
  tmp$.draw <- i
  res[[i]] <- tmp
}
calib_0 <- bind_rows(res)
calib_0 <- calib_0 %>% 
  select(-n) %>% 
  group_by(countyfips) %>% 
  summarise(across(-c(.draw), 
                   list(mean = mean, 
                        median = median,
                        q5 = ~ quantile(.x, .05),
                        q95 = ~ quantile(.x, .95),
                        sd = sd
                   )) )
calib_0$calib <- "Uncalibrated"

## Poststratify calibrated estimates --------------------------------

out <- list()
i <- 1
for (res in list(calib_1, calib_2, calib_3)) {
  tmp <- res$results %>% 
    group_by(.draw) %>% 
    group_split() %>% 
    map(~ {
      poststratify(.x, outcomes = all_of(paste0(outcomes, "_calib")),
                   by = countyfips, weight = est_n)
    }) %>% 
    bind_rows(.id = ".draw") 
  
  tmp <- tmp %>% 
    rename_with(~ str_remove(.x, "_calib"), ends_with("_calib")) %>% 
    select(-n)
  
  tmp <- tmp %>% 
    group_by(countyfips) %>% 
    summarise(across(-c(.draw), 
                     list(mean = mean, 
                          median = median,
                          q5 = ~ quantile(.x, .05),
                          q95 = ~ quantile(.x, .95),
                          sd = sd
                     )) )
  
  tmp$calib <- case_when( i == 1 ~ "Gov.",
                          i == 2 ~ "Gov. + Sec. of State",
                          i == 3 ~ "Gov. + Sec. of State +\nAbortion Prop.")
  out[[i]] <- tmp
  i <- i + 1
}
out_sum <- bind_rows(out)
out_sum_orig <- out_sum


## Calculate MRsP estimates ----------------------------------

# Three flavors here: 
# prop3 model with and without governor vote as covariate
# prop3 model with county gov vote as contexxtual covariate
# If no gov covariate, then use regular census PS table
# If gov covariate, then try two PS tables: 1) synthetic PS table assuming
# independence of gov vote and covariates (MRsP solution); 2) PS table generated
# by calibrating a gov model


# Reset parallel plan
future::plan("sequential")
future::plan("multisession", workers = 4)



### Generate conventional synthetic poststratification  ------------

# assume independence between PS cells and gov vote (within county)
mi_ps_synth <- left_join(mi_ps, calib_target %>% select(countyfips, gov), by = "countyfips")
mi_ps_synth <- bind_rows(
  mi_ps_synth %>%
    mutate(est_n = est_n * gov, est_n = est_n * gov) %>%
    mutate(gov = 1),
  mi_ps_synth %>%
    mutate(est_n = est_n * (1 - gov), est_n = est_n * (1 - gov)) %>%
    mutate(gov = 0)
)


### Generate calibrated synthetic PS table ------------------------------

# Calibrate gov model to create an imputed PS table
govres <- calibrate_mrp(model = govmod,
                        ps_table = mi_ps,
                        weight = "est_n",
                        geography = "countyfips",
                        outcomes = "gov",
                        targets = calib_target,
                        method = "plugin", 
                        posterior_summary = TRUE,
                        draw_ids = draw_ids)

mi_ps_gov <- bind_rows(govres$results %>% 
                         mutate(est_n = gov_calib * est_n,
                                est_n = gov_calib * est_n) %>% 
                         mutate(gov = 1),
                       govres$results %>% 
                         mutate(est_n = (1 - gov_calib) * est_n,
                                est_n = (1 - gov_calib) * est_n) %>%
                         mutate(gov = 0)) %>% 
  select(-gov_calib)
mi_ps_gov <- left_join(mi_ps_gov, 
                       mi_ps %>% select(-est_prop, -est_n) %>% 
                         mutate(.cellid = row_number()))

# compare MRSP and calibrated PS tables
comp <- left_join(mi_ps_gov %>% select(-est_n, est_n_gov = est_n),
                  mi_ps_synth %>% select(-est_n, est_n_synth = est_n))
comp <- comp %>% 
  mutate(diff = 100 * (est_n_gov - est_n_synth)/est_n_synth)
plot(est_n_gov ~ est_n_synth, data = comp %>% filter(gov == 1))
hist(comp$diff)


ggplot(comp %>% filter(gov == 1)) + aes(x = race, y = diff) + stat_summary() + 
  labs(title = "Average increase in cell size for gov == 1",
       subtitle = "Conventional to calibrated MRsP")




### Generate estimates of Prop 3 using synthetic tables --------------

# using census PS table
prop3census <- generate_cell_estimates(
  model = prop3mod,
  outcomes = "michprop3",
  ps_table = mi_ps,
  summarize = FALSE,
  draw_ids = draw_ids
)

res <- list()
for (i in seq_along(draw_ids)) {
  tmp <- prop3census[i,,]
  tmp <- mi_ps %>% 
    mutate(michprop3 = tmp) %>% 
    group_by(countyfips) %>%
    summarise(michprop3 = weighted.mean(michprop3, est_n)) %>% 
    mutate(.draw = i)
  res[[i]] <- tmp
}
prop3census <- bind_rows(res)
prop3census <- prop3census %>% 
  group_by(countyfips) %>%
  summarise(michprop3_mean = mean(michprop3),
            michprop3_median = median(michprop3),
            michprop3_q5 = quantile(michprop3, .05),
            michprop3_q95 = quantile(michprop3, .95),
            michprop3_sd = sd(michprop3)) %>% 
  mutate(calib = "Conventional MRP")


# using synthetic gov table assuming independence
prop3synth <- generate_cell_estimates(
  model = prop3govmod,
  outcomes = "michprop3",
  ps_table = mi_ps_synth,
  summarize = FALSE,
  draw_ids = draw_ids
)
res <- list()
for (i in seq_along(draw_ids)) {
  tmp <- prop3synth[i,,]
  tmp <- mi_ps_synth %>% 
    mutate(michprop3 = tmp) %>% 
    group_by(countyfips) %>%
    summarise(michprop3 = weighted.mean(michprop3, est_n)) %>% 
    mutate(.draw = i)
  res[[i]] <- tmp
}
prop3synth <- bind_rows(res)
prop3synth <- prop3synth %>% 
  group_by(countyfips) %>%
  summarise(michprop3_mean = mean(michprop3),
            michprop3_median = median(michprop3),
            michprop3_q5 = quantile(michprop3, .05),
            michprop3_q95 = quantile(michprop3, .95),
            michprop3_sd = sd(michprop3)) %>% 
  mutate(calib = "Conventional MRsP")


# using calibrated gov table
prop3gov <- generate_cell_estimates(
  model = prop3govmod,
  outcomes = "michprop3",
  ps_table = mi_ps_gov,
  summarize = FALSE,
  draw_ids = draw_ids
)
res <- list()
for (i in seq_along(draw_ids)) {
  tmp <- prop3gov[i,,]
  tmp <- mi_ps_gov %>% 
    mutate(michprop3 = tmp) %>% 
    group_by(countyfips) %>%
    summarise(michprop3 = weighted.mean(michprop3, est_n)) %>% 
    mutate(.draw = i)
  res[[i]] <- tmp
}
prop3gov <- bind_rows(res)
prop3gov <- prop3gov %>% 
  group_by(countyfips) %>%
  summarise(michprop3_mean = mean(michprop3),
            michprop3_median = median(michprop3),
            michprop3_q5 = quantile(michprop3, .05),
            michprop3_q95 = quantile(michprop3, .95),
            michprop3_sd = sd(michprop3)) %>% 
  mutate(calib = "Calibrated MRsP")


# Using gov as contextual covariate
prop3govgeo <- generate_cell_estimates(
  model = prop3govgeomod,
  outcomes = "michprop3",
  ps_table = mi_ps_gov,
  summarize = FALSE,
  draw_ids = draw_ids
)
res <- list()
for (i in seq_along(draw_ids)) {
  tmp <- prop3govgeo[i,,]
  tmp <- mi_ps_gov %>% 
    mutate(michprop3 = tmp) %>% 
    group_by(countyfips) %>%
    summarise(michprop3 = weighted.mean(michprop3, est_n)) %>% 
    mutate(.draw = i)
  res[[i]] <- tmp
}
prop3govgeo <- bind_rows(res)
prop3govgeo <- prop3govgeo %>% 
  group_by(countyfips) %>%
  summarise(michprop3_mean = mean(michprop3),
            michprop3_median = median(michprop3),
            michprop3_q5 = quantile(michprop3, .05),
            michprop3_q95 = quantile(michprop3, .95),
            michprop3_sd = sd(michprop3)) %>% 
  mutate(calib = "MRP w/\nCounty Gov.")




## Merge results together --------------------------------------------

out_sum_wide <- bind_rows(out_sum_orig, calib_0, prop3census, prop3synth, prop3gov, prop3govgeo)
out_sum <- out_sum_wide %>% 
  pivot_longer(-c(countyfips, calib)) %>% 
  mutate(
    stat = stringr::str_match(name, "_([^_]+)$")[, 2],
    outcome = str_match(name, "^(.*?)_")[, 2]
  ) %>% 
  select(-name) %>%
  pivot_wider(names_from = "stat",
              values_from = "value") 

## Clean up labels for plotting
out_sum <- out_sum %>% 
  mutate(calib = fct_relevel(calib, c("Uncalibrated", 
                                      "Gov.",
                                      "Gov. + Sec. of State",
                                      "Gov. + Sec. of State +\nAbortion Prop.",
                                      "Conventional MRP",
                                      "MRP w/\nCounty Gov.",
                                      "Conventional MRsP",
                                      "Calibrated MRsP")),
         label = case_when(
           outcome == "gov" ~ "Governor",
           outcome == "sos" ~ "Secretary of State",
           outcome == "michprop3" ~ "Abortion Proposition",
           outcome == "bidenlegitimateirt" ~ "Biden Legitimate",
           outcome == "bidenapprirt" ~ "Biden Approval",
           outcome == "electionfairirt" ~ "Elections Fair",
           outcome == "dempid" ~ "PID: Dem.",
           outcome == "indpid" ~ "PID: Ind.",
           outcome == "reppid" ~ "PID: Rep.",
           TRUE ~ outcome
         )) %>% 
  mutate(label = fct(label, levels = c("Governor",
                                       "Secretary of State",
                                       "Abortion Proposition",
                                       "Biden Legitimate",
                                       "Biden Approval",
                                       "Elections Fair",
                                       "PID: Dem.",
                                       "PID: Ind.",
                                       "PID: Rep."))) %>% 
  mutate(type = case_when(
    outcome %in% c("gov", "sos", "michprop3") ~ "Vote",
    TRUE ~ "Attitude"
  ))

# mark the main calibration approaches vs. synth
out_sum <- out_sum %>% 
  mutate(main_sample = case_when(
    calib %in% c("Uncalibrated", "Gov.", "Gov. + Sec. of State", "Gov. + Sec. of State +\nAbortion Prop.") ~ TRUE,
    TRUE ~ FALSE
  ))


# Merge ground-truth data and calculate error--------------------------------

out_sum <- left_join(out_sum, 
                     calib_target %>% 
                       select(countyfips, any_of(outcomes)) %>% 
                       pivot_longer(-countyfips, names_to = "outcome", values_to = "true"), 
                     by = c("countyfips", "outcome"))

out_sum <- out_sum %>% 
  mutate(error = mean - true)


## Get errors in wide format
errors <- out_sum %>% 
  select(countyfips, calib, type, main_sample, outcome, label, error) %>% 
  # mutate(error = abs(error)) %>% 
  pivot_wider(values_from = "error",
              names_from = "calib")




# Analyze and plot results ------------------------------------------------

out_sum <- out_sum %>% 
  mutate(calib2 = fct(case_when(calib == "Gov." ~ "Governor",
                                calib == "Gov. + Sec. of State" ~ "Governor +\nSec. of State",
                                calib == "Uncalibrated" ~ "Uncalibrated"), 
                      c("Uncalibrated", 
                        "Governor", 
                        "Governor +\nSec. of State")))

ggplot(out_sum %>% 
         filter(calib != "Gov. + Sec. of State +\nAbortion Prop.", 
                type == "Vote",
                main_sample)) + 
  aes(x = true, y = mean) + 
  geom_abline(slope = 1, intercept = 0) +
  geom_point() +
  facet_grid(calib2 ~ label) +
  labs(x = "True Vote Share",
       y = "Modeled Vote Share")
ggsave("output/figures/mi-elections.pdf",width=8,height=5.5)



# Plot errors
ggplot(errors %>% 
         filter( type == "Vote", main_sample)) + 
  geom_vline(xintercept = 0) + 
  geom_segment(aes(x = Uncalibrated, 
                   xend = `Gov.`,
                   y = 3, 
                   yend = 2),
               colour = "grey50", 
               lwd = .1) + 
  geom_segment(aes(x = `Gov.`, 
                   xend = `Gov. + Sec. of State`,
                   y = 2, yend = 1),
               colour = "grey50", 
               lwd = .1) + 
  geom_point(aes(x = Uncalibrated, y = 3), size = .5) + 
  geom_point(aes(x = `Gov.`, y = 2),
             size = .5) + 
  geom_point(aes(x = `Gov. + Sec. of State`, y = 1),
             size = .5) + 
  scale_y_continuous(breaks = c(3, 2, 1), 
                     labels = c("Uncalibrated", "Calibrated to Governor", "Calibrated to Governor\n+ Secretary of State"),
                     limits = c(.75, 3.25)) + 
  facet_wrap(~label, ncol = 3) +
  theme(panel.grid.minor.y = element_blank()) + 
  labs(x = "County Error", y = NULL)  
ggsave("output/figures/mi-elections-error-reduction.pdf",
       height = 4, width =8)



ggplot(out_sum %>% 
         filter(type == "Vote",
                main_sample,
                abs(error) > 1e-5) %>% 
         mutate(calib2 = fct(case_when(calib == "Gov." ~ "Governor",
                                       calib == "Gov. + Sec. of State" ~ "Governor +\nSec. of State",
                                       calib == "Uncalibrated" ~ "None"), 
                             c("None", 
                               "Governor", 
                               "Governor +\nSec. of State"))) %>% 
         filter(!is.na(calib2))) +
  aes(x = error, fill = calib2) + 
  geom_vline(xintercept = 0, lty =2) + 
  geom_density(alpha = .5) +
  facet_wrap(~label, drop = TRUE) + 
  scale_y_continuous() + 
  scale_fill_discrete(name = "Calibration\nTarget") + 
  theme(legend.position = "bottom",
        panel.spacing = unit(5, "mm")) + 
  labs(x = "County-Level Error", y = "Density")
ggsave("output/figures/mi-election-error-density.pdf", width=8, height=4)







# save errors to table
error_tab <- out_sum %>% 
  filter(type == "Vote", main_sample) %>% 
  mutate(calib = fct(case_when(calib == "Gov." ~ "Governor",
                               calib == "Gov. + Sec. of State" ~ "Governor +\nSec. of State",
                               calib == "Uncalibrated" ~ "None"), 
                     c("None", 
                       "Governor", 
                       "Governor +\nSec. of State"))) %>%  
  group_by(label, calib) %>% 
  summarise(across(error, 
                   list(`Mean Signed Error` = ~ round(mean(.x)*100, 1), 
                        `Mean Abs. Error` = ~ round(mean(abs(.x))*100, 1),
                        `Root Mean Sq. Error` = ~round(sqrt(mean((100*.x)^2)), 1),
                        `Minimum`  = ~ round(min(.x)*100, 1), 
                        `Maximum`  = ~ round(max(.x)*100, 1)),
                   .names = "{.fn}")) %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ format(.x, nsmall = 1))) %>% 
  filter(!is.na(calib))

error_tab <- error_tab %>% 
  ungroup() %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ {
    case_when(row_number() %in% c(2, 3, 6) ~ "-",
              TRUE ~ .x)
  }))
  

error_tab %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ {
    case_when(.x == 0 ~ "$-$",
              TRUE ~ sprintf("$%s$", .x))
  })) %>% 
  rename(`Calibration Target` = calib,
         Race = label) %>% 
  mutate(Race = ifelse(row_number() %% 3 != 1, "", as.character(Race)),
         `Calibration Target` = linebreak(`Calibration Target`)) %>%
  mutate(Race = case_when(
    Race == "Secretary of State" ~ "Secretary\nof State",
    Race == "Abortion Prop." ~ "Abortion\nProposition",
    TRUE ~ Race
  )) %>% 
  mutate(Race = linebreak(Race, align = "r")) %>% 
  kable(format = "latex",align = 'r', 
        booktabs = TRUE, 
        escape = FALSE,
        linesep = c("", "", "\\addlinespace"),
        col.names = linebreak(c("Race", "Calibration\nTarget", "Mean\nSigned Error", 
                                "Mean\nAbs. Error", "Root Mean\nSq. Error", "Min.\nError", "Max.\nError"),
                              align = "r")) %>% 
  row_spec(c(3,6), extra_latex_after = "\\midrule") %>% 
  gsub("$0.0$", "$-$", .) %>% 
  cat(file = "output/tables/michigan-calibration-error-reduction.tex")








# Write small files for numbers in main text -----------------------------

# Mean Signed Error of SOS before calibration, after gov calibration, and % reduction
cat((error_tab$`Mean Signed Error`[error_tab$label == "Secretary of State" & error_tab$calib == "None"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/sos-msgnederror-uncalib.tex")
cat((error_tab$`Mean Signed Error`[error_tab$label == "Secretary of State" & error_tab$calib == "Governor"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/sos-msgnederror-calib-gov.tex")
abs((as.numeric(error_tab$`Mean Signed Error`[error_tab$label == "Secretary of State" & error_tab$calib == "Governor"]) - 
       as.numeric(error_tab$`Mean Signed Error`[error_tab$label == "Secretary of State" & error_tab$calib == "None"])) / 
      as.numeric(error_tab$`Mean Signed Error`[error_tab$label == "Secretary of State" & error_tab$calib == "None"])) %>% 
  {round(. * 100, 0)} %>% 
  {sprintf("$%s\\%%$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/sos-msnederror-reduction.tex")



# Mean Absolute error of SOS before calibration and after calibration
cat((error_tab$`Mean Abs. Error`[error_tab$label == "Secretary of State" & error_tab$calib == "None"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/sos-mae-uncalib.tex")
cat((error_tab$`Mean Abs. Error`[error_tab$label == "Secretary of State" & error_tab$calib == "Governor"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/sos-mae-calib-gov.tex")
abs((as.numeric(error_tab$`Mean Abs. Error`[error_tab$label == "Secretary of State" & error_tab$calib == "Governor"]) - 
       as.numeric(error_tab$`Mean Abs. Error`[error_tab$label == "Secretary of State" & error_tab$calib == "None"])) / 
      as.numeric(error_tab$`Mean Abs. Error`[error_tab$label == "Secretary of State" & error_tab$calib == "None"])) %>% 
  {round(. * 100, 0)} %>% 
  {sprintf("$%s\\%%$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/sos-mae-reduction.tex")


# Range of error for SOS before/after calib
unlist(error_tab[error_tab$label == "Secretary of State" & error_tab$calib == "Governor",][c("Minimum", "Maximum")]) %>% 
  paste0(collapse = ",") %>% 
  {sprintf("$[%s]$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/sos-error-range-calib-gov.tex")

unlist(error_tab[error_tab$label == "Secretary of State" & error_tab$calib == "None",][c("Minimum", "Maximum")]) %>% 
  paste0(collapse = ",") %>% 
  {sprintf("$[%s]$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/sos-error-range-uncalib.tex")






# Mean Absolute error of SOS before calibration and after calibration
cat((error_tab$`Mean Abs. Error`[error_tab$label == "Abortion Proposition" & error_tab$calib == "None"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/prop3-mae-uncalib.tex")
cat((error_tab$`Mean Abs. Error`[error_tab$label == "Abortion Proposition" & error_tab$calib == "Governor"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/prop3-mae-calib-gov.tex")

cat((error_tab$`Mean Abs. Error`[error_tab$label == "Abortion Proposition" & error_tab$calib == "Governor +\nSec. of State"]) %>% 
      str_remove("-") %>% 
      {sprintf("$%s$", .)},
    file = "output/tables/numbers-in-text/prop3-mae-calib-gov-sos.tex")

abs((as.numeric(error_tab$`Mean Abs. Error`[error_tab$label == "Abortion Proposition" & error_tab$calib == "Governor"]) - 
       as.numeric(error_tab$`Mean Abs. Error`[error_tab$label == "Abortion Proposition" & error_tab$calib == "None"])) / 
      as.numeric(error_tab$`Mean Abs. Error`[error_tab$label == "Abortion Proposition" & error_tab$calib == "None"])) %>% 
  {round(. * 100, 0)} %>% 
  {sprintf("$%s\\%%$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/prop3-mae-reduction.tex")



# Range of error for Prop3 before/after calib
unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "Governor +\nSec. of State",][c("Minimum", "Maximum")]) %>% 
  paste0(collapse = ",") %>% 
  {sprintf("$[%s]$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/prop3-error-range-calib-gov-sos.tex")

unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "Governor +\nSec. of State",][c("Minimum", "Maximum")]) %>% 
  as.numeric() %>% 
  diff() %>% 
  cat(file = "output/tables/numbers-in-text/prop3-error-range-width-calib-gov-sos.tex")

unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "None",][c("Minimum", "Maximum")]) %>% 
  as.numeric() %>% 
  diff() %>% 
  cat(file = "output/tables/numbers-in-text/prop3-error-range-width-uncalib.tex")


unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "None",][c("Minimum", "Maximum")]) %>% 
  paste0(collapse = ",") %>% 
  {sprintf("$[%s]$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/prop3-error-range-uncalib.tex")

# reduction in range
rr <- (diff(as.numeric(unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "Governor +\nSec. of State",][c("Minimum", "Maximum")]) )) - 
         diff(as.numeric(unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "None",][c("Minimum", "Maximum")]) )) ) / 
  diff(as.numeric(unlist(error_tab[error_tab$label == "Abortion Proposition" & error_tab$calib == "None",][c("Minimum", "Maximum")]) )) %>% 
  as.numeric() %>% 
  abs() 
round(rr*100  ,0) %>%
  abs() %>% 
  {sprintf("$%s\\%%$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/prop3-range-reduction.tex")





# Compare to MRsP ---------------------------------------------------------

methods <- c("Conventional MRP", "MRP w/\nCounty Gov.", "Conventional MRsP", "Calibrated MRsP", "Gov.")
labels <- gsub("Calibrated MRsP", "Chained Calibrated MRsP", methods)
labels <- gsub("^Gov.$", "MV Calibration", labels)
mrspdat <- out_sum %>% 
  filter(outcome == "michprop3", 
         calib %in%  methods) %>% 
  mutate(calib = fct_recode(calib, 
                            "MV Calibration" = "Gov.", 
                            "Chained Calibrated MRsP" = "Calibrated MRsP",
                            "MV Calibration 2" = "Gov. + Sec. of State")) %>% 
  mutate(calib = fct_relevel(calib, labels))

ggplot(mrspdat) + 
  aes(x = error, fill = calib) +
  geom_vline(xintercept = 0, lty = 2) + 
  geom_density(alpha = .4) + 
  theme(legend.position = "bottom") +
  labs(x = "County-Level Error", y = "Density", fill = NULL) + 
  guides(fill = guide_legend(nrow = 2))
ggsave("output/figures/error-density-mrsp-comparison.pdf", width=6,height=4)


ggplot(mrspdat) + 
  aes(x = true, y = mean) + 
  geom_abline(slope = 1, intercept = 0) + 
  geom_point() + 
  labs(x = "True Vote Share", y = "Modeled Vote Share") +
  facet_wrap(~ calib)
ggsave("output/figures/mrsp-comparison.pdf", width=9,height=6)



# error_tab <- out_sum %>% 
#   filter(outcome == "michprop3",
#          calib %in% c("Uncalibrated", methods)) %>% 
#   mutate(calib = case_when(
#     calib == "Univariate Uncalibrated" ~ "Conventional Uncalib.",
#     calib == "MRsP w/ Gov." ~ "Conventional MRsP",
#     calib == "MRsP w/ Calibrated Gov." ~ "Calibrated MRsP",
#     calib == "Uncalibrated" ~ "MV Uncalib.",
#     calib == "Gov." ~ "MV Calibrated"
#   )) %>% 
#   mutate(calib = fct_relevel(calib, c("Conventional Uncalib.",
#                                       "Conventional MRsP",
#                                       "Calibrated MRsP",
#                                       "MV Uncalib.",
#                                       "MV Calibrated"))) %>% 
error_tab_mrsp <- mrspdat %>% 
  group_by(calib) %>% 
  summarise(across(error, 
                   list(`Mean Signed Error` = ~ round(mean(.x)*100, 1), 
                        `Mean Abs. Error` = ~ round(mean(abs(.x))*100, 1),
                        `Root Mean Sq. Error` = ~round(sqrt(mean((100*.x)^2)), 1),
                        `Minimum`  = ~ round(min(.x)*100, 1), 
                        `Maximum`  = ~ round(max(.x)*100, 1)),
                   .names = "{.fn}")) %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ format(.x, nsmall = 1))) %>% 
  filter(!is.na(calib))


error_tab_mrsp %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ {
    case_when(.x == 0 ~ "$-$",
              TRUE ~ sprintf("$%s$", .x))
  })) %>% 
  rename(`Method` = calib) %>% 
  kable(format = "latex",align = 'r', 
        booktabs = TRUE, 
        escape = FALSE,
        linesep = c("", "", "\\addlinespace"),
        col.names = linebreak(c("Method", "Mean\nSigned Error", 
                                "Mean\nAbs. Error", "Root Mean\nSq. Error", "Min.\nError", "Max.\nError"),
                              align = "r")) %>% 
  cat(file = "output/tables/mrsp-error-reduction.tex")




# Show effect of calibration ----------------------------------------------

## Show how estimates change before and after calibration as a function of 
## error in auxiliary variable

out_calib_fx <- out_sum %>% 
  filter(calib %in% c("Uncalibrated", "Gov."),
         outcome %in% c("sos", "michprop3")) %>% 
  mutate(calib = case_when(
    calib == "Gov." ~ "Calibrated",
    TRUE ~ calib
  )) %>% 
  select(-error, -calib2) %>% 
  pivot_wider(values_from = mean:sd,
              names_from = calib)

# join with-county-level calibration errors
out_calib_fx <- left_join(out_calib_fx,
                          errors %>% 
                            filter(outcome == "gov",
                                   main_sample) %>% 
                            mutate(gov_error = Uncalibrated) %>% 
                            select(countyfips, gov_error),
                          by = "countyfips")
out_calib_fx <- left_join(out_calib_fx,
                          calib_target %>% 
                            select(countyfips, true_gov = gov),
                          by = "countyfips")


# Effect of calibration as a function of error in Governor estimate
ggplot(out_calib_fx) + 
  aes(y = mean_Calibrated - mean_Uncalibrated,
      x = gov_error) + 
  geom_point() + 
  geom_hline(yintercept = 0, lty = 2) + 
  geom_abline(slope = -1, intercept = 0) + 
  scale_x_continuous(labels = ~ sprintf("%spp", .x*100)) + 
  scale_y_continuous(labels = ~ sprintf("%spp", .x*100), breaks = round(seq(-1, 1, .05), 2)) + 
  facet_wrap(~label, scales = "free_x") + 
  theme(panel.spacing = unit(7, "mm"),
        plot.margin = margin(10, 10, 10, 10)) + 
  labs(x = "Overestimate of Dem. Governor Vote Share",
       y = "Effect of Calibration on\nEstimated Dem. Vote Share")
ggsave("output/figures/mi-calib-adjustment-by-gov-error.pdf",width=8,height=4)


ggplot(out_calib_fx) + 
  aes(y = mean_Calibrated - mean_Uncalibrated,
      x = true_gov) + 
  geom_point(colour = "grey60") + 
  geom_hline(yintercept = 0, lty = 2) + 
  geom_smooth(colour = "black", se = FALSE, span = .9) + 
  scale_x_continuous(labels = ~ sprintf("%spp", .x*100)) + 
  scale_y_continuous(labels = ~ sprintf("%spp", .x*100)) + 
  facet_wrap(~label, scales = "free_x") + 
  theme(panel.spacing = unit(7, "mm"),
        plot.margin = margin(10, 10, 10, 10)) + 
  labs(x = "Democratic Vote Share for Governor",
       y = "Change in Estimate After\nCalibration to Governor")
ggsave("output/figures/mi-calib-adjustment-by-gov-results.pdf",width=8,height=4)














# Examine covariance terms ---------------------------------------------------
vs <- c("gov", "sos", "michprop3")
labs <- c("Governor", "Secretary of State", "Abortion Prop.")

## Get survey-based estimates of county-level covariance
survey_covs <- get_re_covariance(mvmod, group = "countyfips", tidy = FALSE, draw_ids = draw_ids)
survey_covs_sum <- apply(survey_covs[, vs, vs], 2:3, mean)
rownames(survey_covs_sum) <- colnames(survey_covs_sum) <- labs
survey_covs_sum[!lower.tri(survey_covs_sum, diag = TRUE)] <- NA

survey_cor <- simplify2array(apply(survey_covs[, vs, vs], 1, cov2cor, simplify = FALSE))
survey_cor_sum <- apply(survey_cor, c(1,2), mean)
rownames(survey_cor_sum) <- colnames(survey_cor_sum) <- labs
survey_cor_sum[!lower.tri(survey_cor_sum, diag = TRUE)] <- NA

## Logit shift correlations
emp_covs <- calib_3$logit_shifts %>%
  group_by(.draw) %>% 
  group_split() %>% 
  map( ~ cov(select(.x, -c(.draw, countyfips))))
emp_covs <- simplify2array(emp_covs)
emp_covs <- emp_covs[c("gov_shift", "sos_shift", "michprop3_shift"), c("gov_shift", "sos_shift", "michprop3_shift"), ]
emp_covs_sum <- apply(emp_covs, c(1,2), mean)
rownames(emp_covs_sum) <- colnames(emp_covs_sum) <- labs
emp_covs_sum[!lower.tri(emp_covs_sum, diag = TRUE)] <- NA

emp_cor <- simplify2array(apply(emp_covs, 3, cov2cor, simplify = FALSE))
emp_cor_sum <- apply(emp_cor, c(1,2), mean)
rownames(emp_cor_sum) <- colnames(emp_cor_sum) <- labs
emp_cor_sum[!lower.tri(emp_cor_sum, diag = TRUE)] <- NA



emp_covs_sum <- round(emp_covs_sum, 3)
emp_covs_sum[is.na(emp_covs_sum)] <- ""
kable(emp_covs_sum, 
      digits = 3,
      format = "latex",align = 'r', 
      booktabs = TRUE, 
      escape = FALSE,
      na = "",
      linesep = "") %>% 
  column_spec(column = -1,
              width = "2cm") %>% 
  cat(file = "output/tables/michigan-empirical-covariances.tex")

emp_cor_sum <- round(emp_cor_sum, 3)
emp_cor_sum[is.na(emp_cor_sum)] <- ""
kable(emp_cor_sum, 
      digits = 3,
      format = "latex",align = 'r', 
      booktabs = TRUE, 
      escape = FALSE,
      linesep = "") %>% 
  column_spec(column = -1,
              width = "2cm") %>% 
  cat(file = "output/tables/michigan-empirical-correlation.tex")

survey_covs_sum <- round(survey_covs_sum, 3)
survey_covs_sum[is.na(survey_covs_sum)] <- ""
kable(survey_covs_sum, 
      digits = 3,
      format = "latex",align = 'r', 
      booktabs = TRUE, 
      escape = FALSE,
      linesep = "") %>% 
  column_spec(column = -1,
              width = "2cm") %>% 
  cat(file = "output/tables/michigan-modeled-covariances.tex")


survey_cor_sum <- round(survey_cor_sum, 3)
survey_cor_sum[is.na(survey_cor_sum)] <- ""
kable(survey_cor_sum, 
      digits = 3,
      format = "latex",align = 'r', 
      booktabs = TRUE, 
      escape = FALSE,
      linesep = "") %>% 
  column_spec(column = -1,
              width = "2cm") %>% 
  cat(file = "output/tables/michigan-modeled-correlation.tex")





# Another approach: correlation of estimated intercept + logit shift
# modeled_intercepts <- ranef(mvmod, groups = "countyfips", summary = FALSE)$countyfips
# 
# emp_covs <- list()
# for (i in seq_along(draw_ids)) {
#   this_draw_model <- modeled_intercepts[draw_ids[i], , c("gov_Intercept", "sos_Intercept", "michprop3_Intercept")] %>%
#     as.data.frame() %>%
#     rownames_to_column("countyfips") %>%
#     pivot_longer(-countyfips, names_to = "outcome", values_to = "model") %>%
#     mutate(outcome = str_remove(outcome, "_Intercept"))
# 
#   this_draw_calib <- calib_3$logit_shifts %>%
#     filter(.draw == draw_ids[i]) %>%
#     select(-.draw) %>%
#     pivot_longer(-countyfips, names_to = "outcome", values_to = "shift") %>%
#     mutate(outcome = str_remove(outcome, "_shift"))
# 
#   tmp <- inner_join(this_draw_model, this_draw_calib, by = c("countyfips", "outcome"))
#   tmp <- tmp %>%
#     mutate(realized = model + shift) %>%
#     select(countyfips, outcome, realized) %>%
#     pivot_wider(names_from = outcome, values_from = realized)
#   tmp <- cov(tmp %>% select(-countyfips))
#   emp_covs[[i]] <- tmp
# }
# emp_covs <- simplify2array(emp_covs)
# emp_covs <- apply(emp_covs, c(1, 2), mean)
# 
# 
# colnames(emp_covs) <- c("Governor", "Secretary of State", "Abortion Prop.")
# rownames(emp_covs) <- c("Governor", "Secretary of State", "Abortion Prop.")
# 
# 
# colnames(model_based_cov) <- c("Governor", "Secretary of State", "Abortion Prop.")
# rownames(model_based_cov) <- c("Governor", "Secretary of State", "Abortion Prop.")


## Convert to correlation matrix and save to table ------------------------

cor_mat <- apply(survey_covs, 1, cov2cor, simplify = FALSE)
cor_mat <- simplify2array(cor_mat)
cor_mat <- apply(cor_mat, c(1, 2), mean)
if (!lqmm::is.positive.definite(cor_mat)) {
  cor_mat <- lqmm::make.positive.definite(cor_mat)
}
# order <- outcomes[which(outcomes != "bidenapprirt")]
order <- outcomes
cor_mat <- round(cor_mat[order, order], 2)



# Recodes
recodes <- data.frame(var = str_remove_all(outcomes, "_"),
                      label = fct(c("Governor", "Secretary of State", "Abortion Prop.",
                                    "Biden Legitimate", "Biden Approval", "Fair Elections",
                                    "Democratic PID", "Independent PID", "Republican PID")),
                      type = c(rep("Election", 3), rep("Opinions", length(outcomes) - 3)))


rownames(cor_mat) <- recodes$label[match(rownames(cor_mat), recodes$var)]
colnames(cor_mat) <- recodes$label[match(colnames(cor_mat), recodes$var)]
cor_out <- cor_mat
cor_out[upper.tri(cor_out)] <- NA
cor_out <- kable(cor_out, 
                 format = "latex",align = 'r', 
                 booktabs = TRUE, 
                 escape = FALSE,
                 linesep = "") %>% 
  column_spec(column = -1,
              width = "2cm") %>% 
  str_replace_all("NA", "") 
cat(cor_out, file = "output/tables/michigan-model-correlations.tex")





# Analyze change to Party ID ----------------------------------------------

## Look at "raw" survey PID, uncalibrated estimates, and calibrated estimates.
pid <- out_sum %>% 
  filter(outcome %in% c("dempid", "indpid", "reppid")) %>% 
  mutate(calib2 = as.character(as.numeric(calib)))

svy_pid <- sm_mi %>%
  select(countyfips, dem_pid, ind_pid, rep_pid, state_pooled_wt_4) %>% 
  group_by(countyfips) %>%
  summarise(n = n(),
            across(c(dem_pid, ind_pid, rep_pid),
                   list(mean = mean,
                        mean_se = ~ SEMdeff(.x, w = state_pooled_wt_4))))
svy_pid <- svy_pid %>% 
  pivot_longer(-c(countyfips, n)) %>% 
  mutate(outcome = substr(name, 1, 7) %>% str_remove("_"),
         est = ifelse(grepl("se", name), "sd", "mean")) %>% 
  select(-name) %>% 
  pivot_wider(values_from = value,
              names_from = est) %>% 
  mutate(calib2 = "Raw")

pid_comb <- bind_rows(svy_pid, pid) %>% 
  select(countyfips, outcome, calib2, mean, n) %>% 
  pivot_wider(values_from = c(mean, n), 
              names_from = calib2) %>% 
  mutate(across(starts_with("mean"), ~ .x * 100))

gp <- GGally::ggpairs(pid_comb %>% filter(outcome == "dempid"), 
                      columns = c("mean_Raw", "mean_1", "mean_4"), 
                      columnLabels = c("Raw Survey", "Uncalibrated\nMRP", "Calibrated\nMRP")) + 
  labs(#title = "Democratic Party ID",
    x = "County Democratic PID Share") +
  theme(panel.grid.major = element_line(), 
        panel.border = element_rect(fill = "transparent"),
        panel.spacing.x = unit(3, "mm"))
ggsave(plot = gp, 
       filename = "output/figures/mi-democratic-pid.pdf", 
       width = 8, height = 6)






message("02-run-michigan.R complete.")
