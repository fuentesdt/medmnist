function cfg = adrenalmnist3d()
%ADRENALMNIST3D Base config for the AdrenalMNIST3D dataset.
%
%   cfg = adrenalmnist3d()
%
%   Target (Yang et al. 2023, ResNet-50 3D): ACC ~0.79, AUC ~0.83.
%   Paths are relative to the repo root; run train.m from there.

    cfg.dataset      = "adrenalmnist3d";
    cfg.dataPath     = "./data/medmnist3d/adrenalmnist3d.npz";
    cfg.numClasses   = 2;
    cfg.inputSize    = [28 28 28 1];   % [H W D C]

    cfg.architecture = "baseline_3d_v1";
    cfg.optimizer    = "adam";
    cfg.lr           = 1e-3;
    cfg.batchSize    = 32;
    cfg.epochs       = 50;

    % flip only — CT, symmetric gland structure, no laterality concern.
    cfg.augmentation = "flip";

    cfg.seed         = 42;
end
