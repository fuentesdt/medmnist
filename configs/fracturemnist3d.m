function cfg = fracturemnist3d()
%FRACTUREMNIST3D Base config for the FractureMNIST3D dataset.
%
%   cfg = fracturemnist3d()
%
%   Target (Yang et al. 2023, ResNet-50 3D): ACC ~0.51, AUC ~0.71.
%   Hard task — low published ceiling even for ResNet-50.
%   Paths are relative to the repo root; run train.m from there.

    cfg.dataset      = "fracturemnist3d";
    cfg.dataPath     = "./data/medmnist3d/fracturemnist3d.npz";
    cfg.numClasses   = 3;
    cfg.inputSize    = [28 28 28 1];   % [H W D C]

    cfg.architecture = "baseline_3d_v1";
    cfg.optimizer    = "adam";
    cfg.lr           = 1e-3;
    cfg.batchSize    = 32;
    cfg.epochs       = 50;

    % flip only — CT rib/spine patches.
    cfg.augmentation = "flip";

    cfg.useBatchNorm = true;
    cfg.seed         = 42;
end
