#!/bin/bash
# =============================================================================
# Replication script for:
#   Marble & Clinton (forthcoming, Political Analysis)
#   "Improving Small-Area Estimates of Public Opinion by Calibrating to
#    Known Population Quantities"
#
# Requirements: R 4.3+, cmdstan, calibratedMRP package, ~16GB RAM
# Run install.R first to install all dependencies.
#
# Estimated runtime:
#   - With frozen model fits (default): ~30 minutes
#   - Full re-estimation (--refit): ~4-8 hours
#   - Full simulations (--nsims 25): ~several days on top of above
#
# Usage:
#   ./run.sh                       # Use frozen fits, skip simulations
#   ./run.sh --refit               # Re-estimate all Bayesian models
#   ./run.sh --nsims 25            # Run CES simulations (25 reps/config)
#   ./run.sh --refit --nsims 25    # Full replication from scratch
# =============================================================================

set -e  # Exit on error

# Parse arguments
REFIT_FLAG=""
NSIMS=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --refit)
      REFIT_FLAG="--refit"
      shift
      ;;
    --nsims)
      NSIMS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./run.sh [--refit] [--nsims N]"
      exit 1
      ;;
  esac
done

echo "============================================="
echo "Replication: Marble & Clinton (Pol. Analysis)"
echo "============================================="
echo "Options:"
echo "  --refit:  ${REFIT_FLAG:-not set (using frozen model fits)}"
echo "  --nsims:  ${NSIMS} (0 = use frozen simulation results)"
echo "============================================="
echo ""

# Create output directories
mkdir -p output/figures/model-diagnostics output/tables/numbers-in-text log

# Start log
LOG="log/replication-log.txt"
echo "Replication started: $(date)" > "$LOG"
echo "Options: refit=${REFIT_FLAG:-no} nsims=${NSIMS}" >> "$LOG"
echo "" >> "$LOG"

# ---- Download CES data (needed for CES simulation pipeline) ----
echo "[1/9] Downloading CES data (if needed)..."
Rscript data-raw/download-ces-data.R 2>&1 | tee -a "$LOG"

# ---- Michigan validation pipeline ----
echo "[2/9] Preparing Michigan data..."
Rscript code/michigan-validation/01-prep-data-michigan.R 2>&1 | tee -a "$LOG"

echo "[3/9] Running Michigan validation (main analysis)..."
Rscript code/michigan-validation/02-run-michigan.R $REFIT_FLAG 2>&1 | tee -a "$LOG"

echo "[4/9] Running Michigan precinct validation..."
Rscript code/michigan-validation/03-michigan-precinct.R $REFIT_FLAG 2>&1 | tee -a "$LOG"

echo "[5/9] Running Michigan model diagnostics..."
Rscript code/michigan-validation/04-michigan-diagnostics.R 2>&1 | tee -a "$LOG"

echo "[6/9] Running prior sensitivity analysis..."
Rscript code/michigan-validation/05-prior-sensitivity.R $REFIT_FLAG 2>&1 | tee -a "$LOG"

echo "[7/9] Running plugin vs. Bayes comparison (always refits model)..."
Rscript code/michigan-validation/06-plugin-vs-bayes.R 2>&1 | tee -a "$LOG"

# ---- CES simulation pipeline ----
echo "[8/9] Preparing CES data..."
Rscript code/ces-simulations/01-prep-ces.R 2>&1 | tee -a "$LOG"

if [ "$NSIMS" -gt 0 ]; then
  echo "[8b/9] Running CES simulations (N_SIMS=$NSIMS)..."
  Rscript code/ces-simulations/02-ces-simulations.R $REFIT_FLAG $NSIMS 2>&1 | tee -a "$LOG"
else
  echo "[8b/9] Skipping CES simulations (using frozen results)."
fi

echo "[9/9] Summarizing CES simulation results..."
Rscript code/ces-simulations/03-summarize-ces-sims.R 2>&1 | tee -a "$LOG"

echo ""
echo "============================================="
echo "Replication complete: $(date)"
echo "============================================="
echo "Replication complete: $(date)" >> "$LOG"
