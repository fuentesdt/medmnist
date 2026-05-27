# medmnist-baseline

MATLAB 3D image classification baseline evaluated against the published
MedMNIST3D benchmarks. This is a **positive control**: prove the pipeline
can reproduce literature numbers on standardised public data before applying
it to institutional medical imaging data.

For full context — architecture decisions, benchmark targets, coding
conventions, the results contract — read [`CLAUDE.md`](CLAUDE.md).

---

## Prerequisites

| Where | What |
|---|---|
| Dev machine | Git, Bash |
| GPU machine | MATLAB R2023b+, CUDA, Python + NumPy + PyYAML (for data loading and sweep generation) |

MATLAB's Python bridge (`pyenv`) must point to an environment that has NumPy
and PyYAML installed. Verify with `pyenv` in MATLAB; configure with
`pyenv('Version', '/path/to/python')`. Install packages with
`pip install numpy pyyaml`.

---

## Running all six datasets

```bash
# ── Dev machine ──────────────────────────────────────────────────────────
# 1. Download all six 28³ datasets (~104 MB total).
./tools/download_medmnist3d.sh

# 2. Copy data/ to the GPU machine out-of-band (USB, scp, shared storage).
#    Git does not carry data — data/medmnist3d/ is gitignored.

# 3. Push so the GPU machine can pull.
git push

# ── GPU machine ──────────────────────────────────────────────────────────
git pull

# 4. Verify data files and print split statistics + chance floors.
matlab -batch "addpath('tools'); summarize_medmnist3d('data/medmnist3d')"

# 5. Train all six datasets (one adhoc run per dataset, 50 epochs each).
for ds in nodulemnist3d organmnist3d adrenalmnist3d vesselmnist3d fracturemnist3d synapsemnist3d; do
    matlab -batch "train('configs/${ds}.m')"
done

# 6. Check results against published targets.
matlab -batch "tools.summarize_benchmarks()"
```

The six base configs use identical hyperparameters (lr=1e-3, batch=32, 50 epochs).
Once all run, `summarize_benchmarks` shows which datasets are reproduced and which
need tuning. Use the sweep workflow below to tune any that fall short.

---

## Sweep workflow

Use sweeps to tune hyperparameters once the base runs are done.
One `sweep.yaml` per dataset; the GPU expands, trains, and aggregates.

```bash
# ── Dev machine ──────────────────────────────────────────────────────────
# Write one sweep.yaml per dataset (no MATLAB needed).
# Convention: configs/sweeps/NNN_<dataset>_<tag>/sweep.yaml
git add configs/sweeps/ && git commit -m "sweeps: round 1" && git push

# ── GPU machine ──────────────────────────────────────────────────────────
git pull

# Define the sweeps to run (edit to match your sweep directory names).
SWEEPS=(
    001_nodule_smoke
    002_organ_lr
    003_adrenal_lr
    004_vessel_lr
    005_fracture_lr
    006_synapse_lr
)

# Each command: generates configs if needed, trains all runs, aggregates.
for sweep in "${SWEEPS[@]}"; do
    ./tools/run_sweep.sh "$sweep"
done

# Commit all results, then push once.
for sweep in "${SWEEPS[@]}"; do
    ./tools/commit_results.sh "$sweep"
done
git push

# ── Dev machine ──────────────────────────────────────────────────────────
git pull

# Cross-dataset scorecard: best result vs. published targets.
matlab -batch "tools.summarize_benchmarks()"

# Drill into a specific sweep.
matlab -batch "tools.analyze_sweep('results/nodulemnist3d/001_nodule_smoke')"
```

`run_sweep.sh` handles the full GPU-side loop: if no `run_NNN.m` files exist
yet it generates them from `sweep.yaml`, commits, and pushes before training
starts. Re-running is idempotent — completed runs are skipped. If a run
crashes, re-run the same command to retry only the failed runs.

---

## Dev / GPU split

The dev machine runs Claude Code but has no GPU. The GPU machine runs
MATLAB + CUDA but has no Claude Code. There is no direct SSH between them.
**Git is the only channel.**

```
[Dev: Claude Code] ──push──▶ [git remote] ◀──pull── [GPU machine]
                                    ▲                      │
                                    └────── push results ──┘
```

The inviolable rule: **configs are committed before runs**. Every result
JSON records the git SHA of the code that produced it. `run_sweep.sh`
generates and commits per-run configs automatically if they don't exist,
then refuses to train on a dirty working tree.

---

## Repo layout (brief)

```
train.m                    # single entry point: train(configPath)
configs/                   # base configs (one per dataset) + sweeps/
src/                       # data, model, train, eval, utils
+tools/                    # MATLAB tools: generate_sweep, aggregate_results, analyze_sweep, summarize_benchmarks
tools/                     # Bash scripts: run_sweep.sh, commit_results.sh, download_medmnist3d.sh
results/<dataset>/<sweep>/ # run_NNN.json + summary.csv (committed)
data/medmnist3d/           # .npz files (gitignored — stays on each machine)
```

See [`CLAUDE.md`](CLAUDE.md) for the full file tree, the results JSON
schema, benchmark targets, and workflow rules.
