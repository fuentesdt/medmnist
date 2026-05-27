function analyze_sweep(resultDir, topN)
%ANALYZE_SWEEP Print top runs and hyperparameter impact from summary.csv.
%
%   tools.analyze_sweep('results/nodulemnist3d/001_nodule_smoke')
%   tools.analyze_sweep('results/nodulemnist3d/001_nodule_smoke', 3)
%
%   Loads summary.csv, shows the top-N runs by test_acc, then for each
%   swept hyperparameter reports the mean test_acc per value and the spread
%   (max_mean − min_mean) as a coarse importance signal.

    arguments
        resultDir (1,1) string
        topN      (1,1) double {mustBePositive, mustBeInteger} = 5
    end

    csvPath = fullfile(resultDir, 'summary.csv');
    if ~isfile(csvPath)
        error('analyze_sweep:noCSV', ...
              'summary.csv not found: %s\nRun tools.aggregate_results first.', csvPath);
    end

    T = readtable(csvPath, 'TextType', 'string');
    n = height(T);

    fprintf('\n=== Sweep Analysis: %s ===\n', resultDir);
    fprintf('Total runs: %d\n', n);

    if ~ismember('test_acc', T.Properties.VariableNames)
        fprintf('(no test_acc column — nothing to analyse)\n');
        return
    end

    % ---- Top runs by test_acc -------------------------------------------

    T = sortrows(T, 'test_acc', 'descend');
    k = min(topN, n);
    fprintf('\nTop %d run(s) by test_acc:\n', k);
    fprintf('  %-36s %8s %8s %8s %8s\n', 'run_id', 'test_acc', 'test_auc', 'lr', 'seed');
    fprintf('  %s\n', repmat('-', 1, 74));
    for i = 1:k
        run_id   = char(T.run_id(i));
        test_acc = T.test_acc(i);
        test_auc = nanval(T, 'test_auc', i);
        lr_val   = nanval(T, 'lr',       i);
        seed_val = nanval(T, 'seed',     i);
        fprintf('  %-36s %8.4f %8.4f %8.4g %8g\n', run_id, test_acc, test_auc, lr_val, seed_val);
    end

    % ---- Hyperparameter impact ------------------------------------------
    % For each config column that varies across runs: mean test_acc per value.

    hpCols = {'lr','batchSize','augmentation','seed','epochs','optimizer'};
    hpCols = hpCols(ismember(hpCols, T.Properties.VariableNames));

    fprintf('\nHyperparameter impact (spread = max_mean − min_mean across values):\n');
    fprintf('  %-16s %8s  %s\n', 'param', 'spread', 'values → mean test_acc');
    fprintf('  %s\n', repmat('-', 1, 74));

    impacts = struct('param', {}, 'spread', {});

    for ki = 1:numel(hpCols)
        col  = hpCols{ki};
        vals = T.(col);

        if isnumeric(vals)
            uv = unique(vals(~isnan(vals)));
        else
            uv = unique(vals);
        end

        if numel(uv) < 2
            continue   % not swept; skip
        end

        groupMeans = zeros(numel(uv), 1);
        for vi = 1:numel(uv)
            if isnumeric(uv)
                mask = vals == uv(vi);
            else
                mask = vals == uv(vi);   % string == string works element-wise
            end
            groupMeans(vi) = mean(T.test_acc(mask), 'omitnan');
        end

        spread = max(groupMeans) - min(groupMeans);
        impacts(end + 1) = struct('param', col, 'spread', spread); %#ok<AGROW>

        pairs = cell(numel(uv), 1);
        for vi = 1:numel(uv)
            if isnumeric(uv)
                pairs{vi} = sprintf('%g→%.4f', uv(vi), groupMeans(vi));
            else
                pairs{vi} = sprintf('%s→%.4f', char(uv(vi)), groupMeans(vi));
            end
        end
        fprintf('  %-16s %8.4f  %s\n', col, spread, strjoin(pairs, '  '));
    end

    if isempty(impacts)
        fprintf('  (no swept hyperparameters detected)\n');
        return
    end

    % Most impactful parameter
    [~, best] = max([impacts.spread]);
    fprintf('\nMost impactful: %s  (spread = %.4f)\n', ...
            impacts(best).param, impacts(best).spread);

    % Best setting of the most impactful parameter
    col = impacts(best).param;
    vals = T.(col);
    if isnumeric(vals)
        uv = unique(vals(~isnan(vals)));
    else
        uv = unique(vals);
    end
    groupMeans = zeros(numel(uv), 1);
    for vi = 1:numel(uv)
        mask = vals == uv(vi);
        groupMeans(vi) = mean(T.test_acc(mask), 'omitnan');
    end
    [bestMean, bestIdx] = max(groupMeans);
    if isnumeric(uv)
        fprintf('Best value:     %s = %g  (mean test_acc = %.4f)\n\n', col, uv(bestIdx), bestMean);
    else
        fprintf('Best value:     %s = %s  (mean test_acc = %.4f)\n\n', col, char(uv(bestIdx)), bestMean);
    end
end


function v = nanval(T, col, i)
    % Return T.(col)(i) as double, or NaN if column is absent.
    if ismember(col, T.Properties.VariableNames) && isnumeric(T.(col))
        v = T.(col)(i);
    else
        v = NaN;
    end
end
