function head = buildHead(cfg)
%BUILDHEAD Dispatch point: return output layers and loss function.
%
%   head = buildHead(cfg)
%
%   Returns a struct:
%     head.layers  — layer array to append after the backbone
%     head.lossFcn — loss function string passed to trainnet
%
%   Dispatches on cfg.architecture. Current datasets are all single-label
%   classification, so crossentropy is universal here.

    arguments
        cfg (1,1) struct
    end

    switch cfg.architecture
        case 'baseline_3d_v1'
            head.layers  = [flattenLayer(                          'Name', 'flatten'); ...
                            fullyConnectedLayer(cfg.numClasses,    'Name', 'fc'); ...
                            softmaxLayer(                          'Name', 'softmax')];
            head.lossFcn = 'crossentropy';

        otherwise
            error('buildHead:unknownArchitecture', ...
                  'No head defined for architecture "%s". Add a branch here.', ...
                  cfg.architecture);
    end
end
