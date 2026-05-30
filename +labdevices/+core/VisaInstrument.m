classdef VisaInstrument < handle
    properties
        ResourceName string
        Device
        Timeout double = 10
        ReadTerminator string = "LF"
        WriteTerminator string = "LF"
        Name string = "Instrument"
    end

    methods
        function obj = VisaInstrument(resourceName)
            if nargin >= 1 && ~isempty(resourceName)
                obj.ResourceName = string(resourceName);
            else
                obj.ResourceName = "";
            end
        end

        function connect(obj)
            if obj.isConnected()
                return;
            end

            if strlength(obj.ResourceName) == 0
                error("labdevices:MissingResource", "ResourceName is empty.");
            end

            if exist('visadev', 'file') ~= 2 && exist('visadev', 'builtin') ~= 5
                error("labdevices:ToolboxMissing", ...
                    "visadev is not available. Install the Instrument Control Toolbox.");
            end

            obj.releaseExistingVisaDevice();

            try
                obj.Device = visadev(char(obj.ResourceName));
            catch ME
                if contains(string(ME.message), "Creating a second device", 'IgnoreCase', true)
                    msg = sprintf(['An existing visadev object is still holding resource %s.\n' ...
                        'Try running: delete(visadevfind(''ResourceName'',''%s'')); clear scope cleanupObj; then retry.'], ...
                        char(obj.ResourceName), char(obj.ResourceName));
                    error("labdevices:DuplicateVisaDevice", "%s", msg);
                end
                rethrow(ME);
            end
            obj.Device.Timeout = obj.Timeout;
            configureTerminator(obj.Device, char(obj.ReadTerminator), char(obj.WriteTerminator));
        end

        function disconnect(obj)
            if obj.isConnected()
                dev = obj.Device;
                obj.Device = [];
                try
                    delete(dev);
                catch
                end
            end
        end

        function tf = isConnected(obj)
            tf = ~isempty(obj.Device);
        end

        function delete(obj)
            obj.disconnect();
        end

        function out = idn(obj)
            out = strtrim(obj.query("*IDN?"));
        end

        function write(obj, command)
            obj.ensureConnected();
            writeline(obj.Device, char(command));
        end

        function out = query(obj, command)
            obj.ensureConnected();
            obj.flushAvailableBytes();
            writeline(obj.Device, char(command));
            out = strtrim(readline(obj.Device));
            % 读取后续行（如有），合并多行响应
            while obj.Device.NumBytesAvailable > 0
                nextLine = strtrim(readline(obj.Device));
                if strlength(nextLine) == 0; break; end
                out = [out, newline, nextLine]; %#ok<AGROW>
            end
        end

        function out = queryDouble(obj, command)
            out = str2double(obj.query(command));
        end

        function out = queryAsciiArray(obj, command)
            raw = obj.query(command);
            if strlength(string(raw)) == 0
                out = [];
                return;
            end

            pieces = regexp(char(raw), ',', 'split');
            out = str2double(string(strtrim(pieces)));
            out = out(~isnan(out));
        end

        function out = readBinaryBlock(obj, command, precision, byteOrder)
            if nargin < 4 || isempty(byteOrder)
                byteOrder = "little-endian";
            end

            obj.ensureConnected();
            obj.Device.ByteOrder = char(byteOrder);
            obj.flushAvailableBytes();
            writeline(obj.Device, char(command));
            out = readbinblock(obj.Device, char(precision));
            obj.flushAvailableBytes();
        end

        function waitForOperation(obj)
            obj.query("*OPC?");
        end

        function flushAvailableBytes(obj)
            if ~obj.isConnected()
                return;
            end

            try
                flush(obj.Device, "input");
            catch
                try
                    flush(obj.Device);
                catch
                end
            end
        end

        function saved = save(~, acquisition, varargin)
            saved = labdevices.core.DataExporter.saveAcquisition(acquisition, varargin{:});
        end

        function saved = saveData(obj, acquisition, varargin)
            saved = obj.save(acquisition, varargin{:});
        end
    end

    methods (Access = protected)
        function releaseExistingVisaDevice(obj)
            if exist('visadevfind', 'file') ~= 2 && exist('visadevfind', 'builtin') ~= 5
                return;
            end

            try
                existing = visadevfind('ResourceName', char(obj.ResourceName));
            catch
                try
                    existing = visadevfind();
                    if ~isempty(existing) && isprop(existing, 'ResourceName')
                        names = string(get(existing, 'ResourceName'));
                        existing = existing(names == obj.ResourceName);
                    end
                catch
                    existing = [];
                end
            end

            if isempty(existing)
                return;
            end

            try
                delete(existing);
                pause(0.1);
            catch
            end
        end

        function ensureConnected(obj)
            if ~obj.isConnected()
                error("labdevices:NotConnected", "%s is not connected.", obj.Name);
            end
        end

        function stamp = buildTimestamp(~)
            stamp = char(datetime("now", "Format", "yyyy_MM_dd-HH_mm_ss_SSS"));
        end

        function items = appendStructItem(~, items, item)
            if isempty(item)
                return;
            end

            if isempty(items)
                items = item;
                return;
            end

            itemFields = fieldnames(item);
            itemsFields = fieldnames(items);
            allFields = union(itemsFields, itemFields, 'stable');

            for idx = 1:numel(allFields)
                fieldName = allFields{idx};
                if ~isfield(items, fieldName)
                    [items.(fieldName)] = deal([]);
                end
                if ~isfield(item, fieldName)
                    item.(fieldName) = [];
                end
            end

            items = orderfields(items);
            item = orderfields(item, items);
            items(end + 1) = item;
        end
    end
end
