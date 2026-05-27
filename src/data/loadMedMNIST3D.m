function data = loadMedMNIST3D(npzPath)
%LOADMEDMNIST3D Load a MedMNIST3D .npz file via the Python bridge.
%
%   data = loadMedMNIST3D(npzPath)
%
%   Returns a struct with fields XTrain, YTrain, XVal, YVal, XTest, YTest.
%   X arrays: [H W D C N] single, values in [0, 1].
%   Y arrays: [N 1] int64, 0-indexed class labels.
%
%   Requires a Python environment with NumPy (see pyenv).

    arguments
        npzPath (1,1) string
    end

    if ~isfile(npzPath)
        error('loadMedMNIST3D:fileNotFound', ...
              'Data file not found: %s', npzPath);
    end

    try
        np = py.importlib.import_module('numpy');
    catch ME
        error('loadMedMNIST3D:noNumpy', ...
              'Could not import numpy (%s). Run pyenv first.', ME.message);
    end

    npz     = np.load(npzPath);
    cleanup = onCleanup(@() npz.close());  %#ok<NASGU>

    data.XTrain = loadImages(npz, 'train');
    data.YTrain = loadLabels(npz, 'train');
    data.XVal   = loadImages(npz, 'val');
    data.YVal   = loadLabels(npz, 'val');
    data.XTest  = loadImages(npz, 'test');
    data.YTest  = loadLabels(npz, 'test');
end


function X = loadImages(npz, split)
    % NumPy stores as (N,H,W,D) C-order. MATLAB's cast transposes to [D W H N].
    % Permute to [H W D N], add channel dim → [H W D C N], rescale to [0,1].
    key = char(split + "_images");
    arr = single(npz{key});             % [D W H N]

    if ndims(arr) ~= 4
        error('loadMedMNIST3D:unexpectedRank', ...
              'Expected 4-D image array for split "%s", got %d-D.', split, ndims(arr));
    end

    arr = permute(arr, [3 2 1 4]);      % [H W D N]
    N   = size(arr, 4);
    X   = reshape(arr, size(arr,1), size(arr,2), size(arr,3), 1, N);  % [H W D C N]
    X   = X / 255;
end


function Y = loadLabels(npz, split)
    % NumPy stores labels as (N,1) C-order. MATLAB's cast gives [1 N]; flatten to [N 1].
    key = char(split + "_labels");
    Y   = int64(npz{key});              % [1 N]
    Y   = Y(:);                         % [N 1]
end
