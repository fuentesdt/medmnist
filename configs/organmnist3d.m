function cfg = organmnist3d()
%ORGANMNIST3D Base config for the OrganMNIST3D dataset.
%
%   cfg = organmnist3d()
%
%   Target (Yang et al. 2023, ResNet-50 3D): ACC ~0.95, AUC ~0.997.
%   Paths are relative to the repo root; run train.m from there.

    cfg.dataset      = "organmnist3d";
    cfg.dataPath     = "./data/medmnist3d/organmnist3d.npz";
    cfg.numClasses   = 11;
    cfg.inputSize    = [28 28 28 1];   % [H W D C]

    cfg.architecture = "baseline_3d_v1";
    cfg.optimizer    = "adam";
    cfg.lr           = 1e-3;
    cfg.batchSize    = 32;
    cfg.epochs       = 50;

    % No flip — organs are lateralised (liver right, spleen left).
    cfg.augmentation = "none";

    cfg.seed         = 42;
end
