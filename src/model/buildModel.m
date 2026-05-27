function model = buildModel(cfg)
%BUILDMODEL Assemble the full layer stack for the configured architecture.
%
%   model = buildModel(cfg)
%
%   Returns a struct:
%     model.layers  — layer array ready to pass to trainnet
%     model.lossFcn — loss function string (from buildHead)

    arguments
        cfg (1,1) struct
    end

    inputLayer = buildInputLayer(cfg);
    head       = buildHead(cfg);
    backbone   = buildBackbone(cfg);

    model.layers  = [inputLayer; backbone; head.layers];
    model.lossFcn = head.lossFcn;
end


function layers = buildBackbone(cfg)
    switch cfg.architecture
        case 'baseline_3d_v1'
            layers = baseline3dV1Backbone(cfg);
        otherwise
            error('buildModel:unknownArchitecture', ...
                  'No backbone defined for architecture "%s". Add a branch here.', ...
                  cfg.architecture);
    end
end


function layers = baseline3dV1Backbone(cfg)
    % Three conv blocks (8→16→32 filters) with BN+ReLU and 2× max-pool after
    % each of the first two blocks. Global average pool collapses spatial dims.
    %
    % Spatial dimensions after each stage for 28³ input:
    %   after block 1 + pool: 14³
    %   after block 2 + pool: 7³
    %   after block 3 + GAP:  1³  (then FC flattens)

    spatialIn = cfg.inputSize(1:3);
    assert(all(mod(spatialIn, 4) == 0), ...
           'baseline_3d_v1 requires spatial dims divisible by 4 (got %s).', ...
           mat2str(spatialIn));
    gapSize = spatialIn / 4;   % size after two stride-2 max pools

    layers = [
        convolution3dLayer([3 3 3], 8,  'Padding', 'same', 'Name', 'conv1')
        batchNormalizationLayer(            'Name', 'bn1')
        reluLayer(                          'Name', 'relu1')
        maxPooling3dLayer([2 2 2], 'Stride', [2 2 2], 'Name', 'pool1')

        convolution3dLayer([3 3 3], 16, 'Padding', 'same', 'Name', 'conv2')
        batchNormalizationLayer(            'Name', 'bn2')
        reluLayer(                          'Name', 'relu2')
        maxPooling3dLayer([2 2 2], 'Stride', [2 2 2], 'Name', 'pool2')

        convolution3dLayer([3 3 3], 32, 'Padding', 'same', 'Name', 'conv3')
        batchNormalizationLayer(            'Name', 'bn3')
        reluLayer(                          'Name', 'relu3')
        averagePooling3dLayer(gapSize,       'Name', 'gap')
    ];
end
