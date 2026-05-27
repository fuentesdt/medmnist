#!/usr/bin/env bash
#
# run_sweep.sh
#
# Launch a MATLAB training sweep on the GPU machine.
#
# Usage:
#   ./tools/run_sweep.sh <sweep_id>
#
# Behaviour:
#   - If no run_NNN.m configs exist yet, generates them from sweep.yaml,
#     commits, and pushes so results are tied to a clean, traceable SHA.
#   - Refuses to start if the git working tree has uncommitted tracked changes.
#   - Skips any run whose result JSON already exists (idempotent re-runs).
#   - Continues past individual run failures; reports a summary at the end.
#   - Calls tools.aggregate_results at the end to build summary.csv.
#   - Exits non-zero if any run failed.
#
# Requires: matlab in PATH, git remote accessible for push.

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
    echo "Error: $YAML_PATH not found. Is the sweep committed and the repo pulled?" >&2
    exit 1
fi

# --- Dirty-tree guard --------------------------------------------------------
# Uncommitted tracked changes mean the result SHA won't match the code that ran.

if ! git diff --quiet HEAD; then
    echo "Error: git working tree has uncommitted changes. Commit or stash first." >&2
    git status --short >&2
    exit 1
fi

# --- Generate run configs if needed ------------------------------------------
# If sweep.yaml is present but per-run configs haven't been expanded yet,
# generate them here, commit, and push before training starts.

mapfile -t RUN_PATHS < <(find "$SWEEP_DIR" -name 'run_[0-9][0-9][0-9].m' | sort)

if [[ ${#RUN_PATHS[@]} -eq 0 ]]; then
    echo "No run configs found — generating from $YAML_PATH ..."
    if ! matlab -batch "tools.generate_sweep('$SWEEP_DIR')"; then
        echo "Error: tools.generate_sweep failed." >&2
        exit 1
    fi
    git add "$SWEEP_DIR/"
    git commit -m "expand: $SWEEP_ID"
    git push
    mapfile -t RUN_PATHS < <(find "$SWEEP_DIR" -name 'run_[0-9][0-9][0-9].m' | sort)
    if [[ ${#RUN_PATHS[@]} -eq 0 ]]; then
        echo "Error: generate_sweep produced no run configs in $SWEEP_DIR." >&2
        exit 1
    fi
fi

# --- Locate dataset and compute provenance -----------------------------------

DATASET=$(grep '^dataset:' "$YAML_PATH" | sed 's/^dataset:[[:space:]]*//' | tr -d '[:space:]')
if [[ -z "$DATASET" ]]; then
    echo "Error: cannot parse 'dataset' from $YAML_PATH" >&2
    exit 1
fi

readonly RESULT_DIR="results/$DATASET/$SWEEP_ID"
GIT_SHA=$(git rev-parse --short HEAD)

printf 'Sweep:   %s\n' "$SWEEP_ID"
printf 'Dataset: %s\n' "$DATASET"
printf 'SHA:     %s\n' "$GIT_SHA"
printf 'Runs:    %d\n' "${#RUN_PATHS[@]}"
echo

# --- Run loop ----------------------------------------------------------------

passed=0
failed=0
skipped=0

for run_path in "${RUN_PATHS[@]}"; do
    run_file=$(basename "$run_path")
    run_name="${run_file%.m}"
    result_json="$RESULT_DIR/$run_name.json"

    if [[ -f "$result_json" ]]; then
        printf '  [skip] %s — result exists\n' "$run_name"
        skipped=$((skipped + 1))
        continue
    fi

    printf '  [run ] %s\n' "$run_name"

    if matlab -batch "train('$SWEEP_DIR/$run_file')"; then
        printf '  [ok  ] %s\n' "$run_name"
        passed=$((passed + 1))
    else
        printf '  [fail] %s\n' "$run_name" >&2
        failed=$((failed + 1))
    fi
done

echo
printf 'Done: %d ok, %d failed, %d skipped.\n' "$passed" "$failed" "$skipped"

# --- Aggregate ---------------------------------------------------------------
# Build summary.csv from result JSONs. Soft failure: warns but does not abort.

if [[ "$passed" -gt 0 || "$skipped" -gt 0 ]]; then
    echo
    printf 'Aggregating results to %s/summary.csv ...\n' "$RESULT_DIR"
    if ! matlab -batch "tools.aggregate_results('$RESULT_DIR')"; then
        printf 'Warning: aggregation failed — run tools.aggregate_results manually.\n' >&2
    fi
fi

# Non-zero exit if any run failed so the caller (CI, shell script) can detect it.
[[ "$failed" -eq 0 ]]
