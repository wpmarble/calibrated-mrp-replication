#!/bin/bash
# Smoke test for replication package
# Tests that all path changes and frozen-load logic work correctly.
# Does NOT re-estimate any models or run simulations.
# Expected runtime: ~10-20 minutes
set -e

echo "=== Replication Package Smoke Test ==="
echo "Started: $(date)"
echo ""

# Create output directories
mkdir -p output/figures/model-diagnostics output/tables/numbers-in-text

# ---- Michigan pipeline (all using frozen fits) ----

echo "[1/7] 01-prep-data-michigan.R ..."
Rscript code/michigan-validation/01-prep-data-michigan.R

echo "[2/7] 02-run-michigan.R (frozen fits) ..."
Rscript code/michigan-validation/02-run-michigan.R

echo "[3/7] 03-michigan-precinct.R (frozen fits) ..."
Rscript code/michigan-validation/03-michigan-precinct.R

echo "[4/7] 04-michigan-diagnostics.R ..."
Rscript code/michigan-validation/04-michigan-diagnostics.R

echo "[5/7] 05-prior-sensitivity.R (frozen fits) ..."
Rscript code/michigan-validation/05-prior-sensitivity.R

# Skip 06-plugin-vs-bayes.R (always refits a brms model)

# ---- CES pipeline (frozen results only) ----

echo "[6/7] 02-ces-simulations.R (tables only, no sims) ..."
Rscript code/ces-simulations/02-ces-simulations.R 0

echo "[7/7] 03-summarize-ces-sims.R ..."
Rscript code/ces-simulations/03-summarize-ces-sims.R

# ---- Verify key outputs exist ----
echo ""
echo "=== Checking outputs ==="
FAIL=0
check_file() {
  if [ -f "$1" ]; then
    echo "  OK: $1"
  else
    echo "  MISSING: $1"
    FAIL=1
  fi
}

# Main text figures
check_file output/figures/mi-elections.pdf
check_file output/figures/mi-elections-error-reduction.pdf
check_file output/figures/mi-election-error-density.pdf
check_file output/figures/mi-calib-adjustment-by-gov-results.pdf
check_file output/figures/mi-calib-adjustment-by-gov-error.pdf
check_file output/figures/mi-democratic-pid.pdf

# Main text tables
check_file output/tables/michigan-calibration-error-reduction.tex
check_file output/tables/michigan-model-correlations.tex

# Appendix outputs
check_file output/figures/model-diagnostics/mi-rhat-hist.pdf
check_file output/figures/model-diagnostics/mi-trace-lp.pdf
check_file output/figures/model-diagnostics/mi-trace-cty-intercept.pdf
check_file output/figures/mrsp-comparison.pdf
check_file output/figures/error-density-mrsp-comparison.pdf
check_file output/tables/mrsp-error-reduction.tex
check_file output/figures/michigan-prior-sensitivity-rmse.pdf
check_file output/figures/michigan-prior-sensitivity-correlation.pdf
check_file output/figures/mi-precinct-elections.pdf
check_file output/figures/mi-precinct-election-error-density.pdf
check_file output/tables/michigan-precinct-calibration-error-reduction.tex

# CES outputs
check_file output/tables/ces-population-correlations.tex
check_file output/tables/ces-sim-full-regression.tex
check_file output/tables/ces-simulation-rmse-reduction.tex
check_file output/figures/ces-simulation-results.pdf
check_file output/tables/numbers-in-text/pseudopopulation-n.tex

echo ""
if [ $FAIL -eq 0 ]; then
  echo "=== ALL CHECKS PASSED ==="
else
  echo "=== SOME CHECKS FAILED ==="
  exit 1
fi
echo "Finished: $(date)"
