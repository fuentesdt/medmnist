function metrics = computeMetrics(cfg, scores, YTest)
%COMPUTEMETRICS Accuracy, per-class accuracy, macro AUC, and chance floor.
%
%   metrics = computeMetrics(cfg, scores, YTest)
%
%   scores: [N numClasses] or [numClasses N] numeric from minibatchpredict.
%   YTest:  [N 1] categorical (from encodeLabels; double() gives 1-indexed class).

    arguments
        cfg    (1,1) struct
        scores (:,:) {mustBeNumeric}
        YTest  (:,1) categorical
    end

    % Normalize to [N, numClasses] — minibatchpredict output orientation varies
    % across MATLAB versions and network types.
    N = size(YTest, 1);
    fprintf('DBG computeMetrics: scores %dx%d  YTest %dx%d  N=%d  numClasses=%d\n', ...
            size(scores,1), size(scores,2), size(YTest,1), size(YTest,2), N, cfg.numClasses);
    if size(scores, 1) ~= N
        scores = scores';
    end
    scores = single(scores);

    [~, predIdx] = max(scores, [], 2);
    predIdx = predIdx(:);               % ensure column vector
    trueIdx = double(YTest);
    trueIdx = trueIdx(:);               % ensure column vector

    fprintf('DBG computeMetrics: predIdx %dx%d  trueIdx %dx%d\n', ...
            size(predIdx,1), size(predIdx,2), size(trueIdx,1), size(trueIdx,2));

    % Overall accuracy
    metrics.test_acc = mean(predIdx == trueIdx);

    % Per-class accuracy
    perClass = zeros(1, cfg.numClasses);
    for c = 1:cfg.numClasses
        mask = trueIdx == c;
        if any(mask)
            perClass(c) = mean(predIdx(mask) == c);
        end
    end
    metrics.test_acc_per_class = perClass;

    % Macro-averaged one-vs-rest AUC (requires Statistics and ML Toolbox)
    trueLabel0 = trueIdx - 1;   % 0-indexed for perfcurve positiveClass argument
    aucVals    = zeros(1, cfg.numClasses);
    try
        for c = 1:cfg.numClasses
            [~, ~, ~, aucVals(c)] = perfcurve(trueLabel0, scores(:, c), c - 1);
        end
        metrics.test_auc = mean(aucVals);
    catch
        metrics.test_auc = NaN;
    end

    % Majority-class fraction on test split — the floor any classifier must beat
    counts           = histcounts(trueIdx, 1 : cfg.numClasses + 1);
    metrics.chance_floor = max(counts) / numel(trueIdx);
end
