function aggregate_results(resultDir)
%AGGREGATE_RESULTS Build summary.csv from per-run JSON files.
%
%   tools.aggregate_results('results/nodulemnist3d/001_nodule_smoke')
%
%   Reads every run_NNN.json in resultDir, flattens each to one row,
%   sorts by test_acc descending, and writes summary.csv.
%   Skips malformed JSONs with a warning.

    arguments
        resultDir (1,1) string
    end

    d = dir(fullfile(resultDir, 'run_*.json'));
    if isempty(d)
        error('aggregate_results:noJson', 'No run_*.json files found in %s', resultDir);
    end

    % Sort by filename so rows appear in run order before the final sort.
    [~, order] = sort(string({d.name}));
    d = d(order);

    rows = cell(numel(d), 1);
    for i = 1:numel(d)
        fpath = fullfile(d(i).folder, d(i).name);
        try
            rows{i} = flattenRun(jsondecode(fileread(fpath)));
        catch ME
            warning('aggregate_results:parseError', 'Skipping %s: %s', d(i).name, ME.message);
        end
    end

    rows = rows(~cellfun(@isempty, rows));
    if isempty(rows)
        error('aggregate_results:noParsed', 'No JSON files parsed successfully.');
    end

    T = struct2table([rows{:}]);

    if ismember('test_acc', T.Properties.VariableNames)
        T = sortrows(T, 'test_acc', 'descend');
    end

    csvPath = fullfile(resultDir, 'summary.csv');
    writetable(T, csvPath);
    fprintf('aggregate_results: %d rows → %s\n', height(T), csvPath);
end


% =========================================================================

function row = flattenRun(data)
    % Identity
    row.run_id        = safeStr(data, 'run_id');
    row.sweep_id      = safeStr(data, 'sweep_id');
    row.status        = safeStr(data, 'status');
    row.git_sha       = safeStr(data, 'git_sha');
    row.config_hash   = safeStr(data, 'config_hash');
    row.timestamp_utc = safeStr(data, 'timestamp_utc');

    % Results (promoted to top level — what Claude reads first)
    if isfield(data, 'results')
        r = data.results;
        row.test_acc       = safeNum(r, 'test_acc',        NaN);
        row.test_auc       = safeNum(r, 'test_auc',        NaN);
        row.best_val_acc   = safeNum(r, 'best_val_acc',    NaN);
        row.best_val_epoch = safeNum(r, 'best_val_epoch',  NaN);
        row.chance_floor   = safeNum(r, 'chance_floor',    NaN);
        row.train_time_sec = safeNum(r, 'train_time_sec',  NaN);
    end

    % Config
    if isfield(data, 'config')
        c = data.config;
        row.dataset      = safeStr(c, 'dataset');
        row.lr           = safeNum(c, 'lr',          NaN);
        row.batchSize    = safeNum(c, 'batchSize',   NaN);
        row.epochs       = safeNum(c, 'epochs',      NaN);
        row.optimizer    = safeStr(c, 'optimizer');
        row.augmentation = safeStr(c, 'augmentation');
        row.seed         = safeNum(c, 'seed',        NaN);
        row.architecture = safeStr(c, 'architecture');
    end

    % Environment
    if isfield(data, 'env')
        row.gpu  = safeStr(data.env, 'gpu');
        row.host = safeStr(data.env, 'host');
    end
end


function v = safeStr(s, field)
    if isfield(s, field)
        raw = s.(field);
        if ischar(raw) || isstring(raw)
            v = string(raw);
            return
        end
    end
    v = "";
end


function v = safeNum(s, field, default)
    if isfield(s, field) && isnumeric(s.(field)) && isscalar(s.(field))
        v = double(s.(field));
    else
        v = default;
    end
end
