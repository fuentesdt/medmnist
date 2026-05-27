function train(configPath)
%TRAIN Single entry point: load config, train, evaluate, write JSON result.
%
%   train('configs/nodulemnist3d.m')
%   train('configs/sweeps/001_nodule_smoke/run_001.m')
%
%   Run from the repo root. Writes one JSON to results/<dataset>/<sweep>/<run>.json.
%   Skips silently if the result file already exists (idempotent re-runs).

    arguments
        configPath (1,1) string
    end

    setupPaths();

    % 1. Load and validate config -----------------------------------------
    cfg = loadConfig(configPath);
    validateConfig(cfg);

    % 2. Infer sweep/run identity from config path ------------------------
    [sweepId, runId] = inferRunIdentity(configPath);

    % 3. Guard: skip completed runs (idempotent) --------------------------
    % runId already encodes the sweep prefix (e.g. "001_smoke/run_001")
    resultPath = fullfile('results', cfg.dataset, strrep(runId, '/', filesep) + ".json");
    if isfile(resultPath)
        fprintf('[%s] Already complete — skipping.\n', runId);
        return
    end

    % 4. Reproducibility --------------------------------------------------
    rng(cfg.seed, 'twister');

    % 5. Data -------------------------------------------------------------
    fprintf('[%s] Loading data from %s ...\n', runId, cfg.dataPath);
    data   = loadData(cfg);
    YTrain = encodeLabels(cfg, data.YTrain);
    YVal   = encodeLabels(cfg, data.YVal);
    YTest  = encodeLabels(cfg, data.YTest);

    nTrain        = size(data.XTrain, 5);
    itersPerEpoch = max(1, floor(nTrain / cfg.batchSize));

    % 6. Network ----------------------------------------------------------
    fprintf('[%s] Building model (%s) ...\n', runId, cfg.architecture);
    model = buildModel(cfg);

    % 7. Datastores -------------------------------------------------------
    augFcn  = buildAugmentation(cfg);
    trainDs = makeDatastore(data.XTrain, YTrain, augFcn);
    valDs   = makeDatastore(data.XVal,   YVal,   []);

    % 8. Training options -------------------------------------------------
    opts = buildTrainingOptions(cfg, valDs, itersPerEpoch);

    % 9. Train ------------------------------------------------------------
    fprintf('[%s] Training: %d epochs, lr=%.0e, batch=%d, aug=%s ...\n', ...
            runId, cfg.epochs, cfg.lr, cfg.batchSize, cfg.augmentation);
    t0 = tic;
    [net, info] = trainnet(trainDs, model.layers, model.lossFcn, opts);
    trainSec = toc(t0);

    % 10. Save checkpoint (gitignored; path recorded in JSON) -------------
    modelPath = fullfile('checkpoints', strrep(runId, '/', filesep) + ".mat");
    if ~isfolder(fileparts(modelPath)), mkdir(fileparts(modelPath)); end
    save(modelPath, 'net');

    % 11. Evaluate on test split ------------------------------------------
    % Explicit dlarray batching — R2025b misinterprets the batch dim for raw
    % 5D numeric arrays in minibatchpredict.  reshape(·,[], B)' normalises
    % whatever shape predict returns (e.g. [nC B] or [1 1 1 nC B]) to [B nC].
    fprintf('[%s] Evaluating on test split ...\n', runId);
    N_test = size(data.XTest, ndims(data.XTest));
    scores = zeros(N_test, cfg.numClasses, 'single');
    for bStart = 1 : cfg.batchSize : N_test
        bEnd  = min(bStart + cfg.batchSize - 1, N_test);
        B     = bEnd - bStart + 1;
        Xb    = dlarray(single(data.XTest(:,:,:,:, bStart:bEnd)), 'SSSCB');
        out   = predict(net, Xb);
        batch = gather(single(extractdata(out)));
        scores(bStart:bEnd, :) = reshape(batch, [], B)';   % → [B, numClasses]
    end
    metrics = computeMetrics(cfg, scores, YTest);

    % 12. Write result JSON -----------------------------------------------
    writeRunResult(cfg, sweepId, runId, resultPath, info, metrics, trainSec);

    fprintf('[%s] Done.  test_acc=%.3f  test_auc=%.3f  time=%ds\n', ...
            runId, metrics.test_acc, metrics.test_auc, round(trainSec));
end


% -------------------------------------------------------------------------
% Local helpers
% -------------------------------------------------------------------------

function setupPaths()
    root = fileparts(mfilename('fullpath'));
    addpath(fullfile(root, 'configs'));
    addpath(genpath(fullfile(root, 'src')));
end


function cfg = loadConfig(configPath)
    % Temporarily add the config file's directory to the MATLAB path,
    % then call the config function by name.
    [dir, funcName] = fileparts(configPath);
    dir = string(fullfile(dir));
    alreadyOnPath = any(strcmp(dir, strsplit(path, pathsep)));
    if ~alreadyOnPath
        addpath(dir);
        cleanup = onCleanup(@() rmpath(dir));  %#ok<NASGU>
    end
    cfg = feval(funcName);
end


function [sweepId, runId] = inferRunIdentity(configPath)
    % configs/sweeps/001_smoke/run_001.m  → sweepId="001_smoke",  runId="001_smoke/run_001"
    % configs/nodulemnist3d.m             → sweepId="adhoc",       runId="adhoc/nodulemnist3d"
    [dir, name] = fileparts(configPath);
    [parentDir, leaf] = fileparts(dir);
    [~, grandLeaf]    = fileparts(parentDir);

    if grandLeaf == "sweeps" || leaf == "sweeps"
        sweepId = leaf;
        runId   = sweepId + "/" + name;
    else
        sweepId = "adhoc";
        runId   = "adhoc/" + name;
    end
end


function ds = makeDatastore(X, Y, augFcn)
    % Combine image and label array datastores; optionally apply augmentation.
    % X: [H W D C N],  Y: [N 1] categorical,  augFcn: [] or function handle.
    imgDs = arrayDatastore(X, 'IterationDimension', ndims(X));
    lblDs = arrayDatastore(Y, 'IterationDimension', 1);
    ds    = combine(imgDs, lblDs);
    if ~isempty(augFcn)
        ds = transform(ds, @(s) {augFcn(s{1}), s{2}});
    end
end
