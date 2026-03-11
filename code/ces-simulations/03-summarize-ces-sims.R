
library(ggplot2)
library(dplyr)
library(forcats)
library(tidyr)
library(kableExtra)


theme_set(theme_classic() + 
            theme(axis.text = element_text(size = 14), 
                  title = element_text(size = 16),
                  strip.text = element_text(size = 16),
                  legend.text = element_text(size = 14)))

res <- readRDS("data/frozen/ces-simulation-results_frozen.rds")
res <- bind_rows(res)

res <- res |> 
  mutate(outcome = case_when(
    outcome == "spendinginfrastructure" ~ "Infrastructure Spending",
    outcome == "envirocarbon" ~ "Regulate CO$_2$"
  ))


res_wide <- res |>
  pivot_wider(values_from = c(mae, rmse), names_from = "type")
res_wide <- res_wide |> 
  mutate(rmse_change = (rmse_Calibrated -  rmse_Uncalibrated) / rmse_Uncalibrated,
         mae_change = (mae_Calibrated -  mae_Uncalibrated) / mae_Uncalibrated)


rmse_summary <- res_wide |>
  summarise(
    rmse_uncalib = mean(rmse_Uncalibrated),
    rmse_calib = mean(rmse_Calibrated),
    rmse_change = mean(rmse_change),
    .by = c(outcome, DNR, n)
  )

rmse_summary |>
  mutate(n = prettyNum(n, big.mark = ","), 
         rmse_uncalib = sprintf("%.3f", rmse_uncalib),
         rmse_calib = sprintf("%.3f", rmse_calib),
         rmse_change = sprintf("$%.1f$", rmse_change * 100)) |> 
  kable(
    col.names = c(
      "Outcome",
      "\\makecell{Differential\\\\Nonresponse}",
      "Sample $N$",
      "\\makecell{Average RMSE\\\\(Uncalibrated)}",
      "\\makecell{Average RMSE\\\\(Calibrated)}",
      "\\makecell{Average Percent\\\\Change in RMSE}"
    ),
    linesep = "",
    digits = 3,
    format = "latex",
    align = 'r',
    booktabs = TRUE,
    escape = FALSE
  ) |>
  row_spec(which(seq_len(nrow(rmse_summary)) %% 2 == 0),
           extra_latex_after = "\\addlinespace") |>
  cat(file = "output/tables/ces-simulation-rmse-reduction.tex")






ggplot(res) + 
  aes(y = rmse, x = factor(n), colour = type) + 
  geom_violin() + 
  facet_grid(DNR ~ outcome)




ggplot(res) + 
  aes(y = rmse, x = n, colour = DNR) + 
  geom_point(position = position_jitter(log(1.1))) + 
  scale_x_log10() + 
  facet_grid(type ~ outcome)


ggplot(
  res_wide |> mutate(outcome = gsub("CO$_2$", "CO2", outcome, fixed = TRUE))
) +
  aes(x = factor(n), y = rmse_change) +
  geom_hline(yintercept = 0, lty = 3) +
  geom_point(position = position_jitter(.2)) +
  facet_grid(
    fct_relevel(DNR, c("No DNR", "Moderate DNR", "Extreme DNR")) ~
    fct_relevel(outcome, c("Regulate CO2", "Infrastructure Spending"))
  ) + 
  scale_y_continuous(labels = scales::percent_format()) + 
  labs(x = "Sample Size", y = "Change in RMSE") + 
  theme(panel.spacing.y = unit(1, "cm"))
ggsave("output/figures/ces-simulation-results.pdf",width=7, height=7)
