function data = loadData(cfg)
%LOADDATA Dispatch point: load training data for the configured dataset.
%
%   data = loadData(cfg)
%
%   Returns a struct with XTrain/YTrain/XVal/YVal/XTest/YTest.
%   See loadMedMNIST3D for the field formats.

    arguments
        cfg (1,1) struct
    end

    medmnist3d = ["adrenalmnist3d", "fracturemnist3d", "nodulemnist3d", ...
                  "organmnist3d",   "synapsemnist3d",  "vesselmnist3d"];

    if any(cfg.dataset == medmnist3d)
        data = loadMedMNIST3D(cfg.dataPath);
    else
        error('loadData:unknownDataset', ...
              'No loader defined for dataset "%s". Add a branch here.', cfg.dataset);
    end
end
