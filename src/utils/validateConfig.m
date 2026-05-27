function validateConfig(cfg)
%VALIDATECONFIG Validate a training config struct. Errors fast with a clear message.
%
%   validateConfig(cfg)

    arguments
        cfg (1,1) struct
    end

    required = {'dataset','dataPath','numClasses','inputSize', ...
                'architecture','optimizer','lr','batchSize','epochs', ...
                'augmentation','seed'};
    for i = 1:numel(required)
        f = required{i};
        if ~isfield(cfg, f)
            error('validateConfig:missingField', ...
                  'Config is missing required field: "%s".', f);
        end
    end

    % dataset
    validDatasets = {'adrenalmnist3d','fracturemnist3d','nodulemnist3d', ...
                     'organmnist3d','synapsemnist3d','vesselmnist3d'};
    checkMember(cfg.dataset, validDatasets, 'dataset');

    % dataPath
    if ~isStringScalar(cfg.dataPath) || strtrim(cfg.dataPath) == ""
        error('validateConfig:invalidValue', ...
              'cfg.dataPath must be a non-empty string.');
    end

    % numClasses
    if ~isnumeric(cfg.numClasses) || ~isscalar(cfg.numClasses) || ...
       cfg.numClasses < 2 || cfg.numClasses ~= floor(cfg.numClasses)
        error('validateConfig:invalidValue', ...
              'cfg.numClasses must be an integer >= 2 (got %s).', ...
              mat2str(cfg.numClasses));
    end

    % inputSize: [H W D C] — four positive integers
    if ~isnumeric(cfg.inputSize) || numel(cfg.inputSize) ~= 4 || ...
       any(cfg.inputSize < 1) || any(cfg.inputSize ~= floor(cfg.inputSize))
        error('validateConfig:invalidValue', ...
              'cfg.inputSize must be a length-4 vector of positive integers [H W D C] (got %s).', ...
              mat2str(cfg.inputSize));
    end

    % architecture
    validArchs = {'baseline_3d_v1'};
    checkMember(cfg.architecture, validArchs, 'architecture');

    % optimizer
    validOptims = {'adam','sgd'};
    checkMember(cfg.optimizer, validOptims, 'optimizer');

    % lr
    if ~isnumeric(cfg.lr) || ~isscalar(cfg.lr) || cfg.lr <= 0 || cfg.lr > 1
        error('validateConfig:invalidValue', ...
              'cfg.lr must be a scalar in (0, 1] (got %s).', mat2str(cfg.lr));
    end

    % batchSize
    if ~isnumeric(cfg.batchSize) || ~isscalar(cfg.batchSize) || ...
       cfg.batchSize < 1 || cfg.batchSize ~= floor(cfg.batchSize)
        error('validateConfig:invalidValue', ...
              'cfg.batchSize must be a positive integer (got %s).', ...
              mat2str(cfg.batchSize));
    end

    % epochs
    if ~isnumeric(cfg.epochs) || ~isscalar(cfg.epochs) || ...
       cfg.epochs < 1 || cfg.epochs ~= floor(cfg.epochs)
        error('validateConfig:invalidValue', ...
              'cfg.epochs must be a positive integer (got %s).', ...
              mat2str(cfg.epochs));
    end

    % augmentation
    validAugs = {'none','flip','flip_rotate'};
    checkMember(cfg.augmentation, validAugs, 'augmentation');

    % seed
    if ~isnumeric(cfg.seed) || ~isscalar(cfg.seed) || ...
       cfg.seed < 0 || cfg.seed ~= floor(cfg.seed)
        error('validateConfig:invalidValue', ...
              'cfg.seed must be a non-negative integer (got %s).', ...
              mat2str(cfg.seed));
    end
end


function checkMember(val, validSet, fieldName)
    % Accepts both string scalars and char vectors.
    if ~ischar(val) && ~isStringScalar(val)
        error('validateConfig:invalidType', ...
              'cfg.%s must be a string (got %s).', fieldName, class(val));
    end
    if ~any(strcmp(string(val), string(validSet)))
        error('validateConfig:invalidValue', ...
              'cfg.%s must be one of {%s} (got "%s").', ...
              fieldName, strjoin(string(validSet), ', '), val);
    end
end
