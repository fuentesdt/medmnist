function Y = encodeLabels(cfg, raw)
%ENCODELABELS Convert raw 0-indexed integer labels to categorical.
%
%   Y = encodeLabels(cfg, raw)
%
%   raw: [N 1] integer array (0-indexed class IDs from loadData).
%   Y:   [N 1] categorical with values 0, 1, ..., numClasses-1.
%
%   Specifying class IDs explicitly ensures all classes appear in every split,
%   even if a class has zero samples in that split.

    arguments
        cfg (1,1) struct
        raw (:,1) {mustBeNumeric}
    end

    classIds = int64(0 : cfg.numClasses - 1);
    Y = categorical(raw(:), classIds);
end
