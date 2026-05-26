# Kickoff prompt for Claude Code

Paste this as your first message in a fresh Claude Code session, after you've placed CLAUDE.md, the existing scripts (`download_medmnist3d.sh`, `summarize_medmnist3d.m`), and an empty git repo in the working directory.

---

I'm starting a MATLAB 3D image classification baseline project. Read CLAUDE.md first — it has the full design context, benchmark targets, repo layout, dispatch points, results contract, and the two-machine git-only workflow. Don't skim it; the architectural decisions there are load-bearing for everything you'll do.

You're on the dev machine. There is no GPU here and no MATLAB execution available. You can only write code, generate configs, and analyze results that come back via git from the GPU machine. Don't try to run MATLAB to verify things — write the code, lint it by reading it carefully, and trust the GPU-side runs to surface real bugs.

## What already exists

- `CLAUDE.md` — project context. Authoritative.
- `tools/download_medmnist3d.sh` — bash script that downloads the six 3D `.npz` files from Zenodo with MD5 verification. Already works.
- `tools/summarize_medmnist3d.m` — MATLAB script that loads each `.npz` via the Python bridge (`py.numpy.load`) and prints per-split statistics + chance floor. Already works.

Both of these are reference implementations of the patterns the project uses (Python bridge for `.npz`, structured output, idempotent re-runs). Read them before writing new code so your style matches.

## What I want you to build, in this order

Do not skip ahead. Each step has an acceptance check; do not move to the next step until the current one passes its check.

### Step 1: Repo scaffolding and .gitignore

Create the directory structure from the "Repo layout" section of CLAUDE.md. Add a `.gitignore` that excludes `data/medmnist3d/`, `*.mat`, `checkpoints/`, MATLAB scratch files, and a `CLAUDE.local.md` for local-only notes.

Move the two existing scripts into `tools/` if they aren't there already. Create empty `src/{data,model,train,eval,utils}/` and `tests/` directories with `.gitkeep` files so git tracks them.

**Acceptance check:** `tree -L 2` shows the layout from CLAUDE.md. `git status` shows the scaffold ready to commit but no data files staged.

### Step 2: The base config for one dataset

Write `configs/nodulemnist3d.m`. It should be a function that returns a struct with every field the rest of the pipeline will need: `dataset`, `dataPath`, `numClasses`, `inputSize`, `lr`, `batchSize`, `epochs`, `optimizer`, `augmentation`, `seed`, `architecture`. Pick sensible defaults that you'd expect to roughly reproduce the ~0.84 ACC target from CLAUDE.md.

Also write `src/utils/validateConfig.m` that checks every required field is present, types are right, and values are in plausible ranges. Fail fast with informative messages.

**Acceptance check:** `cfg = nodulemnist3d(); validateConfig(cfg);` would succeed if MATLAB were available. The config has no fields that aren't actually used downstream.

### Step 3: The five dispatch points

Write the five dispatch functions listed in CLAUDE.md's "Dispatch points" section into `src/data/`, `src/model/`. For this phase only `nodulemnist3d` is implemented in each — but write them as factories that take `cfg` and dispatch on `cfg.dataset` or `cfg.architecture` so adding the other five MedMNIST3D datasets later is one new branch each.

Especially: `loadData(cfg)` should use the Python-bridge pattern from `summarize_medmnist3d.m`. Don't reinvent it.

**Acceptance check:** Each function has a single responsibility, a clear interface, and no per-dataset logic anywhere else in the codebase.

### Step 4: train.m

The single entry point. Takes a config path. Loads the config, validates it, seeds RNG, calls the dispatch functions to assemble the model and data, runs training, evaluates on the test split, writes the JSON result file in the format specified in CLAUDE.md's "results contract" section.

The JSON writer is `src/train/writeRunResult.m`. It should hash the resolved config (use `DataHash` from File Exchange or implement a simple `jsonencode + sha256`), capture the git SHA via `system('git rev-parse --short HEAD')`, and write to `results/<dataset>/<sweep_id>/<run_id>.json`. For non-sweep runs (a one-off `train('configs/nodulemnist3d.m')`), use `sweep_id = "adhoc"`.

**Acceptance check:** Reading `train.m` top to bottom tells you the full lifecycle of a run. No buried side effects. Every field in the documented JSON schema is populated.

### Step 5: Sweep generation

Write `tools/generate_sweep.m`. Takes a sweep folder path, reads `sweep.yaml`, expands the grid, writes `run_NNN.m` files (each is a function returning a config struct based on the base config with the swept fields overridden). Respects `constraints.max_runs` — refuse to generate beyond it.

Use MATLAB's built-in `yamlread` if available (R2024a+); otherwise pull in `yaml-matlab` from File Exchange and document the dependency in CLAUDE.md under "Coding conventions."

Then create one example sweep at `configs/sweeps/001_nodule_smoke/sweep.yaml` — a tiny 4-run sweep (2 learning rates × 2 seeds) for end-to-end testing before committing to real sweeps.

**Acceptance check:** `tools.generate_sweep('configs/sweeps/001_nodule_smoke')` would produce 4 `run_NNN.m` files. Each is a valid config. Re-running the generator is idempotent.

### Step 6: GPU-side launcher and committer

Write `tools/run_sweep.sh` and `tools/commit_results.sh` exactly per the design in CLAUDE.md. The launcher must:
- Refuse to run on a dirty git tree.
- Skip already-complete runs (idempotent).
- Continue past individual run failures.
- Aggregate to `summary.csv` at the end.

The committer must run the PHI guard grep even though we're in the public-data phase — we want it tested before it matters.

**Acceptance check:** Reading both scripts, you can predict their behavior on the dirty-tree, partial-success, and PHI-leak cases without running them.

### Step 7: Aggregation and analysis

Write `tools/aggregate_results.m` (builds `summary.csv` from per-run JSONs) and `tools/analyze_sweep.m` (loads the summary, prints top-N runs, identifies which hyperparameters mattered).

For `analyze_sweep.m`, "which hyperparameters mattered" can be as simple as: for each swept dimension, report the spread in test_acc when grouping by that dimension. Don't overbuild this — it's diagnostic, not science.

**Acceptance check:** Given a synthetic `summary.csv` with 4 runs you write by hand, `analyze_sweep` produces a readable summary.

### Step 8: README and the first real commit

Write a `README.md` that points new contributors at CLAUDE.md, explains the dev/GPU split, and gives the literal command sequence for the first run:

```
# on dev machine
./tools/download_medmnist3d.sh
# (manually copy data/medmnist3d to GPU machine — git won't carry it)
git add -A && git commit -m "initial scaffold" && git push

# on GPU machine
git pull
matlab -batch "summarize_medmnist3d('data/medmnist3d')"
matlab -batch "train('configs/nodulemnist3d.m')"
```

Commit everything. This is the baseline before any sweeps.

**Acceptance check:** A collaborator could clone the repo, read README.md + CLAUDE.md, and know exactly what to do.

## Working style

- Match the conventions already established in `summarize_medmnist3d.m`: `arguments` blocks, `onCleanup` for resource handling, defensive checks with informative error IDs.
- Don't add dependencies casually. `npy-matlab` was rejected in favor of the Python bridge for a reason — re-read CLAUDE.md if you're tempted to add something.
- Prefer plain MATLAB structs and JSON over MAT files for anything that crosses the git boundary. MAT files are opaque and binary; JSON diffs in PRs.
- When you find yourself wanting to write a 200-line file, pause and check whether two 80-line files would be clearer. Especially in `src/`.
- If you hit a design question that isn't answered by CLAUDE.md, ask me. Don't decide silently. Update CLAUDE.md after the decision so the next session has it.
- When you finish each step, give me the acceptance-check result and wait before moving on. I want to review the structure before we commit to building on top of it.

## What success looks like at the end of this session

- Eight commits, one per step.
- The repo can be cloned, scaffolded, and pointed at the GPU machine.
- A single `train('configs/nodulemnist3d.m')` would produce a valid JSON result if MATLAB were available.
- A 4-run smoke sweep is generated and ready to push.
- CLAUDE.md reflects any decisions made during implementation.

Start with Step 1. Report back when its acceptance check passes.
