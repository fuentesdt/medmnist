function summarize_benchmarks(resultsRoot)
%SUMMARIZE_BENCHMARKS Cross-dataset table: best achieved vs. published targets.
%
%   tools.summarize_benchmarks()
%   tools.summarize_benchmarks('results')
%
%   Scans results/<dataset>/**/*.json, picks the best test_acc per dataset,
%   and compares against the ResNet-50 baselines from Yang et al. 2023.
%   "Reproduced" = within 0.02 ACC of target.

    arguments
        resultsRoot (1,1) string = "results"
    end

    targets = benchmarkTargets();
    datasets = fieldnames(targets);

    hdr = sprintf('%-18s  %8s  %8s  %8s  %8s  %8s  %8s', ...
        'dataset', 'best_acc', 'tgt_acc', 'gap', 'best_auc', 'tgt_auc', 'status');
    fprintf('\n%s\n%s\n', hdr, repmat('-', 1, strlength(hdr)));

    for i = 1:numel(datasets)
        ds = datasets{i};
        t  = targets.(ds);

        jsons = findJsons(fullfile(resultsRoot, ds));
        if isempty(jsons)
            fprintf('%-18s  %8s  %8.3f  %8s  %8s  %8.3f  %8s\n', ...
                ds, '—', t.acc, '—', '—', t.auc, 'not run');
            continue
        end

        [bestAcc, bestAuc] = bestResult(jsons);
        gap    = bestAcc - t.acc;
        status = classifyGap(gap);

        fprintf('%-18s  %8.4f  %8.3f  %+8.3f  %8.4f  %8.3f  %8s\n', ...
            ds, bestAcc, t.acc, gap, bestAuc, t.auc, status);
    end
    fprintf('\n"reproduced" = within 0.02 ACC of published ResNet-50 baseline.\n\n');
end


% -------------------------------------------------------------------------

function t = benchmarkTargets()
    % Yang et al., Scientific Data 2023, Table 4 (ResNet-50 3D).
    t.nodulemnist3d   = struct('acc', 0.84, 'auc', 0.87);
    t.organmnist3d    = struct('acc', 0.95, 'auc', 0.997);
    t.adrenalmnist3d  = struct('acc', 0.79, 'auc', 0.83);
    t.vesselmnist3d   = struct('acc', 0.88, 'auc', 0.87);
    t.fracturemnist3d = struct('acc', 0.51, 'auc', 0.71);
    t.synapsemnist3d  = struct('acc', 0.73, 'auc', 0.82);
end


function jsons = findJsons(datasetDir)
    % Return paths to all run_NNN.json files under datasetDir.
    if ~isfolder(datasetDir)
        jsons = {};
        return
    end
    entries = dir(fullfile(datasetDir, '**', 'run_*.json'));
    jsons   = fullfile({entries.folder}, {entries.name});
end


function [bestAcc, bestAuc] = bestResult(jsons)
    bestAcc = -Inf;
    bestAuc = NaN;
    for k = 1:numel(jsons)
        try
            d = jsondecode(fileread(jsons{k}));
            if ~strcmp(d.status, 'complete'), continue; end
            acc = d.results.test_acc;
            auc = d.results.test_auc;
            if acc > bestAcc
                bestAcc = acc;
                bestAuc = auc;
            end
        catch
        end
    end
end


function s = classifyGap(gap)
    if gap >= -0.02
        s = 'reproduced';
    elseif gap >= -0.05
        s = 'close';
    else
        s = 'below';
    end
end
