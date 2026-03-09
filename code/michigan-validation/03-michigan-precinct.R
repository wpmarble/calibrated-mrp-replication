# Michigan precinct validation


library(tidyverse)
library(lubridate)
library(brms)
library(bayesplot)
library(tidybayes)
library(furrr)
library(ggdist)
library(kableExtra)
library(calibratedMRP)
plan(multisession, workers = 10)
options(future.globals.maxSize = 3e3 * 1024^2) # mem size in MB - 3gb total

set.seed(19104)


## Parse command-line arguments for refit flag
args <- commandArgs(trailingOnly = TRUE)
REFIT <- "--refit" %in% args

# rerun calibration or just load saved results?
rerun <- REFIT

# test w/ subset of draws?
TEST <- FALSE
if (TEST) {
  rlang::inform(c(i = "just using a subset of draws"))
}


theme_set(theme_classic() + 
            theme(axis.text = element_text(size = 14), 
                  title = element_text(size = 16),
                  strip.text = element_text(size = 16),
                  legend.text = element_text(size = 14)))

source("code/functions.R")
source("code/michigan-validation/01-prep-data-michigan.R")


# subset to data collected within 3 weeks of the election
sm <- subset(sm, date >= ymd("2022-10-18"))


# Load estimated model from 02-run-michigan.R
mod <- readRDS("data/frozen/michigan-model-fit_frozen.rds")

if (TEST){
  set.seed(11092025)
  draw_ids <- sample(1:ndraws(mod), 100)
} else {
  draw_ids <- 1:ndraws(mod)
}

## Generate Predictions in Poststratification Table ## 
print("generating cell estimates...")
mi_ps <- ps_cty %>% filter(state == "MI")
pred_draws <- generate_cell_estimates(
  mod,
  mi_ps,
  outcomes = c("gov", "sos", "michprop3"),
  summarize = FALSE,
  draw_ids = draw_ids
)

## Extract Correlation of REs ##
print("extracting RE covariance...")
county_intercept_cov <- get_re_covariance(
  mod = mod,
  group = "countyfips",
  tidy = FALSE,
  draw_ids = draw_ids
)




# Load precinct results ---------------------------------------------------
print("loading precinct results...")
prec <- read.csv("data/michigan-precincts/michigan22.csv")
fips <- read.csv("data/census/county-fips.csv") %>% 
  filter(state == "MI") %>% 
  mutate(name = str_remove(name, "County")) %>% 
  mutate(name = trimws(toupper(name))) %>% 
  mutate(name = ifelse(name == "GRAND TRAVERSE", "GD. TRAVERSE", name))
prec <- tidylog::left_join(prec, fips, by = c("County.Name" = "name"))

prec <- prec %>% 
  select(fips, County.Name, City.Town.Name, District.Code, Ward.Number, 
         Precinct, Office.Name, Candidate.Name, Candidate.Party, Votes) %>% 
  group_by(fips, City.Town.Name, District.Code, Ward.Number, Precinct) %>% 
  mutate(prec_id = cur_group_id())

prec <- prec %>% 
  filter(Candidate.Party %in% c("DEM", "REP") | Office.Name == "PROPOSITION 3") %>% 
  group_by(prec_id, Office.Name) %>% 
  mutate(voteshare = Votes / sum(Votes)) %>% 
  filter(Candidate.Name %in% c("GRETCHEN WHITMER",
                               "JOCELYN BENSON",
                               "YES")) %>% 
  ungroup()

# make wide -- only keep precinct and dem/yes voteshare
prec <- prec %>% 
  mutate(tmp = case_when(
    Office.Name == "GOVERNOR" ~ "gov",
    Office.Name == "SECRETARY OF STATE" ~ "sos",
    Office.Name == "PROPOSITION 3" ~ "michprop3"
  )) %>% 
  select(fips, prec_id, tmp, voteshare) %>% 
  pivot_wider(names_from = "tmp",
              values_from = "voteshare")


prec_res <- prec




# Run calibration ----------------------------------------------------
print("running calibration...")
ps_table_start <- mi_ps %>% 
  select(countyfips, est_prop)

precincts <- prec %>% 
  distinct(fips, prec_id) %>% 
  rename(countyfips = fips)


if (rerun){
  out <- future_map(seq_along(draw_ids), 
                    .progress = TRUE,
                    .f = ~ {
    draw <- .x
    
    ### add predictions to PS table
    preds <- as_tibble(pred_draws[draw,,])
    ps_table <- bind_cols(ps_table_start, preds)
    
    preds <- poststratify(ps_table, 
                          outcomes = c("gov", "sos", "michprop3"),
                          weight = est_prop, 
                          by = countyfips)
    
    # Join to precincts
    preds_prec <- left_join(
      precincts,
      preds %>% 
        mutate(countyfips = as.numeric(countyfips)), 
      by = "countyfips")
    
    
    shifts <- logit_shift(ps_table = preds_prec, 
                          outcomes = "gov", 
                          geography = prec_id,
                          weight = n, 
                          targets = prec_res)
    
    shifts <- logit_shift_aux(shifts, 
                              shift_var = "gov", 
                              cov = county_intercept_cov[draw,,] )
    
    res <- calibrate_preds(ps_table = preds_prec, 
                           shifts = shifts,
                           preds = c("gov", "sos", "michprop3"),
                           geography = prec_id)
    
    res$.draw <- draw
    res
  })
  out_og <- out
  saveRDS(out_og, "data/frozen/michigan-precinct-RR_frozen.rds")
} else {
  out <- readRDS("data/frozen/michigan-precinct-RR_frozen.rds")
}
out <- bind_rows(out)




# Tidy output -------------------------------------------------------------

print("summarizing posterior...")
recodes <- data.frame(var = c("gov", "sos", "michprop3"),
                      label = fct(c("Governor", "Secretary of State", "Abortion Prop.")))




## Summarize posterior 
out_sum <- out %>% 
  select(-ends_with("shift")) |> 
  group_by(prec_id) %>% 
  summarise(across(-c(.draw, countyfips), 
                   list(mean = mean, 
                        median = median,
                        q5 = ~ quantile(.x, .05),
                        q95 = ~ quantile(.x, .95),
                        sd = sd
                   )) )

# Make long
out_sum <- out_sum %>% 
  pivot_longer(c(ends_with("mean"),
                 ends_with("median"),
                 ends_with("q5"),
                 ends_with("q95"),
                 ends_with("sd"))) %>% 
  mutate(
    stat = stringr::str_match(name, "_([^_]+)$")[, 2],
    calib = case_when(
      grepl("calib", name) ~ "Calibrated to Gov.",
      TRUE ~ "Uncalibrated"
    ),
    outcome = str_match(name, "^(.*?)_")[, 2]
  ) %>% 
  select(-name) %>% 
  pivot_wider(names_from = "stat",
              values_from = "value") %>% 
  filter(outcome != "n")
out_sum <- left_join(out_sum, recodes, by = c("outcome" = "var"))



out_sum <- left_join(out_sum, 
                     prec_res %>% 
                       rename(countyfips = fips) %>% 
                       rename_with(~ paste0(.x, "_true"), 
                                   -c(countyfips, prec_id)) %>% 
                       select(prec_id,
                              starts_with("gov"), 
                              starts_with("sos"),
                              starts_with("michprop3")) %>% 
                       pivot_longer(-prec_id,
                                    values_to = "true") %>% 
                       mutate(race = case_when(
                         grepl("gov", name) ~ "gov",
                         grepl("sos", name) ~ "sos",
                         grepl("michprop3", name) ~ "michprop3")) %>% 
                       select(-name), 
                     by = c("prec_id", "outcome" = "race"))

out_sum <- out_sum %>% 
  mutate(error = mean - true)



## Get errors in wide format
errors <- out_sum %>% 
  select(prec_id, calib, outcome, label, error) %>% 
  # mutate(error = abs(error)) %>% 
  pivot_wider(values_from = "error",
              names_from = "calib")




# Analyze and plot results ------------------------------------------------
print("analyzing results...")


## Summarize results
ggplot(out_sum)  + 
  aes(x = true, y = mean) +
  geom_abline(slope = 1, intercept = 0) + 
  geom_point(size = .5) + 
  facet_grid(fct_relevel(calib, c("Uncalibrated", "Calibrated to Gov.")) ~ label) + 
  labs(x = "True Vote Share",
       y = "Modeled Vote Share") + 
  theme(panel.spacing = unit(.5, "cm"))
ggsave("output/figures/mi-precinct-elections.pdf",width=8,height=5.5)





# Plot errors
ggplot(out_sum %>% 
         filter(sd > .001)) +
  aes(x = error, fill = calib) + 
  geom_vline(xintercept = 0, lty =2) + 
  geom_density(alpha = .5) +
  facet_wrap(~label, drop = TRUE, scales = "free_y") + 
  scale_y_continuous() + 
  scale_fill_discrete(name = "Calibration\nTarget") + 
  # theme_classic() + 
  theme(legend.position = "bottom",
        panel.spacing = unit(5, "mm")) + 
  labs(x = "Precinct-Level Error", y = "Density")
ggsave("output/figures/mi-precinct-election-error-density.pdf", width=8, height=4)






# Save errors to table ----------------------------------------------------


# save errors to table
error_tab <- out_sum %>% 
  mutate(calib = ifelse(calib == "Calibrated to Gov.", "Governor", calib)) %>% 
  mutate(calib = fct_relevel(calib, "Uncalibrated")) %>% 
  group_by(label, calib) %>% 
  summarise(across(error, 
                   list(`Mean Signed Error` = ~ round(mean(.x, na.rm=TRUE)*100, 1), 
                        `Mean Abs. Error` = ~ round(mean(abs(.x), na.rm=TRUE)*100, 1),
                        `Root Mean Sq. Error` = ~round(sqrt(mean((100*.x)^2, na.rm=TRUE)), 1),
                        `Minimum`  = ~ round(min(.x, na.rm=TRUE)*100, 1), 
                        `Maximum`  = ~ round(max(.x, na.rm=TRUE)*100, 1)),
                   .names = "{.fn}")) %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ format(.x, nsmall = 1))) %>% 
  filter(!is.na(calib))

error_tab %>% 
  mutate(across(`Mean Signed Error`:Maximum, ~ {
    case_when(as.character(label) == as.character(calib) ~ "$-$",
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
  row_spec(c(2,4), extra_latex_after = "\\midrule") %>% 
  cat(file = "output/tables/michigan-precinct-calibration-error-reduction.tex")






# Little files for numbers in text ----------------------------------------

# RMSE for SoS and prop3
error_tab %>% 
  filter(label == "Secretary of State",
         calib == "Uncalibrated") %>% 
  pluck("Root Mean Sq. Error") %>% 
  trimws() %>% 
  {sprintf("$%s$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/sos-rmse-precinct-uncalib.txt")

error_tab %>% 
  filter(label == "Secretary of State",
         calib == "Governor") %>% 
  pluck("Root Mean Sq. Error") %>% 
  trimws() %>% 
  {sprintf("$%s$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/sos-rmse-precinct-calib.txt")


error_tab %>% 
  filter(label == "Abortion Prop.",
         calib == "Uncalibrated") %>% 
  pluck("Root Mean Sq. Error") %>% 
  trimws() %>% 
  {sprintf("$%s$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/prop3-rmse-precinct-uncalib.txt")

error_tab %>% 
  filter(label == "Abortion Prop.",
         calib == "Governor") %>% 
  pluck("Root Mean Sq. Error") %>% 
  trimws() %>% 
  {sprintf("$%s$", .)} %>% 
  cat(file = "output/tables/numbers-in-text/prop3-rmse-precinct-calib.txt")










