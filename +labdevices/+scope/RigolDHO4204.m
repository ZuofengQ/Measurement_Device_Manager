classdef RigolDHO4204 < labdevices.core.VisaInstrument
    properties
        ScreenDivisions double = 10
        MaxSampleRateHz double = 4e9
        MaxMemoryDepthPoints double = 500e6
        DefaultChunkPoints double = 1e6
        PreparedCapture struct = struct()
    end

    methods
        function obj = RigolDHO4204(resourceName)
            if nargin < 1 || isempty(resourceName)
                resourceName = labdevices.core.InstrumentRegistry.resource("rigol_dho4204_scope");
            end
            obj@labdevices.core.VisaInstrument(resourceName);
            obj.Name = "Rigol DHO4204 Scope";
            obj.Timeout = 30;
            obj.ReadTerminator = "LF";
            obj.WriteTerminator = "LF";
        end

        function configure(obj, varargin)
            p = inputParser();
            addParameter(p, "TimebaseScaleSdiv", []);
            addParameter(p, "TimebaseOffsetS", []);
            addParameter(p, "ChannelDisplay", struct());
            addParameter(p, "ChannelScaleVdiv", struct());
            addParameter(p, "ChannelOffsetV", struct());
            addParameter(p, "ChannelCoupling", struct());
            addParameter(p, "TriggerMode", []);
            addParameter(p, "TriggerSource", []);
            addParameter(p, "TriggerSlope", []);
            addParameter(p, "TriggerLevelV", []);
            addParameter(p, "SampleRateHz", []);
            addParameter(p, "TotalTimeS", []);
            addParameter(p, "MemoryDepth", []);
            addParameter(p, "AcquisitionType", "NORMAL");
            parse(p, varargin{:});

            if ~isempty(p.Results.TimebaseScaleSdiv)
                obj.write(sprintf(':TIMebase:MAIN:SCALe %.15g', p.Results.TimebaseScaleSdiv));
            end
            if ~isempty(p.Results.TimebaseOffsetS)
                obj.write(sprintf(':TIMebase:MAIN:OFFSet %.15g', p.Results.TimebaseOffsetS));
            end
            if ~isempty(p.Results.TriggerMode)
                obj.write(sprintf(':TRIGger:MODE %s', char(string(p.Results.TriggerMode))));
            end
            if ~isempty(p.Results.TriggerSource)
                obj.write(sprintf(':TRIGger:EDGE:SOURce %s', char(string(p.Results.TriggerSource))));
            end
            if ~isempty(p.Results.TriggerSlope)
                obj.write(sprintf(':TRIGger:EDGE:SLOPe %s', char(string(p.Results.TriggerSlope))));
            end
            if ~isempty(p.Results.TriggerLevelV)
                obj.write(sprintf(':TRIGger:EDGE:LEVel %.15g', p.Results.TriggerLevelV));
            end

            obj.applyPerChannelNumericSetting(p.Results.ChannelDisplay, ...
                @(ch, val) sprintf(':CHANnel%d:DISPlay %d', ch, logical(val)));
            obj.applyPerChannelNumericSetting(p.Results.ChannelScaleVdiv, ...
                @(ch, val) sprintf(':CHANnel%d:SCALe %.15g', ch, val));
            obj.applyPerChannelNumericSetting(p.Results.ChannelOffsetV, ...
                @(ch, val) sprintf(':CHANnel%d:OFFSet %.15g', ch, val));
            obj.applyPerChannelStringSetting(p.Results.ChannelCoupling, ...
                @(ch, val) sprintf(':CHANnel%d:COUPling %s', ch, char(string(val))));

            if ~isempty(p.Results.SampleRateHz) || ~isempty(p.Results.TotalTimeS) || ~isempty(p.Results.MemoryDepth)
                obj.configureLongCapture( ...
                    p.Results.TotalTimeS, ...
                    p.Results.SampleRateHz, ...
                    'MemoryDepth', p.Results.MemoryDepth, ...
                    'AcquisitionType', p.Results.AcquisitionType);
            end
        end

        function settings = configureLongCapture(obj, totalTimeS, sampleRateHz, varargin)
            p = inputParser();
            addParameter(p, "MemoryDepth", []);
            addParameter(p, "AcquisitionType", "NORMAL");
            addParameter(p, "StopAfterConfigure", true);
            parse(p, varargin{:});

            if isempty(totalTimeS) || isempty(sampleRateHz)
                error("labdevices:InvalidLongCapture", ...
                    "configureLongCapture requires TotalTimeS and SampleRateHz.");
            end

            totalTimeS = double(totalTimeS);
            sampleRateHz = min(double(sampleRateHz), obj.MaxSampleRateHz);
            requestedPoints = max(1, round(totalTimeS * sampleRateHz));

            if isempty(p.Results.MemoryDepth)
                targetDepth = obj.chooseMemoryDepth(requestedPoints);
            else
                targetDepth = min(double(p.Results.MemoryDepth), obj.MaxMemoryDepthPoints);
            end

            obj.write(':RUN');
            pause(0.2);

            obj.write(sprintf(':ACQuire:TYPE %s', upper(char(string(p.Results.AcquisitionType)))));
            obj.write(sprintf(':TIMebase:MAIN:SCALe %.15g', totalTimeS / obj.ScreenDivisions));
            obj.write(sprintf(':ACQuire:MDEPth %d', round(targetDepth)));
            obj.write(':TIMebase:MAIN:OFFSet 0');

            if targetDepth >= 100e6
                pause(2.0);
            elseif targetDepth >= 10e6
                pause(1.0);
            else
                pause(0.5);
            end

            actualScale = obj.safeQueryDouble(':TIMebase:MAIN:SCALe?', totalTimeS / obj.ScreenDivisions);
            actualTime = actualScale * obj.ScreenDivisions;
            actualSampleRate = obj.safeQueryDouble(':ACQuire:SRATe?', sampleRateHz);
            actualDepthStr = strtrim(obj.query(':ACQuire:MDEPth?'));
            actualDepth = str2double(actualDepthStr);
            if strcmpi(actualDepthStr, 'AUTO') || isnan(actualDepth)
                actualDepth = targetDepth;
            end

            if p.Results.StopAfterConfigure
                obj.write(':STOP');
                pause(0.2);
            end

            settings = struct();
            settings.requestedTotalTimeS = totalTimeS;
            settings.requestedSampleRateHz = sampleRateHz;
            settings.requestedPoints = requestedPoints;
            settings.memoryDepth = actualDepth;
            settings.totalTimeS = actualTime;
            settings.sampleRateHz = actualSampleRate;
            settings.timebaseScaleSdiv = actualScale;
            settings.acquisitionType = upper(char(string(p.Results.AcquisitionType)));
        end

        function settings = prepareCapture(obj, channels, sampleRateHz, totalTimeS, varargin)
            p = inputParser();
            addParameter(p, "ChannelScaleVdiv", struct());
            addParameter(p, "ChannelOffsetV", struct());
            addParameter(p, "ChannelCoupling", struct());
            addParameter(p, "TriggerMode", []);
            addParameter(p, "TriggerSource", []);
            addParameter(p, "TriggerSlope", []);
            addParameter(p, "TriggerLevelV", []);
            addParameter(p, "MemoryDepth", []);
            addParameter(p, "AcquisitionType", "NORMAL");
            parse(p, varargin{:});

            channels = obj.normalizeChannels(channels);
            obj.applyChannelSelection(channels);

            obj.applyPerChannelNumericSetting(p.Results.ChannelScaleVdiv, ...
                @(ch, val) sprintf(':CHANnel%d:SCALe %.15g', ch, val));
            obj.applyPerChannelNumericSetting(p.Results.ChannelOffsetV, ...
                @(ch, val) sprintf(':CHANnel%d:OFFSet %.15g', ch, val));
            obj.applyPerChannelStringSetting(p.Results.ChannelCoupling, ...
                @(ch, val) sprintf(':CHANnel%d:COUPling %s', ch, char(string(val))));

            if ~isempty(p.Results.TriggerMode)
                obj.write(sprintf(':TRIGger:MODE %s', char(string(p.Results.TriggerMode))));
            end
            if ~isempty(p.Results.TriggerSource)
                obj.write(sprintf(':TRIGger:EDGE:SOURce %s', char(string(p.Results.TriggerSource))));
            end
            if ~isempty(p.Results.TriggerSlope)
                obj.write(sprintf(':TRIGger:EDGE:SLOPe %s', char(string(p.Results.TriggerSlope))));
            end
            if ~isempty(p.Results.TriggerLevelV)
                obj.write(sprintf(':TRIGger:EDGE:LEVel %.15g', p.Results.TriggerLevelV));
            end

            settings = obj.configureLongCapture(totalTimeS, sampleRateHz, ...
                'MemoryDepth', p.Results.MemoryDepth, ...
                'AcquisitionType', p.Results.AcquisitionType);

            obj.PreparedCapture = struct( ...
                'channels', channels, ...
                'settings', settings);
        end

        function runCapture(obj)
            obj.write(':RUN');
        end

        function data = stopAndReadCapture(obj, channels, varargin)
            if nargin < 2 || isempty(channels)
                if isfield(obj.PreparedCapture, 'channels')
                    channels = obj.PreparedCapture.channels;
                else
                    channels = 1;
                end
            end

            obj.stop();
            pause(0.2);
            data = obj.acquireDeepMemory(channels, 'AssumeStopped', true, varargin{:});
        end

        function data = acquireTimed(obj, channels, sampleRateHz, totalTimeS, varargin)
            p = inputParser();
            addParameter(p, "ChannelScaleVdiv", struct());
            addParameter(p, "ChannelOffsetV", struct());
            addParameter(p, "ChannelCoupling", struct());
            addParameter(p, "TriggerMode", []);
            addParameter(p, "TriggerSource", []);
            addParameter(p, "TriggerSlope", []);
            addParameter(p, "TriggerLevelV", []);
            addParameter(p, "MemoryDepth", []);
            addParameter(p, "AcquisitionType", "NORMAL");
            addParameter(p, "WaitMarginS", 0.5);
            addParameter(p, "MaxPoints", []);
            addParameter(p, "ChunkPoints", obj.DefaultChunkPoints);
            parse(p, varargin{:});

            settings = obj.prepareCapture(channels, sampleRateHz, totalTimeS, ...
                'ChannelScaleVdiv', p.Results.ChannelScaleVdiv, ...
                'ChannelOffsetV', p.Results.ChannelOffsetV, ...
                'ChannelCoupling', p.Results.ChannelCoupling, ...
                'TriggerMode', p.Results.TriggerMode, ...
                'TriggerSource', p.Results.TriggerSource, ...
                'TriggerSlope', p.Results.TriggerSlope, ...
                'TriggerLevelV', p.Results.TriggerLevelV, ...
                'MemoryDepth', p.Results.MemoryDepth, ...
                'AcquisitionType', p.Results.AcquisitionType);

            obj.runCapture();
            pause(settings.totalTimeS + p.Results.WaitMarginS);
            data = obj.stopAndReadCapture(channels, ...
                'MaxPoints', p.Results.MaxPoints, ...
                'ChunkPoints', p.Results.ChunkPoints);
        end

        function data = acquire(obj, channels, varargin)
            if nargin < 2 || isempty(channels)
                channels = 1;
            end

            p = inputParser();
            addParameter(p, "Mode", "NORM");
            addParameter(p, "NumPoints", []);
            addParameter(p, "StopBeforeRead", []);
            addParameter(p, "ChunkPoints", obj.DefaultChunkPoints);
            parse(p, varargin{:});

            mode = upper(char(string(p.Results.Mode)));
            stopBeforeRead = p.Results.StopBeforeRead;
            if isempty(stopBeforeRead)
                stopBeforeRead = strcmpi(mode, 'RAW');
            end

            if strcmpi(mode, 'RAW')
                data = obj.acquireDeepMemory(channels, ...
                    'MaxPoints', p.Results.NumPoints, ...
                    'ChunkPoints', p.Results.ChunkPoints, ...
                    'AssumeStopped', ~stopBeforeRead);
                return;
            end

            channels = obj.normalizeChannels(channels);
            if stopBeforeRead
                obj.stop();
            end

            traces = struct([]);

            for idx = 1:numel(channels)
                channel = channels(idx);
                if round(obj.safeQueryDouble(sprintf(':CHANnel%d:DISPlay?', channel), 1)) == 0
                    continue;
                end

                trace = obj.readScreenWaveform(channel);
                traces = obj.appendStructItem(traces, trace);
            end

            data = struct();
            data.device = 'DHO4204';
            data.model = 'Rigol DHO4204';
            data.type = 'Scope';
            data.resourceName = char(obj.ResourceName);
            data.idn = obj.idn();
            data.timestamp = obj.buildTimestamp();
            data.mode = 'NORM';
            data.timebaseScale = obj.safeQueryDouble(':TIMebase:MAIN:SCALe?', NaN);
            data.timebaseOffset = obj.safeQueryDouble(':TIMebase:MAIN:OFFSet?', NaN);
            data.xunit = 's';
            data.yunit = 'V';
            data.traces = traces;
        end

        function data = acquireDeepMemory(obj, channels, varargin)
            p = inputParser();
            addParameter(p, "MaxPoints", []);
            addParameter(p, "ChunkPoints", obj.DefaultChunkPoints);
            addParameter(p, "AssumeStopped", false);
            parse(p, varargin{:});

            channels = obj.normalizeChannels(channels);
            if ~p.Results.AssumeStopped
                obj.stop();
                pause(0.2);
            end

            traces = struct([]);
            sampleRateHz = NaN;
            totalTimeS = NaN;

            for idx = 1:numel(channels)
                channel = channels(idx);
                if round(obj.safeQueryDouble(sprintf(':CHANnel%d:DISPlay?', channel), 1)) == 0
                    continue;
                end

                trace = obj.readDeepMemoryWaveform(channel, p.Results.MaxPoints, p.Results.ChunkPoints);
                traces = obj.appendStructItem(traces, trace);

                if isnan(sampleRateHz) && isfield(trace, 'sampleRateHz')
                    sampleRateHz = trace.sampleRateHz;
                end
                if isnan(totalTimeS) && isfield(trace, 'captureTimeS')
                    totalTimeS = trace.captureTimeS;
                end
            end

            data = struct();
            data.device = 'DHO4204';
            data.model = 'Rigol DHO4204';
            data.type = 'Scope';
            data.resourceName = char(obj.ResourceName);
            data.idn = obj.idn();
            data.timestamp = obj.buildTimestamp();
            data.mode = 'RAW';
            data.sampleRateHz = sampleRateHz;
            data.captureTimeS = totalTimeS;
            data.timebaseScale = obj.safeQueryDouble(':TIMebase:MAIN:SCALe?', NaN);
            data.timebaseOffset = obj.safeQueryDouble(':TIMebase:MAIN:OFFSet?', NaN);
            data.memoryDepth = obj.safeQueryDouble(':ACQuire:MDEPth?', NaN);
            data.xunit = 's';
            data.yunit = 'V';
            data.traces = traces;
        end

        function run(obj)
            obj.write(':RUN');
        end

        function stop(obj)
            obj.write(':STOP');
        end

        function clearWaveforms(obj)
            obj.write(':CLEar');
        end
    end

    methods (Access = private)
        function trace = readScreenWaveform(obj, channel)
            obj.write(sprintf(':WAV:SOUR CHAN%d', channel));
            obj.write(':WAV:MODE NORM');
            obj.write(':WAV:FORM BYTE');

            yRef = obj.safeQueryDouble(':WAV:YREF?', 0);
            yOrigin = obj.safeQueryDouble(':WAV:YOR?', 0);
            yIncrement = obj.safeQueryDouble(':WAV:YINC?', 1);
            xIncrement = obj.safeQueryDouble(':WAV:XINC?', 1);
            xOrigin = obj.safeQueryDouble(':WAV:XOR?', 0);

            raw = obj.readBinaryBlock(':WAV:DATA?', 'uint8', 'little-endian');
            x = xOrigin + (0:numel(raw)-1).' * xIncrement;
            y = (double(raw(:)) - yOrigin - yRef) * yIncrement;

            trace = struct();
            trace.name = sprintf('CHAN%d', channel);
            trace.index = channel;
            trace.x = x;
            trace.y = y;
            trace.raw = raw(:);
            trace.mode = 'NORM';
            trace.yRef = yRef;
            trace.yOrigin = yOrigin;
            trace.yIncrement = yIncrement;
            trace.xIncrement = xIncrement;
            trace.xOrigin = xOrigin;
            trace.verticalScale = obj.safeQueryDouble(sprintf(':CHANnel%d:SCALe?', channel), NaN);
        end

        function trace = readDeepMemoryWaveform(obj, channel, maxPoints, chunkPoints)
            obj.write(sprintf(':WAVeform:SOURce CHAN%d', channel));
            obj.write(':WAVeform:MODE RAW');
            obj.write(':WAVeform:FORMat WORD');
            obj.write(':WAVeform:STARt 1');
            obj.write(':WAVeform:STOP 1000');
            pause(0.2);

            preamble = obj.parsePreamble(obj.query(':WAVeform:PREamble?'));
            totalPoints = preamble.points;
            if ~isempty(maxPoints)
                totalPoints = min(totalPoints, round(maxPoints));
            end

            chunkPoints = max(1, round(chunkPoints));
            y = zeros(totalPoints, 1);
            writeIndex = 1;

            for startPoint = 1:chunkPoints:totalPoints
                stopPoint = min(startPoint + chunkPoints - 1, totalPoints);
                obj.write(sprintf(':WAVeform:STARt %d', startPoint));
                obj.write(sprintf(':WAVeform:STOP %d', stopPoint));
                rawChunk = obj.readBinaryBlock(':WAVeform:DATA?', 'uint16', 'little-endian');

                rawDouble = double(rawChunk(:));
                yChunk = (rawDouble - preamble.yReference) .* preamble.yIncrement + preamble.yOrigin;
                nextIndex = writeIndex + numel(yChunk) - 1;
                y(writeIndex:nextIndex) = yChunk;
                writeIndex = nextIndex + 1;
            end

            y = y(1:writeIndex - 1);
            x = preamble.xOrigin + ((0:numel(y)-1).' - preamble.xReference) * preamble.xIncrement;

            trace = struct();
            trace.name = sprintf('CHAN%d', channel);
            trace.index = channel;
            trace.x = x;
            trace.y = y;
            trace.mode = 'RAW';
            trace.sampleRateHz = 1 / preamble.xIncrement;
            trace.captureTimeS = numel(y) * preamble.xIncrement;
            trace.totalPoints = numel(y);
            trace.xIncrement = preamble.xIncrement;
            trace.xOrigin = preamble.xOrigin;
            trace.xReference = preamble.xReference;
            trace.yIncrement = preamble.yIncrement;
            trace.yOrigin = preamble.yOrigin;
            trace.yReference = preamble.yReference;
            trace.verticalScale = obj.safeQueryDouble(sprintf(':CHANnel%d:SCALe?', channel), NaN);
        end

        function preamble = parsePreamble(~, preambleRaw)
            values = str2double(strsplit(char(string(preambleRaw)), ','));
            if numel(values) < 10
                error("labdevices:InvalidPreamble", ...
                    "Unexpected Rigol preamble: %s", char(string(preambleRaw)));
            end

            preamble = struct();
            preamble.format = values(1);
            preamble.type = values(2);
            preamble.points = values(3);
            preamble.count = values(4);
            preamble.xIncrement = values(5);
            preamble.xOrigin = values(6);
            preamble.xReference = values(7);
            preamble.yIncrement = values(8);
            preamble.yOrigin = values(9);
            preamble.yReference = values(10);
        end

        function depth = chooseMemoryDepth(obj, requestedPoints)
            validDepths = [1e3, 10e3, 100e3, 1e6, 10e6, 25e6, 50e6, ...
                100e6, 125e6, 200e6, 250e6, 500e6];
            validDepths = validDepths(validDepths <= obj.MaxMemoryDepthPoints);
            idx = find(validDepths >= requestedPoints, 1, 'first');
            if isempty(idx)
                depth = validDepths(end);
            else
                depth = validDepths(idx);
            end
        end

        function channels = normalizeChannels(~, channels)
            channels = unique(channels(:).');
            channels = channels(channels >= 1 & channels <= 4);
            if isempty(channels)
                error("labdevices:InvalidChannel", "No valid Rigol scope channels were requested.");
            end
        end

        function applyChannelSelection(obj, channels)
            for channel = 1:4
                if ismember(channel, channels)
                    obj.write(sprintf(':CHANnel%d:DISPlay ON', channel));
                else
                    obj.write(sprintf(':CHANnel%d:DISPlay OFF', channel));
                end
            end
        end

        function out = safeQueryDouble(obj, command, fallback)
            try
                out = obj.queryDouble(command);
                if isnan(out)
                    out = fallback;
                end
            catch
                out = fallback;
            end
        end

        function applyPerChannelNumericSetting(obj, valueStruct, formatter)
            if isempty(valueStruct) || ~isstruct(valueStruct)
                return;
            end

            fieldNames = fieldnames(valueStruct);
            for idx = 1:numel(fieldNames)
                fieldName = fieldNames{idx};
                channel = obj.parseChannelField(fieldName);
                if isnan(channel)
                    continue;
                end
                value = valueStruct.(fieldName);
                obj.write(formatter(channel, value));
            end
        end

        function applyPerChannelStringSetting(obj, valueStruct, formatter)
            if isempty(valueStruct) || ~isstruct(valueStruct)
                return;
            end

            fieldNames = fieldnames(valueStruct);
            for idx = 1:numel(fieldNames)
                fieldName = fieldNames{idx};
                channel = obj.parseChannelField(fieldName);
                if isnan(channel)
                    continue;
                end
                value = valueStruct.(fieldName);
                obj.write(formatter(channel, value));
            end
        end

        function channel = parseChannelField(~, fieldName)
            match = regexp(fieldName, '\d+', 'match', 'once');
            if isempty(match)
                channel = NaN;
            else
                channel = str2double(match);
            end
        end
    end
end
