function layer = buildInputLayer(cfg)
%BUILDINPUTLAYER Dispatch point: return the network input layer.
%
%   layer = buildInputLayer(cfg)
%
%   Dispatches on cfg.architecture. cfg.inputSize is [H W D C].
%   Normalization is 'none' because loadMedMNIST3D already rescales to [0, 1].

    arguments
        cfg (1,1) struct
    end

    switch cfg.architecture
        case 'baseline_3d_v1'
            layer = image3dInputLayer(cfg.inputSize, ...
                'Normalization', 'none', ...
                'Name', 'input');

        otherwise
            error('buildInputLayer:unknownArchitecture', ...
                  'No input layer defined for architecture "%s". Add a branch here.', ...
                  cfg.architecture);
    end
end
