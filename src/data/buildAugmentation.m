function augFcn = buildAugmentation(cfg)
%BUILDAUGMENTATION Dispatch point: return an image augmentation function.
%
%   augFcn = buildAugmentation(cfg)
%
%   Returns a function handle:  Xaug = augFcn(X)
%   where X and Xaug are [H W D C] single arrays (one sample).
%
%   Augmentation is applied per-sample during training (not at validation/test).
%   train.m wraps augFcn into a datastore transform.

    arguments
        cfg (1,1) struct
    end

    switch cfg.augmentation
        case 'none'
            augFcn = @(X) X;

        case 'flip'
            augFcn = @flip3D;

        case 'flip_rotate'
            augFcn = @flipRotate3D;

        otherwise
            error('buildAugmentation:unknownAugmentation', ...
                  'Unknown augmentation "%s". Valid: none, flip, flip_rotate.', ...
                  cfg.augmentation);
    end
end


function X = flip3D(X)
    % Independent 50% chance of flipping along each spatial axis.
    for dim = 1:3
        if rand() > 0.5
            X = flip(X, dim);
        end
    end
end


function X = flipRotate3D(X)
    % Flips along all axes, then a random 90-degree rotation in one spatial plane.
    X = flip3D(X);

    plane = randi(3);      % 1 = H×W, 2 = H×D, 3 = W×D
    k     = randi([1 3]);  % number of 90-degree CCW turns (1, 2, or 3)

    switch plane
        case 1  % rotate in H×W plane — rot90 acts on dims 1,2 by default
            X = rot90(X, k);

        case 2  % rotate in H×D plane — swap D into position 2, rotate, swap back
            X = permute(X, [1 3 2 4]);
            X = rot90(X, k);
            X = permute(X, [1 3 2 4]);  % self-inverse permutation

        case 3  % rotate in W×D plane — move W,D into positions 1,2, rotate, restore
            X = permute(X, [2 3 1 4]);
            X = rot90(X, k);
            X = permute(X, [3 1 2 4]);
    end
end
