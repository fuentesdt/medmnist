function summarize_medmnist3d(dataDir)
%SUMMARIZE_MEDMNIST3D Load each MedMNIST3D .npz and print split statistics.
%
%   summarize_medmnist3d()          uses ./data/medmnist3d
%   summarize_medmnist3d(dataDir)   uses the given directory
%
%   For each dataset, prints: per-split N, image dtype/shape, label dtype,
%   number of classes, class distribution, intensity range, and class balance.
%
%   Requires a working Python environment configured in MATLAB (see pyenv).

    arguments
        dataDir (1,1) string = "./data/medmnist3d"
    end

    % --- Sanity-check the Python environment up front ----------------------
    pe = pyenv;
    if pe.Status ~= "Loaded" && pe.Version == ""
        error("summarize_medmnist3d:NoPython", ...
              "No Python environment configured. Run pyenv('Version', '<path>') first.");
    end
    try
        np = py.importlib.import_module('numpy');
    catch ME
        error("summarize_medmnist3d:NoNumpy", ...
              "Could not import numpy in Python (%s). Install it in the env reported by pyenv.", ...
              ME.message);
    end

    datasets = ["adrenalmnist3d", "fracturemnist3d", "nodulemnist3d", ...
                "organmnist3d", "synapsemnist3d", "vesselmnist3d"];

    for i = 1:numel(datasets)
        name = datasets(i);
        fpath = fullfile(dataDir, name + ".npz");
        fprintf("\n========== %s ==========\n", name);

        if ~isfile(fpath)
            fprintf("  [skip] file not found: %s\n", fpath);
            continue
        end

        try
            summarizeOne(fpath, np);
        catch ME
            fprintf("  [fail] %s\n", ME.message);
        end
    end
end


function summarizeOne(npzPath, np)
    % Load the .npz via numpy and pull the six standard arrays into MATLAB.
    npz = np.load(npzPath);
    cleanup = onCleanup(@() npz.close());  %#ok<NASGU> close the file handle

    splits = ["train", "val", "test"];

    % --- Per-split numeric summaries --------------------------------------
    fprintf("%-7s %8s %22s %10s %12s %14s\n", ...
            "split", "N", "img shape (HxWxD)", "img dtype", "intensity", "labels (uniq)");
    fprintf("%s\n", repmat('-', 1, 78));

    classCounts = struct();   % accumulated across splits
    classDtype = "";

    for s = splits
        imgKey = char(s + "_images");
        lblKey = char(s + "_labels");

        imgsPy = npz{imgKey};
        lblsPy = npz{lblKey};

        % Read dtypes from the Python side BEFORE casting — once we cast in
        % MATLAB, the original numpy dtype is gone.
        imgDtype = string(imgsPy.dtype.name);
        lblDtype = string(lblsPy.dtype.name);
        if classDtype == "", classDtype = lblDtype; end

        % Shape comes back as a py.tuple of int64-ish values.
        imgShape = double(py.array.array('q', py.numpy.asarray(imgsPy.shape).tolist()));
        lblShape = double(py.array.array('q', py.numpy.asarray(lblsPy.shape).tolist()));

        % Convert to MATLAB. For uint8 images keep them as uint8 to avoid
        % needlessly inflating memory just for a summary.
        imgs = uint8(imgsPy);   % NumPy axis order [N H W D] is preserved
        lbls = int64(lblsPy);   % labels are small ints; int64 is safe

        % Defensive: numpy reports shape as [N H W D]; after cast MATLAB
        % sees the same numeric ordering, just interpreted column-major.
        % We use the Python-reported shape for the printout so it's
        % unambiguous what NumPy stored.
        if numel(imgShape) ~= 4
            error("Unexpected image rank %d (expected 4 for [N H W D]).", numel(imgShape));
        end
        N = imgShape(1); H = imgShape(2); W = imgShape(3); D = imgShape(4);

        if lblShape(1) ~= N
            error("Label count %d does not match image count %d.", lblShape(1), N);
        end

        % Intensity range — pull from the casted array.
        imin = double(min(imgs(:)));
        imax = double(max(imgs(:)));

        % Unique labels in this split (labels are N x 1).
        uniq = unique(lbls(:));
        fprintf("%-7s %8d %5dx%-5dx%-5d %10s %5d..%-5d %s\n", ...
                s, N, H, W, D, imgDtype, imin, imax, ...
                join(string(uniq), ","));

        % Accumulate counts per class across splits.
        for u = uniq.'
            key = "c" + string(u);
            if ~isfield(classCounts, key)
                classCounts.(key) = struct('train', 0, 'val', 0, 'test', 0, 'label', double(u));
            end
            classCounts.(key).(s) = sum(lbls(:) == u);
        end
    end

    % --- Class distribution -----------------------------------------------
    fprintf("\nClass distribution (label dtype: %s):\n", classDtype);
    keys = fieldnames(classCounts);
    % Sort by numeric label for readable ordering.
    labels = cellfun(@(k) classCounts.(k).label, keys);
    [~, order] = sort(labels);
    keys = keys(order);

    fprintf("%-7s %8s %8s %8s %8s %8s\n", "class", "train", "val", "test", "total", "% total");
    fprintf("%s\n", repmat('-', 1, 50));
    totals = [0 0 0];
    rowTotals = zeros(numel(keys), 1);
    for i = 1:numel(keys)
        c = classCounts.(keys{i});
        rowTotals(i) = c.train + c.val + c.test;
        totals = totals + [c.train c.val c.test];
    end
    grand = sum(rowTotals);
    for i = 1:numel(keys)
        c = classCounts.(keys{i});
        fprintf("%-7d %8d %8d %8d %8d %7.1f%%\n", ...
                c.label, c.train, c.val, c.test, rowTotals(i), ...
                100 * rowTotals(i) / grand);
    end
    fprintf("%s\n", repmat('-', 1, 50));
    fprintf("%-7s %8d %8d %8d %8d %7.1f%%\n", "total", totals(1), totals(2), totals(3), grand, 100.0);

    % Class balance: ratio of largest to smallest class.
    if numel(rowTotals) > 1
        imbalance = max(rowTotals) / max(min(rowTotals), 1);
        fprintf("Imbalance ratio (max/min class): %.2fx\n", imbalance);
    end

    % Majority-class baseline accuracy on the test split — this is the floor
    % the classifier must beat. If trainnet doesn't clear this, it's broken.
    testCounts = zeros(numel(keys), 1);
    for i = 1:numel(keys)
        testCounts(i) = classCounts.(keys{i}).test;
    end
    if sum(testCounts) > 0
        fprintf("Majority-class test accuracy (chance floor): %.3f\n", ...
                max(testCounts) / sum(testCounts));
    end
end
