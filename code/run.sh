#!/usr/bin/env bash
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
#   - Default (re-estimate models): ~4-8 hours
#   - With frozen model fits (--no-refit): ~30 minutes
#   - With CES simulations (--nsims 25): adds several days
#
# Usage:
#   ./run.sh                       # Re-estimate all Bayesian models
#   ./run.sh --no-refit            # Use frozen model fits (quick verification)
#   ./run.sh --nsims 25            # Also run CES simulations (25 reps/config)
#   ./run.sh --no-refit --nsims 25 # Frozen fits + run simulations
# =============================================================================

set -eo pipefail  # Exit on error, including pipeline failures

# Set working directory to repo root (parent of code/, where this script lives)
cd "$(dirname "$0")"/..

# --- Code Ocean compatibility ---
# CO mounts data at /data and expects output in /results.
# Create symlinks so existing relative paths work unchanged.
if [ -d "/data" ] && [ -d "/results" ]; then
  ln -sf /data data
  ln -sf /results output
  mkdir -p /results/log
  ln -sf /results/log log
fi

# Parse arguments
NO_REFIT_FLAG=""
NSIMS=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-refit)
      NO_REFIT_FLAG="--no-refit"
      shift
      ;;
    --nsims)
      NSIMS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./run.sh [--no-refit] [--nsims N]"
      exit 1
      ;;
  esac
done

echo "============================================="
echo "Replication: Marble & Clinton (Pol. Analysis)"
echo "============================================="
echo "Options:"
echo "  --no-refit: ${NO_REFIT_FLAG:-not set (re-estimating all models)}"
echo "  --nsims:    ${NSIMS} (0 = use frozen simulation results)"
echo "============================================="
echo ""

# Create output directories
mkdir -p output/figures/model-diagnostics output/tables/numbers-in-text log

# Start log
LOG="log/replication-log.txt"
> "$LOG"  # truncate log on each run
log() { echo "$@" | tee -a "$LOG"; }

log "Replication started: $(date)"
if [ -n "$NO_REFIT_FLAG" ]; then REFIT_STATUS="no (using frozen fits)"; else REFIT_STATUS="yes"; fi
log "Options: refit=${REFIT_STATUS} nsims=${NSIMS}"
log ""

# ---- Log session info ----
log "[0/9] Logging session info... $(date)"
Rscript code/session-info.R 2>&1 | tee -a "$LOG"

# ---- Download CES data (needed for CES simulation pipeline) ----
log "[1/9] Downloading CES data (if needed)... $(date)"
Rscript code/download-ces-data.R 2>&1 | tee -a "$LOG"

# ---- Michigan validation pipeline ----
log "[2/9] Preparing Michigan data... $(date)"
Rscript code/michigan-validation/01-prep-data-michigan.R 2>&1 | tee -a "$LOG"

log "[3/9] Running Michigan validation (main analysis)... $(date)"
Rscript code/michigan-validation/02-run-michigan.R $NO_REFIT_FLAG 2>&1 | tee -a "$LOG"

log "[4/9] Running Michigan precinct validation... $(date)"
Rscript code/michigan-validation/03-michigan-precinct.R $NO_REFIT_FLAG 2>&1 | tee -a "$LOG"

log "[5/9] Running Michigan model diagnostics... $(date)"
Rscript code/michigan-validation/04-michigan-diagnostics.R 2>&1 | tee -a "$LOG"

log "[6/9] Running prior sensitivity analysis... $(date)"
Rscript code/michigan-validation/05-prior-sensitivity.R $NO_REFIT_FLAG 2>&1 | tee -a "$LOG"

log "[7/9] Running plugin vs. Bayes comparison (always refits)... $(date)"
Rscript code/michigan-validation/06-plugin-vs-bayes.R 2>&1 | tee -a "$LOG"

# ---- CES simulation pipeline ----
log "[8/9] Preparing CES data... $(date)"
Rscript code/ces-simulations/01-prep-ces.R 2>&1 | tee -a "$LOG"

if [ "$NSIMS" -gt 0 ]; then
  log "[8b/9] Running CES simulations (N_SIMS=$NSIMS)... $(date)"
  Rscript code/ces-simulations/02-ces-simulations.R $NO_REFIT_FLAG $NSIMS 2>&1 | tee -a "$LOG"
else
  log "[8b/9] Skipping CES simulations (using frozen results)."
fi

log "[9/9] Summarizing CES simulation results... $(date)"
Rscript code/ces-simulations/03-summarize-ces-sims.R 2>&1 | tee -a "$LOG"

log ""
log "============================================="
log "Replication complete: $(date)"
log "============================================="
