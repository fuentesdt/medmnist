#!/usr/bin/env bash
#
# commit_results.sh
#
# Stage and commit completed sweep results from the GPU machine.
#
# Usage:
#   ./tools/commit_results.sh <sweep_id>
#
# Behaviour:
#   - Runs a PHI guard: refuses to commit if any result JSON contains patterns
#     associated with patient-identifiable information.  This guard runs even
#     during the public-data phase so it is tested before PHI data enters scope.
#   - Builds summary.csv if it is missing (e.g. if aggregation was skipped).
#   - Stages all files under results/<dataset>/<sweep_id>/ and commits with a
#     one-line message.  One commit per sweep keeps history readable.
#   - Does NOT push automatically.  Run 'git push' afterwards so the dev
#     machine can pull results and plan the next sweep.
#
# Requires: matlab in PATH (for aggregation fallback).

set -euo pipefail

# --- Argument parsing --------------------------------------------------------

readonly SWEEP_ID="${1:-}"
if [[ -z "$SWEEP_ID" ]]; then
    echo "Usage: $0 <sweep_id>" >&2
    exit 1
fi

readonly SWEEP_DIR="configs/sweeps/$SWEEP_ID"
readonly YAML_PATH="$SWEEP_DIR/sweep.yaml"

if [[ ! -f "$YAML_PATH" ]]; then
    echo "Error: $YAML_PATH not found." >&2
    exit 1
fi

# --- Locate dataset ----------------------------------------------------------

DATASET=$(grep '^dataset:' "$YAML_PATH" | sed 's/^dataset:[[:space:]]*//' | tr -d '[:space:]')
if [[ -z "$DATASET" ]]; then
    echo "Error: cannot parse 'dataset' from $YAML_PATH" >&2
    exit 1
fi

readonly RESULT_DIR="results/$DATASET/$SWEEP_ID"

if [[ ! -d "$RESULT_DIR" ]]; then
    echo "Error: result directory not found: $RESULT_DIR" >&2
    echo "       Run run_sweep.sh first." >&2
    exit 1
fi

# --- Check there is something to commit --------------------------------------

n_json=$(find "$RESULT_DIR" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')
if [[ "$n_json" -eq 0 ]]; then
    echo "Error: no JSON result files in $RESULT_DIR — nothing to commit." >&2
    exit 1
fi

# --- PHI guard ---------------------------------------------------------------
# Abort if any result JSON contains patterns associated with patient data.
# Runs even during the public-data phase to validate the guard before PHI
# data is ever in scope.

phi_patterns=(
    "patient_id"
    "subject_id"
    "mrn"
    "date_of_birth"
    "social_security"
    "birth_date"
)

phi_error=0
for pattern in "${phi_patterns[@]}"; do
    if grep -rqi "$pattern" "$RESULT_DIR/" 2>/dev/null; then
        echo "Error: PHI guard triggered — pattern '$pattern' found in:" >&2
        grep -rli "$pattern" "$RESULT_DIR/" >&2 || true
        phi_error=1
    fi
done

# "phi" matched as a whole word to avoid false positives (e.g. paths with "phi").
if grep -rqiw "phi" "$RESULT_DIR/" 2>/dev/null; then
    echo "Error: PHI guard triggered — word 'phi' found in result files." >&2
    grep -rliw "phi" "$RESULT_DIR/" >&2 || true
    phi_error=1
fi

if [[ "$phi_error" -ne 0 ]]; then
    echo
    echo "Commit aborted. Review the flagged files before proceeding." >&2
    exit 1
fi

# --- Ensure summary.csv exists -----------------------------------------------
# run_sweep.sh normally builds it; rebuild here if it was skipped or failed.

if [[ ! -f "$RESULT_DIR/summary.csv" ]]; then
    printf 'summary.csv missing — building now ...\n'
    if ! matlab -batch "tools.aggregate_results('$RESULT_DIR')"; then
        echo "Warning: aggregation failed; committing without summary.csv." >&2
    fi
fi

# --- Stage and commit --------------------------------------------------------

git add "$RESULT_DIR/"

# Bail out cleanly if there is nothing new to stage (e.g. results already committed).
if git diff --cached --quiet; then
    echo "Nothing new to commit in $RESULT_DIR — already up to date."
    exit 0
fi

TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
readonly TIMESTAMP
git commit -m "results: $SWEEP_ID ($n_json run(s), $TIMESTAMP)"

echo
printf 'Committed %d result(s) for sweep %s.\n' "$n_json" "$SWEEP_ID"
printf 'Run "git push" to share results with the dev machine.\n'
