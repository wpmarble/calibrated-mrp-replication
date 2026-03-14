# Prior sensitivity analysis for calibration - Michigan validation
library(tidyverse)
library(lubridate)
library(brms)
library(ggplot2)
library(calibratedMRP)

TEST <- FALSE

## Parse command-line arguments for refit flag
args <- commandArgs(trailingOnly = TRUE)
RERUN <- ! "--no-refit" %in% args

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

if (RERUN) {
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



  ## Sets of priors ---------------------------------------------------------

  gp <- get_prior(formula = form, data = sm_mi, family = bernoulli())


  # priors on beta and correlations
  # betas: improper uniform, normal(0, 5), normal(0, 1)
  # correlations: LKJ(0.25), LKJ(1), LKJ(3), LKJ(10)
  priors <- list(
    
    # LKJ(.25)
    b_unif_lkj0.25 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(0.25)", prior)
      ),
    b_weak_lkj0.25 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(0.25)", prior),
        prior = ifelse(class == "b", "normal(0, 5)", prior)
      ),
    b_strong_lkj0.25 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(0.25)", prior),
        prior = ifelse(class == "b", "normal(0, 1)", prior)
      ),

    # LKJ(1)
    b_unif_lkj1 = gp,
    b_weak_lkj1 = gp |>
      mutate(prior = ifelse(class == "b" & prior == "", "normal(0,5)", prior)),
    b_strong_lkj1 = gp |>
      mutate(prior = ifelse(class == "b" & prior == "", "normal(0,1)", prior)),

    # LKJ(3)
    b_unif_lkj3 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(3)", prior)
      ),
    b_weak_lkj3 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(3)", prior),
        prior = ifelse(class == "b", "normal(0, 5)", prior)
      ),
    b_strong_lkj3 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(3)", prior),
        prior = ifelse(class == "b", "normal(0, 1)", prior)
      ),
    
    # LKJ(10)
    b_unif_lkj10 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(10)", prior)
      ),
    b_weak_lkj10 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(10)", prior),
        prior = ifelse(class == "b", "normal(0, 5)", prior)
      ),
    b_strong_lkj10 = gp |>
      mutate(
        prior = ifelse(class == "cor", "lkj(10)", prior),
        prior = ifelse(class == "b", "normal(0, 1)", prior)
      )
  )


  ## Run model ##
  iter <- if (TEST) 100 else 800
  chains <- 4
  draw_ids <- if (TEST) 1:10 else NULL
  res <- list()
  for (i_prior in seq_len(length(priors))) {
    this_out <- list()
    this_out$desc <- names(priors)[i_prior]
    
    # fit model
    mod <- brm(
      formula = form,
      data = sm_mi,
      family = bernoulli,
      prior = priors[[i_prior]],
      cores = 4,
      chains = chains,
      iter = iter,
      backend = "cmdstanr",
      adapt_delta = .97,
      max_treedepth = 12
    )

    # extract correlation matrix
    covs <- get_re_covariance(mod, group = "countyfips", draw_ids = draw_ids)
    covs <- apply(covs, c(2,3), mean)
    corr <- cov2cor(covs)
    this_out$cor <- corr

    # generate calibrated state-level estimates
    calib_out <- calibrate_mrp(
      model = mod,
      ps_table = mi_ps,
      weight = "est_n",
      geography = "countyfips",
      outcomes = outcomes,
      targets = calib_target %>% select(countyfips, gov),
      method = "plugin",
      draw_ids = draw_ids
    )
    
    this_out$calib <- calib_out
    res[[i_prior]] <- this_out
  }

  saveRDS(res, file = "data/frozen/prior-sensitivity-results_frozen.rds")
} else {
  res <- readRDS("data/frozen/prior-sensitivity-results_frozen.rds")
}




# Analyze results --------------------------------------------------------

# descriptions
sens <- tibble(desc = unlist(map(res, \(x) x$desc))) |>
  mutate(
    b_prior = case_when(
      str_detect(desc, "unif") ~ "Improper Unif.",
      str_detect(desc, "weak") ~ "Normal(0, 5)",
      str_detect(desc, "strong") ~ "Normal(0, 1)"
    ),
    cor_prior = case_when(
      str_detect(desc, "lkj0.25$") ~ "LKJ(0.25)",
      str_detect(desc, "lkj1$") ~ "LKJ(1)",
      str_detect(desc, "lkj3") ~ "LKJ(3)",
      str_detect(desc, "lkj10") ~ "LKJ(10)"
    )
  ) |> 
  mutate(cor_prior = factor(cor_prior, levels = c("LKJ(0.25)", "LKJ(1)", "LKJ(3)", "LKJ(10)")),
         b_prior = factor(b_prior, levels = c("Improper Unif.", "Normal(0, 5)", "Normal(0, 1)"))
         )

# extract correlations
cors <- unlist(map(res, \(x) x$cor[1, 2]))
sens$est_cor <- cors


# calculate RMSE at county level
county_res <- list()
rmse <- map(res, \(x) {
  x$calib$results |>
    poststratify(
      outcomes = michprop3_calib,
      weight = est_n,
      by = "countyfips"
    ) |>
    select(countyfips, est = michprop3_calib) |>
    left_join(
      calib_target %>% select(countyfips, true = michprop3),
      by = "countyfips"
    ) |> 
    mutate(error = est - true) |>
    summarise(rmse = sqrt(mean(error^2))) |> 
    pull("rmse")
})
sens$rmse <- unlist(rmse)

# show RMSE across priors
ggplot(sens) +
  aes(x = cor_prior, y = rmse*100, fill = b_prior) +
  geom_bar(stat = "identity", position = "dodge") +
  scale_fill_grey(name = "Coefficient\nPrior") +
  labs(x = "Correlation Prior", y = "County-Level RMSE") +
  guides(fill = guide_legend(title.position = "top")) 
ggsave("output/figures/michigan-prior-sensitivity-rmse.pdf", width = 8, height = 4)


# show estimated correlation across priors
ggplot(sens) + 
  aes(x = cor_prior, y = est_cor, fill = b_prior) +
  geom_bar(stat = "identity", position = "dodge") +
  scale_fill_grey(name = "Coefficient\nPrior") +
  labs(x = "Correlation Prior", 
 # convert this to graphics display: \hat{Cor}(\alpha_{gov}, \alpha_{michprop3})") +
    y = expression(widehat(Cor)(alpha^gov, alpha^abortion)) ) 
ggsave("output/figures/michigan-prior-sensitivity-correlation.pdf", width = 8, height = 4)
