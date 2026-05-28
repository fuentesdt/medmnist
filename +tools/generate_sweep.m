function generate_sweep(sweepDir)
%GENERATE_SWEEP Expand sweep.yaml into per-run MATLAB config files.
%
%   tools.generate_sweep('configs/sweeps/001_nodule_smoke')
%
%   Reads sweep.yaml, computes the Cartesian product of the grid, and writes
%   run_NNN.m into the sweep directory (one file per combination).
%
%   Errors if the grid exceeds constraints.max_runs.
%   Idempotent: if all run files already exist, exits without changes.
%   Errors if only some run files exist (delete all to regenerate).

    arguments
        sweepDir (1,1) string
    end

    yamlPath = fullfile(sweepDir, 'sweep.yaml');
    if ~isfile(yamlPath)
        error('generate_sweep:noYaml', 'sweep.yaml not found: %s', yamlPath);
    end

    def = loadYaml(yamlPath);
    validateDef(def);

    % ---- Grid expansion -------------------------------------------------
    gridFields = fieldnames(def.grid)';   % row cell to match cell(1, N)
    valueCells  = cell(1, numel(gridFields));
    for k = 1:numel(gridFields)
        valueCells{k} = toCell(def.grid.(gridFields{k}));
    end

    combos  = cartesianProduct(valueCells);
    nRuns   = size(combos, 1);
    maxRuns = double(def.constraints.max_runs);

    if nRuns > maxRuns
        error('generate_sweep:tooManyRuns', ...
              ['Grid expands to %d runs but constraints.max_runs = %d.\n' ...
               'Reduce the grid or raise max_runs in sweep.yaml.'], nRuns, maxRuns);
    end

    % ---- Idempotency check ----------------------------------------------
    runPaths  = arrayfun(@(i) fullfile(sweepDir, sprintf('run_%03d.m', i)), ...
                         1:nRuns, 'UniformOutput', false);
    existMask = cellfun(@isfile, runPaths);

    if all(existMask)
        fprintf('generate_sweep: all %d run files already exist — nothing to do.\n', nRuns);
        return
    end
    if any(existMask)
        error('generate_sweep:partialState', ...
              ['%d of %d run files exist in %s.\n' ...
               'Delete all run_NNN.m files and rerun to regenerate.'], ...
              sum(existMask), nRuns, sweepDir);
    end

    % ---- Write run files ------------------------------------------------
    [~, baseFuncName] = fileparts(string(def.base_config));
    sweepId           = string(def.sweep_id);

    for i = 1:nRuns
        writeRunFile(runPaths{i}, i, nRuns, sweepId, baseFuncName, gridFields, combos(i, :));
    end

    dimSummary = strjoin( ...
        cellfun(@(f, v) sprintf('%s(%d)', f, numel(v)), gridFields, valueCells, ...
                'UniformOutput', false), ' × ');
    fprintf('generate_sweep: wrote %d run configs to %s\n', nRuns, sweepDir);
    fprintf('  Grid: %s = %d runs\n', dimSummary, nRuns);
end


% =========================================================================
% Local functions
% =========================================================================

function def = loadYaml(yamlPath)
    def = [];

    % Python bridge: yaml → json → jsondecode (reuses the bridge already
    % required for data loading; PyYAML ships with most scientific Python envs).
    if isempty(def)
        try
            py_yaml = py.importlib.import_module('yaml');
            py_json = py.importlib.import_module('json');
            raw     = fileread(yamlPath);
            def     = jsondecode(char(py_json.dumps(py_yaml.safe_load(raw))));
        catch
        end
    end

    % Built-in (MATLAB R2024a+)
    if isempty(def) && ~isempty(which('yamlread'))
        try, def = yamlread(yamlPath); catch, end
    end

    % yaml-matlab package fallback
    if isempty(def)
        try, def = yaml.load(fileread(yamlPath)); catch, end
    end

    if isempty(def)
        error('generate_sweep:noYamlParser', [ ...
            'No YAML parser found.  Tried: Python PyYAML, MATLAB yamlread, yaml-matlab.\n' ...
            '  Fix: ensure the Python env configured in pyenv has PyYAML installed\n'       ...
            '       (pip install pyyaml), or upgrade to MATLAB R2024a+.']);
    end
end


function validateDef(def)
    for f = {'sweep_id', 'dataset', 'base_config', 'grid', 'constraints'}
        if ~isfield(def, f{1})
            error('generate_sweep:missingKey', ...
                  'sweep.yaml is missing required key: "%s".', f{1});
        end
    end
    if ~isfield(def.constraints, 'max_runs')
        error('generate_sweep:missingKey', ...
              'sweep.yaml constraints block is missing "max_runs".');
    end
end


function c = toCell(v)
    % Normalise any YAML scalar/array/cell into a uniform cell row vector.
    if iscell(v)
        c = v(:)';
    elseif isnumeric(v) || islogical(v)
        c = num2cell(v(:)');
    elseif ischar(v) || (isstring(v) && isscalar(v))
        c = {char(v)};
    else
        error('generate_sweep:unsupportedType', ...
              'Grid value of class "%s" is not supported.', class(v));
    end
end


function combos = cartesianProduct(valueCells)
    % Returns [nRuns × nDims] cell array. Rightmost dim varies fastest.
    N     = numel(valueCells);
    sizes = cellfun(@numel, valueCells);
    nRuns = prod(sizes);

    combos = cell(nRuns, N);
    period = nRuns;
    for d = 1:N
        n      = sizes(d);
        period = period / n;
        for r = 1:nRuns
            idx           = mod(floor((r - 1) / period), n) + 1;
            combos{r, d}  = valueCells{d}{idx};
        end
    end
end


function writeRunFile(runPath, idx, nRuns, sweepId, baseFuncName, fields, vals)
    funcName = sprintf('run_%03d', idx);

    overrides    = '';
    summaryParts = cell(1, numel(fields));
    for k = 1:numel(fields)
        cfgField        = snake2camel(fields{k});
        valStr          = value2matlab(vals{k});
        overrides       = [overrides, sprintf('    cfg.%-16s = %s;\n', cfgField, valStr)]; %#ok<AGROW>
        summaryParts{k} = sprintf('%s=%s', fields{k}, valStr);
    end

    content = sprintf([ ...
        'function cfg = %s\n'                                       ...
        '%%%s  Auto-generated by generate_sweep — do not edit.\n'  ...
        '%%   Sweep: %s  |  Run %d of %d\n'                        ...
        '%%   %s\n'                                                 ...
        '\n'                                                        ...
        '    cfg = %s();\n'                                         ...
        '\n'                                                        ...
        '%s'                                                        ...
        'end\n'],                                                   ...
        funcName, upper(funcName), sweepId, idx, nRuns,            ...
        strjoin(summaryParts, '  '), baseFuncName, overrides);

    fid = fopen(runPath, 'w');
    if fid == -1
        error('generate_sweep:writeError', 'Cannot open for writing: %s', runPath);
    end
    cleanup = onCleanup(@() fclose(fid));  %#ok<NASGU>
    fwrite(fid, content, 'char');
end


function camel = snake2camel(s)
    parts = strsplit(s, '_');
    camel = parts{1};
    for i = 2:numel(parts)
        p = parts{i};
        if ~isempty(p)
            camel = [camel, upper(p(1)), p(2:end)]; %#ok<AGROW>
        end
    end
end


function s = value2matlab(v)
    if islogical(v) && isscalar(v)
        if v, s = 'true'; else, s = 'false'; end
    elseif ischar(v) || (isstring(v) && isscalar(v))
        s = ['"', char(v), '"'];
    elseif isnumeric(v) && isscalar(v)
        if v == floor(v) && abs(v) < 1e6
            s = sprintf('%d', v);
        else
            s = sprintf('%g', v);
        end
    else
        error('generate_sweep:renderError', ...
              'Cannot render class "%s" as a MATLAB literal.', class(v));
    end
end
