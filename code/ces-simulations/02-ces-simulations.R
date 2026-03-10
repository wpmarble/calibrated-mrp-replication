
## Show how calibration works across samples
## Two outcomes: spending_infrastructure and enviro_carbon

library(brms)
library(tidyverse)
library(calibratedMRP)
library(kableExtra)
library(future)
library(fixest)
library(texreg)

## Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)
REFIT <- "--refit" %in% args
# N_SIMS: first non-flag argument, or 25 by default
nsims_arg <- setdiff(args, "--refit")
N_SIMS <- if (length(nsims_arg)) as.integer(nsims_arg[1]) else 25

fit_on_pop <- FALSE  # population model not used in paper; extremely slow to fit
run_full_simulation <- N_SIMS > 0

set.seed(82520)

source("code/ces-simulations/00-simulation-functions.R")


# Load data ---------------------------------------------------------------

outcomes <- c("spending_infrastructure", "enviro_carbon", "pres_dem", "pres_rep")
outcomes2 <- gsub("_", "", outcomes)
dat <- readRDS("data/frozen/CES_for_simulation_frozen.rds")

# drop missing data
dat <- drop_na(dat)
cat(prettyNum(nrow(dat), big.mark = ","), file = "output/tables/numbers-in-text/pseudopopulation-n.tex")



# Poststratification table and targets ------------------------------------

ps_table <- dat |> 
  group_by(state, agegrp, race, educ, gender, across(starts_with("st_"))) |> 
  summarise(n = n()) |> 
  ungroup()

targets <- dat |> 
    group_by(state) |> 
    summarise(across(all_of(outcomes), mean)) |> 
    rename_with(\(x) gsub("_", "", x))



# Population correlations ---------------------------------------------------
popcors <- dat |> 
  select(all_of(outcomes)) |> 
  cor()
colnames(popcors) <- rownames(popcors) <- c("Infrastructure", "CO$_2$", "2020 Dem. Vote", "2020 Rep. Vote")


popcors <- round(popcors, 2)
popcors[upper.tri(popcors, diag = TRUE)] <- NA
popcors[is.na(popcors)] <- ""
kable(popcors, 
      digits = 3,
      format = "latex",align = 'r', 
      booktabs = TRUE, 
      escape = FALSE,
      linesep = "") %>% 
  column_spec(column = -1,
              width = "2cm") %>% 
  cat(file = "output/tables/ces-population-correlations.tex")



## Run Regression
co2_basic <- feols(enviro_carbon ~ pres_dem + pres_rep, dat)
co2_covs <- feols(enviro_carbon ~ pres_dem + pres_rep + agegrp + race + gender + educ | state, dat)

sp_basic <- feols(spending_infrastructure ~ pres_dem + pres_rep, dat)
sp_covs <- feols(spending_infrastructure ~ pres_dem + pres_rep + agegrp + race + gender + educ | state, dat)




texreg(
  l = list(co2_basic, co2_covs, sp_basic, sp_covs),

  # # Rename coefficients, uncomment to show all covs
  custom.coef.map = list(
    "pres_dem" = "2020 Vote: Biden",
    "pres_rep" = "2020 Vote: Trump",
    "agegrp30-39" = "Age: 30-39",
    "agegrp40-49" = "Age: 40-49",
    "agegrp50-64" = "Age: 50-64",
    "agegrp65-74" = "Age: 65-74",
    "agegrp75+" = "Age: 75+",
    "raceblack" = "Race: Black",
    "racehispanic" = "Race: Hispanic",
    "raceother" = "Race: Other",
    "racewhite" = "Race: White",
    "gendermale" = "Gender: Male",
    "educsome college" = "Educ: Some College",
    "educcollege" = "Educ: College",
    "educpostgrad" = "Educ: Postgrad"
  ),

  # Add checkmarks to clarify which FEs/covs are included
  custom.gof.rows = list(
    "State FEs" = rep(c("", "\\checkmark"), 2)
  ),
  custom.gof.names = c(
    "Num. obs." = "$N$",
    "R$^2$ (full model)" = "$R^2$",
    "Num. groups: state" = "$N$ States"
  ),


  # Model numbers and multicolumn headers
  custom.model.names = paste0("(", 1:4, ")"),
  custom.header = list("\\makecell{Allow EPA to\\\\Regulate CO$_2$}" = 1:2, 
                       "\\makecell{Increase\\\\Infrastructure Spending}" = 3:4),

  # significance codes
  stars = c(0.01, 0.05, 0.1),

  # statistics to include
  include.rsquared = TRUE,
  include.proj.stats = FALSE,
  include.adjrs = FALSE,
  include.loglik = FALSE,
  include.aic = FALSE,
  include.bic = FALSE,
  include.rmse = FALSE,

  # latex options
  table = FALSE,
  custom.note = "",
  booktabs = TRUE,
  dcolumn = TRUE,
  use.packages = FALSE
) %>%
  format_texreg_N_rows() |> 
  cat(file = "output/tables/ces-sim-full-regression.tex")



# Define model formula and priors ----------------------------------------

form <- bf(
  mvbind(spending_infrastructure, enviro_carbon, pres_dem, pres_rep) ~ 

    # individual-level predictors
    gender + as.integer(agegrp) + (1 | age | agegrp) + race + educ +
    (1 | raceeduc | race:educ) + (1 | agerace | race:agegrp) +
    
    # state-level predictors
    st_pct_nonwhite_z + st_pct_college_z + st_med_inc_z + st_demvs_2020_z +
    (1 | c | state) 
)

# normal(0,5) priors for coefs, default priors otherwise
gp <- get_prior(formula = form, data = dat, family = bernoulli())
mvpriors <- gp |>
  dplyr::mutate(prior = ifelse(class == "b" & prior == "", "normal(0,5)", prior)) 








# Fit model on population ------------------------------------------------

if (fit_on_pop) {
  pop_mod <- brm(
    formula = form,
    data = dat,
    prior = mvpriors,
    family = bernoulli,
    backend = "cmdstanr",
    chains = 4, 
    cores = 4, 
    iter = 800,
    adapt_delta = .97,
    max_treedepth = 12
  )

  saveRDS(pop_mod, file = "data/frozen/ces-population-model_frozen.rds")

  # extract re covariances
  re_covs <- get_re_covariance(pop_mod, group = "state")
  re_covs <- apply(re_covs, c(2,3), mean)
  re_cor <- cov2cor(re_covs)
  re_cor <- round(re_cor, 2)
  rownames(re_cor) <- colnames(re_cor) <- c("Infrastructure", "CO$_2$", "Trump Vote", "Biden Vote")
  re_cor[upper.tri(re_cor, diag = TRUE)] <- NA
  re_cor[is.na(re_cor)] <- ""
  kable(re_cor, 
        digits = 3,
        format = "latex",align = 'r', 
        booktabs = TRUE, 
        escape = FALSE,
        linesep = "") %>% 
    column_spec(column = -1,
                width = "2cm") %>% 
    cat(file = "output/tables/ces-population-re-correlations.tex")
}
if (!run_full_simulation) {
  message("Skipping simulation (N_SIMS = 0). Using frozen results.")
  # Skip to end — results loaded in 03-summarize-ces-sims.R
  q("no")
}

# Generate samples -------------------------------------------------------

# sample size and differential nonresponse
par_n = c(
  500,
  1e3,
  1e4
) 
par_dnr <- list(
  "No DNR" = c(0, 0),
  "Moderate DNR" = c(0.1, 0.1),
  "Extreme DNR" = c(1, 1)
)

nsims_inner <- N_SIMS # number of samples per sampling config
cat(nsims_inner, file = "output/tables/numbers-in-text/nsimsinner.tex")

total_sims <- length(par_n) * length(par_dnr) * nsims_inner
sim_n <- 1
simres <- list()
for (n in par_n) {
  for (i_dnr in seq_len(length(par_dnr))) {
    samps <- replicate(
      n = nsims_inner,
      expr = generate_sample(
        population = dat,
        n = n,
        dnr_outcomes = c("spending_infrastructure", "enviro_carbon"),
        dnr_beta = par_dnr[[i_dnr]]
      ),
      simplify = FALSE
    )
    
    simres_inner <- list()
    for (i_samps in seq_len(nsims_inner)) {
      rlang::inform(sprintf("N = %s; i_dnr = %s; i_samp = %s", n, i_dnr, i_samps))
      rlang::inform(sprintf("Simulation %s of %s", sim_n, total_sims))
      sim_n <- sim_n + 1

      # fit model
      mod <- brm(
        formula = form,
        data = samps[[i_samps]],
        prior = mvpriors,
        family = bernoulli,
        backend = "cmdstanr",
        chains = 4,
        iter = 800,
        cores = 4,
        adapt_delta = .97,
        max_treedepth = 12
      )
  
      # generate uncalibrated estimates
      cell_uncalib <- generate_cell_estimates(
        mod,
        ps_table = ps_table,
        outcomes = outcomes2,
        summarize = TRUE
      )
      state_est_uncalib <- poststratify(
        cell_uncalib,
        outcomes = all_of(outcomes2),
        ses = FALSE,
        weight = n,
        by = state
      ) |> 
        select(-n)
      state_est_uncalib$type = "Uncalibrated"

      # generate calibrated estimates
      cell_calib <- calibrate_mrp(
        mod,
        ps_table = ps_table,
        weight = "n",
        geography = "state",
        targets = targets |> select(-any_of(outcomes2[c(1,2)])),
        method = "plugin",
        posterior_summary = TRUE,
        keep_uncalib = FALSE
      )
      cell_calib$results <- cell_calib$results |> 
        rename_with(\(x) gsub("_calib$|_calib_mean$", "", x))
      state_est_calib <- poststratify(
        cell_calib$results,
        outcomes = outcomes2,
        ses = FALSE,
        weight = n,
        by = state
      ) |> 
        select(-n)
      state_est_calib$type <- "Calibrated"
      
      # summarize results
      state_est <- bind_rows(state_est_uncalib, state_est_calib)
      state_est <- left_join(state_est, targets, by = "state", suffix = c("_est", "_true"))
      state_est <- state_est |> 
        pivot_longer(cols = starts_with(outcomes2)) |> 
        mutate(tmp = ifelse(grepl("_est$", name), "est", "true"),
               outcome = gsub("(_est|_true)$", "", name)) |> 
        select(-name) |> 
        pivot_wider(names_from = tmp, values_from = value) |> 
        filter(outcome %in% outcomes2[c(1, 2)]) |> 
        mutate(error = est - true)
      
      errors <- state_est |> 
        summarise(across(error, 
          list(mae = \(x) mean(abs(x)),
                rmse = \(x) sqrt(mean(x^2)))),
          .by = c(type, outcome)) |> 
          rename_with(\(x) gsub("^error_", "", x))
      errors$.i_innersim <- i_samps
      simres_inner[[i_samps]] <- errors
    }
    simres_inner <- bind_rows(simres_inner)
    simres_inner$DNR <- names(par_dnr)[i_dnr]
    simres_inner$n <- n

    simres <- append(simres, list(simres_inner))
  }
}
saveRDS(simres, file = "data/frozen/ces-simulation-results_frozen.rds")
message("02-ces-simulations.R complete.")

