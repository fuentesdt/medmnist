# CLAUDE.md

Project context for Claude Code. Keep this file short, high-signal, and current. Prune anything that no longer matches the code.

## Project

MATLAB baseline 3D image classifier, evaluated against published benchmarks on **MedMNIST3D** datasets. The baseline is adapted from the MathWorks "Create Simple Deep Learning Neural Network for Classification" example, swapped to 3D layers (`image3dInputLayer`, `convolution3dLayer`, `maxPooling3dLayer`).

**Why this project exists:** an earlier attempt to predict cervical cancer recurrence from ADC maps (N=70, single-modality MRI) produced a null result after extensive hyperparameter sweeps and architecture changes. We don't yet know whether that was a code/pipeline problem or genuine absence of signal. This project is the positive control: prove the pipeline can reproduce published accuracy on standardized 3D benchmarks. If it can, the cervical null result is informative; if it can't, we have a code bug to find.

**Current phase:** public data only (MedMNIST3D). The institutional kidney/cervical work is deferred until the public benchmark is reproducing literature numbers.

## Architecture decision: single `train.m` + per-dataset configs

Chose this over per-dataset scripts because:
- A baseline must hold the method constant while data varies — configs encode this structurally.
- Reproducibility: config hash + git SHA fully identifies a run.
- One auditable training path will matter when PHI data enters scope later.

Per-dataset divergence (loss head, input layer, datastore) lives in small **dispatch points** in shared code, not in `if cfg.dataset == "..."` branches inside `train.m`.

## Benchmark targets (MedMNIST3D, 28³)

These are the numbers we're trying to hit. Source: Yang et al., *Scientific Data* 2023, Table 4 (ResNet-50 with 3D convolutions). Treat as approximate — within 0.02 ACC is "reproduced," materially below is a problem to debug.

| Dataset | Task | Classes | Target ACC | Target AUC | Notes |
|---|---|---|---|---|---|
| **organmnist3d** | Organ ID | 11 | ~0.95 | ~0.997 | Sanity check. If this fails, code is broken. Run first. |
| **nodulemnist3d** | Benign vs malignant lung nodule | 2 | ~0.84 | ~0.87 | Closest analog to the cervical recurrence task. The informative benchmark. |
| **adrenalmnist3d** | Normal vs adrenal mass | 2 | ~0.79 | ~0.83 | Modest signal, realistic ceiling. |
| **vesselmnist3d** | Aneurysm vs healthy vessel | 2 | ~0.88 | ~0.87 | |
| **fracturemnist3d** | Fracture classification | 3 | ~0.51 | ~0.71 | Hard task; low ceiling. |
| **synapsemnist3d** | Synapse classification | 2 | ~0.73 | ~0.82 | |

Chance floor (majority class on test split) is computed by `summarize_medmnist3d.m` and stored in each result JSON. A run that doesn't clear chance is a failed run, not a real result.

## Repo layout

```
.
├── train.m                         # single entry point: train(configPath)
├── configs/
│   ├── nodulemnist3d.m             # base configs (one per dataset)
│   ├── organmnist3d.m
│   ├── ...
│   └── sweeps/
│       └── <NNN>_<name>/
│           ├── sweep.yaml          # human/Claude-authored sweep definition
│           └── run_NNN.m           # generated per-run configs (committed)
├── results/
│   └── <dataset>/<sweep_id>/
│       ├── run_NNN.json            # one JSON per run (committed)
│       └── summary.csv             # aggregated table (committed)
├── src/
│   ├── data/                       # npz loader, label encoder, preprocessing
│   ├── model/                      # layer builders, head builders
│   ├── train/                      # training loop, options builder, JSON writer
│   ├── eval/                       # metrics, chance floor, AUROC
│   └── utils/                      # config hashing, logging, path guards
├── tools/
│   ├── generate_sweep.m            # dev side: expand sweep.yaml → run_NNN.m
│   ├── run_sweep.sh                # GPU side: launcher (idempotent)
│   ├── commit_results.sh           # GPU side: stage, commit, push (PHI guard)
│   ├── aggregate_results.m         # build summary.csv from run_NNN.json
│   ├── analyze_sweep.m             # dev side: top-N, hparam importance
│   └── summarize_medmnist3d.m      # split statistics + chance floor
├── tests/
├── data/medmnist3d/                # gitignored — downloaded npz files
└── CLAUDE.md
```

## Dispatch points (the only places per-dataset logic lives)

1. **`buildInputLayer(cfg)`** — currently `image3dInputLayer([28 28 28 1])` for all MedMNIST3D. Will diverge when 64³ variant or real data enters.
2. **`buildHead(cfg)`** — softmax + crossentropy for all current datasets (all single-label). Multi-label sigmoid+BCE deferred.
3. **`loadData(cfg)`** — currently `loadMedMNIST3D(npzPath)` via Python bridge (`py.numpy.load`). Returns in-memory arrays; the 28³ files fit in RAM with room to spare.
4. **`buildAugmentation(cfg)`** — modality-appropriate. No horizontal flip if laterality matters; no intensity inversion for CT.
5. **`encodeLabels(cfg, raw)`** — single-label categorical for now.

If a 6th dispatch point appears, pause and reconsider whether the single-script design still fits.

## Workflow: two machines, git as the only bus

The dev machine runs Claude Code but has no GPU. The GPU machine runs MATLAB+CUDA but has no Claude Code. No SSH between them. **Git is the only channel.**

```
[Dev: Claude Code] --commit/push--> [git remote] <--pull-- [GPU machine]
                                         ^                       |
                                         +--- push results ------+
```

The loop:
1. Claude generates `configs/sweeps/NNN_name/sweep.yaml` + per-run `.m` files. Commits and pushes.
2. On GPU machine: `git pull && ./tools/run_sweep.sh NNN_name && ./tools/commit_results.sh NNN_name`.
3. Claude pulls, reads `results/<dataset>/NNN_name/summary.csv` and the per-run JSONs, analyzes, designs the next sweep.

Inviolable rules of the loop:
- **Configs are committed *before* runs.** Every result is tied to a known git SHA. `run_sweep.sh` refuses to run on a dirty tree.
- **Re-runs are idempotent.** If `run_NNN.json` exists with `status: complete`, the run is skipped. Crashed runs are retried by re-launching the sweep.
- **One commit per sweep on the results side**, not one per run. Keeps history readable.
- **Model weights are gitignored.** They stay on the GPU machine. The JSON records `model_path_on_training_machine` for human reference only. If a checkpoint needs to come back to the dev machine, that's an out-of-band copy.

## The results contract

The thing that makes Claude Code productive on returning results is that they arrive *structured*, not as console output or screenshots. Every run writes one JSON file:

```json
{
  "run_id": "001_nodule_lr/run_017",
  "sweep_id": "001_nodule_lr",
  "git_sha": "abc1234",
  "config_hash": "f8e9d2c1",
  "timestamp_utc": "2026-05-26T14:30:22Z",
  "config": { "dataset": "nodulemnist3d", "lr": 3e-4, "batch_size": 32,
              "augmentation": "flip_rotate", "epochs": 50, "seed": 1337,
              "architecture": "baseline_3d_v1" },
  "results": { "best_val_acc": 0.834, "best_val_epoch": 37,
               "test_acc": 0.821, "test_auc": 0.879,
               "test_acc_per_class": [0.85, 0.79],
               "chance_floor": 0.65, "train_time_sec": 412 },
  "training_curves": { "epochs": [...], "train_loss": [...],
                       "val_loss": [...], "val_acc": [...] },
  "env": { "matlab_version": "R2024a", "gpu": "...", "host": "..." },
  "status": "complete",
  "model_path_on_training_machine": "/local/checkpoints/001/run_017_best.mat"
}
```

`tools/aggregate_results.m` produces `summary.csv` with one row per run, columns flattened — that's what Claude reads first to triage a sweep.

## Sweep definition format

YAML, not MATLAB. Humans and Claude both edit these often; MATLAB code is for runtime.

```yaml
sweep_id: 001_nodule_lr
dataset: nodulemnist3d
base_config: configs/nodulemnist3d.m
description: |
  First sweep — vary LR and augmentation while holding architecture fixed.
  Target: reach published ResNet-50 baseline (~0.84 ACC, ~0.87 AUC).

grid:
  lr: [1e-4, 3e-4, 1e-3]
  augmentation: [none, flip, flip_rotate]
  batch_size: [16, 32]
  seed: [42, 1337, 2024]

constraints:
  max_runs: 100
  max_train_minutes: 30
```

`tools/generate_sweep.m` expands the grid into individual `run_NNN.m` config files.

## Coding conventions

- MATLAB R2023b or later (`trainnet`, not `trainNetwork`).
- One function per file in `src/`. File name matches function name.
- Configs are MATLAB structs returned from a function (`cfg = nodulemnist3d()`). Validation in code via `validateConfig(cfg)`; fail fast with clear messages.
- All randomness goes through `rng(cfg.seed)` at the top of `train.m`. Seed is logged.
- Every run writes to `results/<dataset>/<sweep_id>/run_NNN.json`. Never overwrite.
- Use `arguments` blocks for function signatures.
- `npy-matlab` is *not* a dependency — we use the Python bridge (`py.numpy.load`) for `.npz` files. Requires a configured `pyenv` with NumPy installed.

## Commands

```matlab
% Single training run
train('configs/nodulemnist3d.m')

% Generate per-run configs for a sweep (run on dev machine)
tools.generate_sweep('configs/sweeps/001_nodule_lr')

% Summarize raw npz splits (run once after downloading)
summarize_medmnist3d('data/medmnist3d')

% Aggregate JSONs into summary.csv
tools.aggregate_results('results/nodulemnist3d/001_nodule_lr')

% Analyze a completed sweep
tools.analyze_sweep('results/nodulemnist3d/001_nodule_lr')
```

```bash
# GPU machine
./tools/run_sweep.sh 001_nodule_lr
./tools/commit_results.sh 001_nodule_lr
```

## Definition of done for the public-data phase

- `train.m` runs end-to-end on every MedMNIST3D config without code changes between them.
- All six datasets reach within 0.02 ACC of the published ResNet-50 baseline on the test split, or have a documented reason they don't (architecture much smaller than ResNet-50, etc.).
- A second run with the same config and seed reproduces metrics within GPU-determinism noise.
- `summary.csv` and per-run JSONs are committed for every sweep that ran to completion.
- The sweep → analyze → next-sweep loop has run end-to-end at least three times without manual intervention beyond the two-command GPU launch.

When all of the above hold, the pipeline is trusted enough to point at the cervical recurrence data and have a meaningful answer about whether the null result is real.

## Out of scope (this phase)

- Cervical recurrence data, kidney data, any institutional/PHI data.
- 2D datasets (CheXpert, etc.). 3D is what we're testing.
- 64³ MedMNIST+ variant — 28³ matches the canonical published baselines and is enough.
- Cross-dataset transfer, foundation-model fine-tuning, ensembling.
- Inference services, deployment, web UIs.
- Automated sweep dispatch (cron-pull on the GPU side). Manual launch is the discipline that catches "this sweep has 4000 runs, did I mean that?" — defer automation until trust is established.

## Future scope (do not implement yet, but design for)

- **Two-repo split for PHI work.** When kidney/cervical data enters, this repo stays public; a private institutional mirror gets the PHI configs and results. Same code, different result destinations chosen by config.
- **PHI guards in the results writer.** `commit_results.sh` already has a grep-based forbidden-field check. When PHI scope arrives, the JSON writer in `src/train/` needs a positive allowlist of fields, not a denylist.
- **Multi-label head** (sigmoid + BCE) for datasets like CheXpert if 2D ever enters scope.

## Things to ask before assuming

- "Best accuracy" — best on which split? Validation accuracy is for model selection; test accuracy is the reported number. Don't tune on test.
- Sweep size — anything over ~100 runs should be confirmed with the user before generating, since it commits GPU time.
- Architecture changes — the baseline is intentionally small to match the MathWorks example. Changing to ResNet-50 to chase the published number is a real methodological choice, not a default.
