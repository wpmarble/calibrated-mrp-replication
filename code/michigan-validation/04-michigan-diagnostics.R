## Michigan model diagnostics

library(tidyverse)
library(brms)
library(bayesplot)
library(tidybayes)

mod <- readRDS("data/frozen/michigan-model-fit_frozen.rds")



# Traceplots --------------------------------------------------------------

## log probability
mcmc_trace(mod, "lp__") + 
  labs(x = "Iteration",
       y = "log probability")
ggsave(
  "output/figures/model-diagnostics/mi-trace-lp.pdf",
  width = 6,
  height = 4
)


## county intercepts
vars <- get_variables(mod)
ctyint <- grep("sd_countyfips", vars, value = TRUE)
nms <- ctyint %>% 
  str_remove_all("sd_countyfips__|_Intercept$") %>% 
  map(~ case_when(
    .x == "gov" ~ "Governor",
    .x == "sos" ~ "Sec. of State",
    .x == "michprop3" ~ "Abortion Proposition",
    .x == "bidenlegitimateirt" ~ "Biden Legitimate Pres.",
    .x == "bidenapprirt" ~ "Biden Approval",
    .x == "electionfairirt" ~ "Elections Usually Fair",
    .x == "dempid" ~ "Democratic PID",
    .x == "indpid" ~ "Independent PID",
    .x == "reppid" ~ "Republican PID"
  )) %>% 
  unlist()
names(nms) <- ctyint

outcome_labeller <- ggplot2::as_labeller(nms)

mcmc_trace(mod, pars = ctyint, 
           facet_args = list(labeller = outcome_labeller)
          ) + 
  theme(strip.text = element_text(size = 12)) + 
  scale_x_continuous(breaks = seq(0, 600, 200)) + 
  labs(x = "Iteration",
       y = "Value") 
ggsave(
  "output/figures/model-diagnostics/mi-trace-cty-intercept.pdf",
  width = 8,
  height = 8
)           




# R-hats ------------------------------------------------------------------

rhats <- brms::rhat(mod)
rhats <- data.frame(rhat = rhats, 
                    par = names(rhats))
ggplot(rhats) + 
  aes(x = rhat) + 
  geom_histogram(alpha = .3, colour = "black") + 
  geom_vline(aes(xintercept = mean(rhat), lty = "mean r-hat")) +
  geom_vline(aes(xintercept = median(rhat), lty = "median r-hat")) +
  scale_linetype_discrete(name = NULL) + 
  labs(x = "R-hat value") +
  theme(legend.position = c(.8,.8))
ggsave(
  "output/figures/model-diagnostics/mi-rhat-hist.pdf",
  width = 6,
  height = 4
)
