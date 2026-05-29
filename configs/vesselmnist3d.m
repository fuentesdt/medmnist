function cfg = vesselmnist3d()
%VESSELMNIST3D Base config for the VesselMNIST3D dataset.
%
%   cfg = vesselmnist3d()
%
%   Target (Yang et al. 2023, ResNet-50 3D): ACC ~0.88, AUC ~0.87.
%   Paths are relative to the repo root; run train.m from there.

    cfg.dataset      = "vesselmnist3d";
    cfg.dataPath     = "./data/medmnist3d/vesselmnist3d.npz";
    cfg.numClasses   = 2;
    cfg.inputSize    = [28 28 28 1];   % [H W D C]

    cfg.architecture = "baseline_3d_v1";
    cfg.optimizer    = "adam";
    cfg.lr           = 1e-3;
    cfg.batchSize    = 32;
    cfg.epochs       = 50;

    % flip only — MRA vessel patches, no directional meaning.
    cfg.augmentation = "flip";

    cfg.useBatchNorm = true;
    cfg.seed         = 42;
end
