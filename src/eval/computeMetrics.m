function metrics = computeMetrics(cfg, scores, YTest)
%COMPUTEMETRICS Accuracy, per-class accuracy, macro AUC, and chance floor.
%
%   metrics = computeMetrics(cfg, scores, YTest)
%
%   scores: [N numClasses] softmax probabilities from minibatchpredict.
%   YTest:  [N 1] categorical (from encodeLabels; double() gives 1-indexed class).

    arguments
        cfg    (1,1) struct
        scores (:,:) single
        YTest  (:,1) categorical
    end

    [~, predIdx] = max(scores, [], 2);   % 1-indexed predicted class
    trueIdx      = double(YTest);         % 1-indexed true class

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
