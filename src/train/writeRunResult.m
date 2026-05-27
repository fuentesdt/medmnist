function writeRunResult(cfg, sweepId, runId, resultPath, info, metrics, trainSec)
%WRITERUNRESULT Write the structured JSON result for one training run.
%
%   writeRunResult(cfg, sweepId, runId, resultPath, info, metrics, trainSec)
%
%   info:      struct returned by trainnet (TrainingLoss, ValidationLoss, etc.)
%   metrics:   struct from computeMetrics (test_acc, test_auc, etc.)
%   trainSec:  wall-clock training time in seconds (from tic/toc)

    arguments
        cfg        (1,1) struct
        sweepId    (1,1) string
        runId      (1,1) string
        resultPath (1,1) string
        info                       % TrainingHistoryData object in R2023b+
        metrics    (1,1) struct
        trainSec   (1,1) double
    end

    if isfile(resultPath)
        error('writeRunResult:resultExists', ...
              'Result already exists; refusing to overwrite: %s', resultPath);
    end

    if ~isfolder(fileparts(resultPath)), mkdir(fileparts(resultPath)); end

    % --- Identity and provenance -------------------------------------------
    [~, sha] = system('git rev-parse --short HEAD');
    sha = strtrim(sha);

    result.run_id        = runId;
    result.sweep_id      = sweepId;
    result.git_sha       = sha;
    result.config_hash   = hashConfig(cfg);
    result.timestamp_utc = string(datetime('now', 'TimeZone', 'UTC', ...
                                   'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
    result.config        = cfg;

    % --- Training results --------------------------------------------------
    curves = extractCurves(info);

    result.results.best_val_acc       = curves.best_val_acc;
    result.results.best_val_epoch     = curves.best_val_epoch;
    result.results.test_acc           = metrics.test_acc;
    result.results.test_auc           = metrics.test_auc;
    result.results.test_acc_per_class = metrics.test_acc_per_class;
    result.results.chance_floor       = metrics.chance_floor;
    result.results.train_time_sec     = round(trainSec);

    result.training_curves = curves.series;

    % --- Environment -------------------------------------------------------
    result.env.matlab_version = version;
    result.env.gpu            = getGpuName();
    result.env.host           = getHostname();

    % --- Bookkeeping -------------------------------------------------------
    result.status = "complete";
    result.model_path_on_training_machine = fullfile(pwd, 'checkpoints', ...
        strrep(runId, '/', filesep) + ".mat");

    % --- Write JSON --------------------------------------------------------
    json = jsonencode(result, 'PrettyPrint', true);
    fid  = fopen(resultPath, 'w', 'n', 'UTF-8');
    if fid == -1
        error('writeRunResult:cannotOpen', 'Cannot open result file for writing: %s', resultPath);
    end
    cleanup = onCleanup(@() fclose(fid));  %#ok<NASGU>
    fwrite(fid, json, 'char');
end


function out = extractCurves(info)
    % Extract training curves from TrainingHistoryData (R2023b+ trainnet)
    % or a legacy plain struct.
    % ValidationLoss / ValidationAccuracy are per-validation-check (≈ per epoch).
    % TrainingLoss is per-iteration.

    if isstruct(info)
        valLoss = safeField(info, 'ValidationLoss',     []);
        valAcc  = safeField(info, 'ValidationAccuracy', []);
        trnLoss = safeField(info, 'TrainingLoss',        []);
    else
        % deep.TrainingInfo (R2023b+): column is "Loss" in both sub-tables.
        try, trnLoss = double(info.TrainingHistory.Loss);     catch, trnLoss = []; end
        try, valLoss = double(info.ValidationHistory.Loss);   catch, valLoss = []; end
        valAcc = [];   % ValidationAccuracy not present in this info format
    end

    % ValidationAccuracy from trainnet is in percent [0,100]; convert to fraction.
    if ~isempty(valAcc)
        valAcc = valAcc / 100;
    end

    nChecks = max(numel(valLoss), numel(valAcc));

    out.series.epochs     = 1:nChecks;
    out.series.val_loss   = double(valLoss(:)');
    out.series.val_acc    = double(valAcc(:)');
    out.series.train_loss = double(trnLoss(:)');   % per-iteration

    if ~isempty(valAcc)
        [best, epoch]       = max(valAcc);
        out.best_val_acc    = best;
        out.best_val_epoch  = epoch;
    else
        out.best_val_acc   = NaN;
        out.best_val_epoch = NaN;
    end
end


function v = safeField(s, name, default)
    if isfield(s, name)
        v = s.(name);
    else
        v = default;
    end
end


function name = getGpuName()
    try
        if gpuDeviceCount('available') > 0
            g    = gpuDevice;
            name = string(g.Name);
        else
            name = "none";
        end
    catch
        name = "unknown";
    end
end


function h = getHostname()
    [~, h] = system('hostname');
    h = strtrim(string(h));
end
