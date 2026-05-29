classdef DataExporter
    methods (Static)
        function saved = saveAcquisition(data, varargin)
            p = inputParser();
            addParameter(p, "Folder", pwd);
            addParameter(p, "BaseName", "");
            addParameter(p, "Formats", {"mat"});
            addParameter(p, "UploadToElog", false);
            addParameter(p, "ElogParams", struct());
            parse(p, varargin{:});

            folder = string(p.Results.Folder);
            baseName = string(p.Results.BaseName);
            formats = p.Results.Formats;
            uploadToElog = logical(p.Results.UploadToElog);
            elogParams = p.Results.ElogParams;
            useAutoBaseName = strlength(baseName) == 0;

            if ischar(formats) || isstring(formats)
                formats = cellstr(string(formats));
            end

            if useAutoBaseName
                baseName = labdevices.core.DataExporter.defaultBaseName(data);
                baseName = labdevices.core.DataExporter.makeUniqueBaseName(folder, baseName);
            end

            baseName = labdevices.core.DataExporter.sanitizeFilename(baseName);

            if ~isfolder(folder)
                mkdir(folder);
            end

            saved = struct();
            saved.folder = char(folder);
            saved.baseName = char(baseName);
            saved.formats = formats;

            lowerFormats = lower(string(formats));

            if any(lowerFormats == "mat")
                matPath = fullfile(folder, baseName + ".mat");
                save(matPath, "data", "-v7.3");
                saved.mat = char(matPath);
            end

            if any(lowerFormats == "csv")
                csvFiles = labdevices.core.DataExporter.writeCsvFiles(data, folder, baseName);
                saved.csv = csvFiles;
            end

            if any(lowerFormats == "png")
                try
                    pngPath = labdevices.core.DataExporter.writePngFile(data, folder, baseName);
                    saved.png = char(pngPath);
                catch ME
                    if strcmp(ME.identifier, "labdevices:NoPlotData")
                        warning("labdevices:NoPlotData", ...
                            "Skipping PNG export because no plottable x/y data was found.");
                    else
                        rethrow(ME);
                    end
                end
            end

            if uploadToElog
                % Build ELOG upload options from saved data
                opts = struct();
                opts.Type = 'AutoSave';

                if isfield(data, 'device')
                    opts.Measurement = char(labdevices.core.DataExporter.pickField(data, 'device', ''));
                end
                if isfield(data, 'idn')
                    opts.Sample = char(strtrim(string(data.idn)));
                end

                % Merge user-provided ElogParams (overrides auto-detected)
                if ~isempty(elogParams)
                    userFields = fieldnames(elogParams);
                    for i = 1:numel(userFields)
                        opts.(userFields{i}) = elogParams.(userFields{i});
                    end
                end

                % Attach a compact snapshot (from data header, no need for Station here)
                if isfield(data, 'device') && isfield(data, 'type')
                    opts.Snapshot = struct();
                    opts.Snapshot.timestamp = char(labdevices.core.DataExporter.pickField( ...
                        data, 'timestamp', ''));
                    opts.Snapshot.instruments = struct( ...
                        'key', '', ...
                        'connected', true, ...
                        'resourceName', char(labdevices.core.DataExporter.pickField( ...
                            data, 'resourceName', '')), ...
                        'name', char(labdevices.core.DataExporter.pickField( ...
                            data, 'device', '')), ...
                        'idn', char(labdevices.core.DataExporter.pickField( ...
                            data, 'idn', 'N/A')));
                end

                % Attach the saved plot PNG (only PNG, no MAT/CSV)
                if isfield(saved, 'png') && ~isempty(saved.png)
                    if ~isfield(opts, 'Attachments') || isempty(opts.Attachments)
                        opts.Attachments = {char(saved.png)};
                    else
                        opts.Attachments = [opts.Attachments, {char(saved.png)}];
                    end
                end

                % Attempt upload (non-blocking via try/catch)
                try
                    [uploadOk, uploadResp] = ...
                        labdevices.core.DataExporter.uploadToElog(opts);
                    if ~uploadOk
                        warning("labdevices:ElogUploadFailed", ...
                            "ELOG upload failed: %s", uploadResp);
                    end
                catch ME
                    warning("labdevices:ElogUploadFailed", ...
                        "ELOG upload error: %s", ME.message);
                end
            end
        end

        function csvFiles = writeCsvFiles(data, folder, baseName)
            csvFiles = {};

            metaTable = labdevices.core.DataExporter.buildMetadataTable(data);
            if ~isempty(metaTable)
                metaPath = fullfile(folder, baseName + "_metadata.csv");
                writetable(metaTable, metaPath);
                csvFiles{end + 1} = char(metaPath); %#ok<AGROW>
            end

            if ~isfield(data, "traces") || isempty(data.traces)
                return;
            end

            for idx = 1:numel(data.traces)
                trace = data.traces(idx);
                traceTable = labdevices.core.DataExporter.buildTraceTable(trace);
                if isempty(traceTable)
                    continue;
                end

                traceLabel = "trace_" + idx;
                if isfield(trace, "name") && strlength(string(trace.name)) > 0
                    traceLabel = "trace_" + idx + "_" + string(trace.name);
                end

                tracePath = fullfile(folder, baseName + "_" + ...
                    labdevices.core.DataExporter.sanitizeFilename(traceLabel) + ".csv");
                writetable(traceTable, tracePath);
                csvFiles{end + 1} = char(tracePath); %#ok<AGROW>
            end
        end

        function pngPath = writePngFile(data, folder, baseName)
            fig = figure("Visible", "off");
            cleanup = onCleanup(@() close(fig));

            plotted = labdevices.core.DataExporter.plotAcquisition(data);
            if ~plotted
                error("labdevices:NoPlotData", "No plottable x/y data found for PNG export.");
            end

            pngPath = fullfile(folder, baseName + ".png");
            exportgraphics(fig, pngPath, "Resolution", 200);
        end

        function plotted = plotAcquisition(data)
            plotted = false;

            if ~isfield(data, "traces") || isempty(data.traces)
                return;
            end

            trace = data.traces(1);
            [x, y, yLabel] = labdevices.core.DataExporter.pickPlotVectors(trace);
            if isempty(x) || isempty(y)
                return;
            end

            plot(x, y, "LineWidth", 1.0);
            grid on;
            xlabel(labdevices.core.DataExporter.pickField(data, "xunit", "x"));
            ylabel(yLabel);
            title(labdevices.core.DataExporter.pickField(data, "device", "Acquisition"));
            plotted = true;
        end

        function T = buildMetadataTable(data)
            rows = cell(0, 2);
            fieldNames = fieldnames(data);
            for idx = 1:numel(fieldNames)
                name = fieldNames{idx};
                if strcmp(name, "traces")
                    continue;
                end

                value = data.(name);
                if isnumeric(value) && isscalar(value)
                    rows(end + 1, :) = {char(name), char(string(value))}; %#ok<AGROW>
                elseif isstring(value) || ischar(value)
                    rows(end + 1, :) = {char(name), char(string(value))}; %#ok<AGROW>
                elseif islogical(value) && isscalar(value)
                    rows(end + 1, :) = {char(name), mat2str(value)}; %#ok<AGROW>
                end
            end

            if isempty(rows)
                T = table();
            else
                T = cell2table(rows, 'VariableNames', {'Field', 'Value'});
            end
        end

        function T = buildTraceTable(trace)
            columns = {};
            names = {};
            candidates = {'x', 'y', 'yLog', 'yLin', 'phase', 'real', 'raw'};

            for idx = 1:numel(candidates)
                fieldName = candidates{idx};
                if ~isfield(trace, fieldName)
                    continue;
                end

                value = trace.(fieldName);
                if isnumeric(value) && isvector(value)
                    columns{end + 1} = value(:); %#ok<AGROW>
                    names{end + 1} = fieldName; %#ok<AGROW>
                end
            end

            if isempty(columns)
                T = table();
                return;
            end

            % Truncate all columns to the minimum common length
            minLen = min(cellfun(@numel, columns));
            for idx = 1:numel(columns)
                columns{idx} = columns{idx}(1:minLen);
            end

            T = table(columns{:}, 'VariableNames', names);
        end

        function [x, y, yLabel] = pickPlotVectors(trace)
            x = [];
            y = [];
            yLabel = "y";

            if isfield(trace, "x") && isnumeric(trace.x) && isvector(trace.x)
                x = trace.x(:);
            end

            yCandidates = {'y', 'yLog', 'yLin', 'phase', 'real'};
            for idx = 1:numel(yCandidates)
                fieldName = yCandidates{idx};
                if isfield(trace, fieldName) && isnumeric(trace.(fieldName)) && isvector(trace.(fieldName))
                    y = trace.(fieldName)(:);
                    yLabel = string(fieldName);
                    break;
                end
            end

            if isempty(x) && ~isempty(y)
                x = (1:numel(y)).';
            end
        end

        function out = pickField(data, fieldName, fallback)
            if isfield(data, fieldName) && ~isempty(data.(fieldName))
                out = char(string(data.(fieldName)));
            else
                out = fallback;
            end
        end

        function baseName = defaultBaseName(data)
            device = string(labdevices.core.DataExporter.pickField(data, "device", "acquisition"));
            timestamp = labdevices.core.DataExporter.defaultFilenameTimestamp(data);
            baseName = device + "_" + timestamp;
            baseName = labdevices.core.DataExporter.sanitizeFilename(baseName);
        end

        function timestamp = defaultFilenameTimestamp(data)
            rawTimestamp = string(labdevices.core.DataExporter.pickField(data, "timestamp", ""));

            if strlength(rawTimestamp) > 0
                try
                    dt = datetime(rawTimestamp, "InputFormat", "yyyy_MM_dd-HH_mm_ss_SSS");
                    timestamp = string(dt, "yyyy_MM_dd-HH_mm");
                    return;
                catch
                end
            end

            timestamp = string(datetime("now", "Format", "yyyy_MM_dd-HH_mm"));
        end

        function baseName = makeUniqueBaseName(folder, baseName)
            baseName = string(baseName);
            folder = char(string(folder));
            if ~labdevices.core.DataExporter.baseNameExists(folder, baseName)
                return;
            end

            suffix = 1;
            while true
                candidate = sprintf('%s_%02d', char(baseName), suffix);
                if ~labdevices.core.DataExporter.baseNameExists(folder, candidate)
                    baseName = string(candidate);
                    return;
                end
                suffix = suffix + 1;
            end
        end

        function tf = baseNameExists(folder, baseName)
            pattern = fullfile(folder, [char(string(baseName)) '*']);
            tf = ~isempty(dir(pattern));
        end

        function name = sanitizeFilename(name)
            name = regexprep(char(string(name)), '[<>:"/\\|?* ]+', '_');
            name = regexprep(name, '_+', '_');
            name = string(strip(name, "_"));
            if strlength(name) == 0
                name = "acquisition";
            end
        end

        function [success, response] = uploadToElog(opts)
            % 通过 HTTP POST 上传 ELOG 条目
            %
            % opts 结构体字段:
            %   .Server      - 主机名（默认 'lpqm1srv2.epfl.ch'）
            %   .Port        - 端口号（默认 8081）
            %   .Logbook     - 日志本名称（必填）
            %   .Author      - 作者（必填）
            %   .Sample      - 样品标识
            %   .Measurement - 测量类型
            %   .Type        - 条目类型（默认 'ManualSave'）
            %   .Comments    - 评注文本
            %   .Snapshot    - 仪器状态快照 struct（可选）
            %   .Attachment  - 附件文件路径（可选）
            %
            % 返回:
            %   success  - HTTP 2xx 则为 true
            %   response - 服务器响应体字符串

            if nargin < 1; opts = struct(); end
            if ~isfield(opts, 'Server') || isempty(opts.Server); opts.Server = '192.168.1.72'; end
            if ~isfield(opts, 'Port') || isempty(opts.Port); opts.Port = 8080; end
            if ~isfield(opts, 'Logbook'); opts.Logbook = ''; end
            if ~isfield(opts, 'Author'); opts.Author = ''; end
            if ~isfield(opts, 'Sample'); opts.Sample = ''; end
            if ~isfield(opts, 'Measurement'); opts.Measurement = ''; end
            if ~isfield(opts, 'Type') || isempty(opts.Type); opts.Type = 'ManualSave'; end
            if ~isfield(opts, 'Comments'); opts.Comments = ''; end
            if ~isfield(opts, 'Snapshot'); opts.Snapshot = struct(); end
            if ~isfield(opts, 'Attachment'); opts.Attachment = {}; end
            if ~isfield(opts, 'Attachments'); opts.Attachments = {}; end
            if ~isfield(opts, 'Executable'); opts.Executable = ''; end
            if ~isfield(opts, 'AdditionalAttributes'); opts.AdditionalAttributes = struct(); end
            opts.Server = char(string(opts.Server));
            opts.Logbook = char(string(opts.Logbook));
            opts.Author = char(string(opts.Author));
            opts.Sample = char(string(opts.Sample));
            opts.Measurement = char(string(opts.Measurement));
            opts.Type = char(string(opts.Type));
            opts.Comments = char(string(opts.Comments));
            opts.Executable = char(string(opts.Executable));

            % Validate required fields
            if isempty(strtrim(opts.Logbook))
                error("labdevices:ElogMissingLogbook", ...
                    "ELOG upload requires a Logbook name.");
            end
            if isempty(strtrim(opts.Author))
                error("labdevices:ElogMissingAuthor", ...
                    "ELOG upload requires an Author.");
            end

            executable = labdevices.core.DataExporter.resolveElogExecutable(opts.Executable);
            textBody = labdevices.core.DataExporter.composeElogBody(opts.Comments, opts.Snapshot);
            attachments = labdevices.core.DataExporter.normalizeElogAttachments( ...
                opts.Attachment, opts.Attachments);

            if contains(executable, '\') || contains(executable, '/') || contains(executable, ':')
                commandParts = {labdevices.core.DataExporter.quoteElogArg(executable)};
            else
                commandParts = {executable};
            end
            commandParts{end + 1} = ['-h ', ...
                labdevices.core.DataExporter.quoteElogArg(strtrim(opts.Server))];
            commandParts{end + 1} = ['-p ', ...
                labdevices.core.DataExporter.quoteElogArg(num2str(round(opts.Port)))];
            commandParts{end + 1} = ['-l ', ...
                labdevices.core.DataExporter.quoteElogArg(strtrim(opts.Logbook))];

            attributePairs = {
                'Author', opts.Author;
                'Sample', opts.Sample;
                'Measurement', opts.Measurement;
                'Type', opts.Type
                };

            extraFields = fieldnames(opts.AdditionalAttributes);
            for idx = 1:numel(extraFields)
                attributePairs(end + 1, :) = { ...
                    extraFields{idx}, opts.AdditionalAttributes.(extraFields{idx})}; %#ok<AGROW>
            end

            for idx = 1:size(attributePairs, 1)
                attrName = strtrim(char(string(attributePairs{idx, 1})));
                attrValue = strtrim(char(string(attributePairs{idx, 2})));
                if isempty(attrName) || isempty(attrValue)
                    continue;
                end
                commandParts{end + 1} = ['-a ', ...
                    labdevices.core.DataExporter.quoteElogArg( ...
                    sprintf('%s=%s', attrName, attrValue))]; %#ok<AGROW>
            end

            for idx = 1:numel(attachments)
                commandParts{end + 1} = ['-f ', ...
                    labdevices.core.DataExporter.quoteElogArg(attachments{idx})]; %#ok<AGROW>
            end

            commandParts{end + 1} = labdevices.core.DataExporter.quoteElogArg(textBody);
            command = strjoin(commandParts, ' ');

            [status, cmdout] = system(command);
            response = char(string(cmdout));
            responseLower = lower(strtrim(response));
            success = status == 0 && (isempty(responseLower) || ...
                contains(responseLower, 'successful') || ...
                contains(responseLower, 'id='));

            if ~success
                response = sprintf('CMD: %s\nOUT: %s', command, response);
            end
        end

        function text = escapeElogText(text)
            text = char(string(text));
            text = strrep(text, '"', '''');
            text = regexprep(text, '\r\n|\r|\n', '\\n');
        end

        function body = composeElogBody(comments, snapshot)
            sections = {};
            commentText = strtrim(char(string(comments)));
            if ~isempty(commentText)
                sections{end + 1} = labdevices.core.DataExporter.escapeElogText(commentText); %#ok<AGROW>
            end

            snapshotText = labdevices.core.DataExporter.formatElogSnapshot(snapshot);
            if ~isempty(snapshotText)
                sections{end + 1} = snapshotText; %#ok<AGROW>
            end

            if isempty(sections)
                body = ' ';
            else
                body = strjoin(sections, '\n\n');
            end
        end

        function text = formatElogSnapshot(snapshot)
            if isempty(snapshot) || ~isstruct(snapshot) || isempty(fieldnames(snapshot))
                text = '';
                return;
            end

            lines = {'--- Instrument Snapshot ---'};
            if isfield(snapshot, 'timestamp') && ~isempty(snapshot.timestamp)
                lines{end + 1} = ['Timestamp: ', char(string(snapshot.timestamp))]; %#ok<AGROW>
            end

            if isfield(snapshot, 'instruments') && ~isempty(snapshot.instruments)
                for idx = 1:numel(snapshot.instruments)
                    inst = snapshot.instruments(idx);
                    connStr = 'No';
                    if isfield(inst, 'connected') && inst.connected
                        connStr = 'Yes';
                    end

                    keyStr = '';
                    nameStr = '';
                    idnStr = 'N/A';
                    resStr = '';
                    if isfield(inst, 'key'); keyStr = char(string(inst.key)); end
                    if isfield(inst, 'name'); nameStr = char(string(inst.name)); end
                    if isfield(inst, 'idn'); idnStr = char(string(inst.idn)); end
                    if isfield(inst, 'resourceName')
                        resStr = char(string(inst.resourceName));
                    end

                    lines{end + 1} = sprintf('[%s] %s | %s | IDN: %s | Resource: %s', ...
                        connStr, keyStr, nameStr, idnStr, resStr); %#ok<AGROW>
                end
            end

            lines{end + 1} = '--- End Snapshot ---';
            escaped = cellfun(@labdevices.core.DataExporter.escapeElogText, ...
                lines, 'UniformOutput', false);
            text = strjoin(escaped, '\n');
        end

        function attachments = normalizeElogAttachments(primary, secondary)
            attachments = {};
            rawItems = {};

            if nargin >= 1 && ~isempty(primary)
                rawItems = [rawItems, labdevices.core.DataExporter.toCellstr(primary)]; %#ok<AGROW>
            end
            if nargin >= 2 && ~isempty(secondary)
                rawItems = [rawItems, labdevices.core.DataExporter.toCellstr(secondary)]; %#ok<AGROW>
            end

            for idx = 1:numel(rawItems)
                filePath = char(string(rawItems{idx}));
                if ~isempty(filePath) && isfile(filePath)
                    attachments{end + 1} = filePath; %#ok<AGROW>
                end
            end

            if ~isempty(attachments)
                attachments = unique(attachments, 'stable');
            end
        end

        function items = toCellstr(value)
            if isempty(value)
                items = {};
            elseif iscell(value)
                items = cellstr(string(value));
            elseif isstring(value)
                items = cellstr(value(:));
            else
                items = {char(string(value))};
            end
        end

        function executable = resolveElogExecutable(preferred)
            candidates = {};
            preferred = strtrim(char(string(preferred)));
            if ~isempty(preferred)
                candidates{end + 1} = preferred; %#ok<AGROW>
            end
            candidates{end + 1} = 'D:\Program Files (x86)\ELOG\elog.exe'; %#ok<AGROW>
            candidates{end + 1} = 'E:\Program Files (x86)\ELOG\elog.exe'; %#ok<AGROW>
            candidates{end + 1} = 'C:\Program Files (x86)\ELOG\elog.exe'; %#ok<AGROW>
            candidates{end + 1} = 'C:\Program Files\ELOG\elog.exe'; %#ok<AGROW>

            executable = 'elog';
            for idx = 1:numel(candidates)
                if isfile(candidates{idx})
                    executable = candidates{idx};
                    return;
                end
            end
        end

        function out = quoteElogArg(value)
            value = char(string(value));
            value = strrep(value, '"', '''');
            out = ['"', value, '"'];
        end
    end
end
