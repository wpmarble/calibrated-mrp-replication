# install.R
# Install all R packages required for replication.
# Run this script once before running run.sh.
#
# Usage: Rscript install.R

# CRAN packages
cran_pkgs <- c(
  "tidyverse",
  "lubridate",
  "brms",
  "cmdstanr",
  "lme4",
  "bayesplot",
  "tidybayes",
  "ggdist",
  "kableExtra",
  "ggplot2",
  "future",
  "furrr",
  "fixest",
  "texreg",
  "scales",
  "sjlabelled",
  "rio",
  "tidylog",
  "rlang",
  "dataverse",
  "arrow",
  "haven",
  "survey",
  "questionr",
  "lqmm",
  "GGally",
  "remotes"
)

# Install CRAN packages (skip already installed)
installed <- rownames(installed.packages())
to_install <- setdiff(cran_pkgs, installed)
if (length(to_install) > 0) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
}

# Install cmdstan (required backend for brms)
if (!requireNamespace("cmdstanr", quietly = TRUE) ||
    is.null(tryCatch(cmdstanr::cmdstan_path(), error = function(e) NULL))) {
  cmdstanr::install_cmdstan()
}

# Install calibratedMRP from GitHub
remotes::install_github("wpmarble/calibratedMRP")

message("All packages installed successfully.")
