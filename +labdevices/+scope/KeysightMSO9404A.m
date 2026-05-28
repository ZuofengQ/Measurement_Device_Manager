classdef KeysightMSO9404A < labdevices.core.VisaInstrument
    methods
        function obj = KeysightMSO9404A(resourceName)
            if nargin < 1 || isempty(resourceName)
                resourceName = labdevices.core.InstrumentRegistry.resource("keysight_mso9404a_scope");
            end
            obj@labdevices.core.VisaInstrument(resourceName);
            obj.Name = "Keysight MSO9404A Scope";
            obj.Timeout = 20;
            obj.ReadTerminator = "LF";
            obj.WriteTerminator = "LF";
        end

        function configure(obj, varargin)
            p = inputParser();
            addParameter(p, "TimeRangeS", []);
            addParameter(p, "Points", []);
            addParameter(p, "SampleRateHz", []);
            addParameter(p, "AverageCount", []);
            addParameter(p, "ChannelDisplay", struct());
            addParameter(p, "ChannelScaleVdiv", struct());
            addParameter(p, "ChannelOffsetV", struct());
            addParameter(p, "TriggerSource", []);
            addParameter(p, "TriggerSlope", []);
            addParameter(p, "TriggerLevelV", []);
            parse(p, varargin{:});

            if ~isempty(p.Results.TimeRangeS)
                obj.write(sprintf(':TIM:RANG %.15g', p.Results.TimeRangeS));
            end
            if ~isempty(p.Results.Points)
                obj.write(sprintf(':ACQ:POIN %d', round(p.Results.Points)));
            end
            if ~isempty(p.Results.SampleRateHz)
                obj.write(sprintf(':ACQ:SRAT %.15g', p.Results.SampleRateHz));
            end
            if ~isempty(p.Results.AverageCount)
                if p.Results.AverageCount > 1
                    obj.write(':ACQ:AVER ON');
                    obj.write(sprintf(':ACQ:AVER:COUN %d', round(p.Results.AverageCount)));
                else
                    obj.write(':ACQ:AVER OFF');
                end
            end
            obj.applyPerChannelNumericSetting(p.Results.ChannelDisplay, ...
                @(ch, val) sprintf(':CHANnel%d:DISPlay %d', ch, logical(val)));
            obj.applyPerChannelNumericSetting(p.Results.ChannelScaleVdiv, ...
                @(ch, val) sprintf(':CHANnel%d:SCALe %.15g', ch, val));
            obj.applyPerChannelNumericSetting(p.Results.ChannelOffsetV, ...
                @(ch, val) sprintf(':CHANnel%d:OFFSet %.15g', ch, val));
            if ~isempty(p.Results.TriggerSource)
                obj.write(sprintf(':TRIG:EDGE:SOUR %s', char(string(p.Results.TriggerSource))));
            end
            if ~isempty(p.Results.TriggerSlope)
                obj.write(sprintf(':TRIG:EDGE:SLOP %s', char(string(p.Results.TriggerSlope))));
            end
            if ~isempty(p.Results.TriggerLevelV)
                obj.write(sprintf(':TRIG:LEV %.15g', p.Results.TriggerLevelV));
            end
        end

        function data = acquire(obj, channels, varargin)
            if nargin < 2 || isempty(channels)
                channels = 1;
            end

            p = inputParser();
            addParameter(p, "Fresh", true);
            parse(p, varargin{:});

            channels = unique(channels(:).');
            channels = channels(channels >= 1 & channels <= 4);
            if isempty(channels)
                error("labdevices:InvalidChannel", "No valid scope channels were requested.");
            end

            runState = strtrim(obj.query(':RSTATE?'));
            wasRunning = strcmpi(runState, 'RUN');

            obj.write(':STOP');
            obj.write(':SYSTEM:HEADER OFF');

            if p.Results.Fresh
                digitizeList = join("CHANNEL" + string(channels), ',');
                obj.write(sprintf(':DIGITIZE %s', char(digitizeList)));
                obj.waitForOperation();
                obj.write(':STOP');
            end

            npoints = round(obj.queryDouble(':WAVEFORM:POINTS?'));
            srate = obj.queryDouble(':ACQUIRE:SRATE?');
            span = obj.queryDouble(':TIMEBASE:RANGE?');

            traces = struct([]);

            for idx = 1:numel(channels)
                channel = channels(idx);
                channelName = sprintf('CHANNEL%d', channel);

                obj.write(sprintf(':WAVEFORM:SOURCE %s', channelName));
                preamble = obj.parseWaveformPreamble(obj.query(':WAVEFORM:PREAMBLE?'));

                obj.Device.ByteOrder = "little-endian";
                obj.write(':WAVEFORM:FORMAT WORD');
                obj.write(':WAVEFORM:BYTEORDER LSBFirst');
                raw = obj.readBinaryBlock(':WAVEFORM:DATA?', 'int16', 'little-endian');
                if isempty(raw)
                    continue;
                end

                x = preamble.xOrigin + ((0:numel(raw)-1).' - preamble.xReference) * preamble.xIncrement;
                y = (double(raw(:)) - preamble.yReference) * preamble.yIncrement + preamble.yOrigin;

                trace = struct();
                trace.name = channelName;
                trace.index = channel;
                trace.x = x;
                trace.y = y;
                trace.raw = raw(:);
                trace.displayState = obj.safeQueryDouble(sprintf(':STAT? %s', channelName), NaN);
                trace.detector = strtrim(obj.query(':ACQUIRE:MODE?'));
                trace.scale = preamble.yIncrement * 2^16;
                trace.offset = preamble.yOrigin;
                trace.xIncrement = preamble.xIncrement;
                trace.xOrigin = preamble.xOrigin;
                trace.xReference = preamble.xReference;
                trace.yIncrement = preamble.yIncrement;
                trace.yOrigin = preamble.yOrigin;
                trace.yReference = preamble.yReference;

                inputMode = strtrim(obj.query(sprintf(':%s:INPUT?', channelName)));
                if strcmpi(inputMode, 'DC50')
                    trace.coupling = '50 Ohm';
                elseif strcmpi(inputMode, 'DC')
                    trace.coupling = '1000 Ohm';
                else
                    trace.coupling = inputMode;
                end

                if strcmp(strtrim(obj.query(':ACQUIRE:AVERAGE?')), '1')
                    trace.navg = round(obj.queryDouble(':ACQUIRE:AVERAGE:COUNT?'));
                else
                    trace.navg = 1;
                end

                traces = obj.appendStructItem(traces, trace);
            end

            data = struct();
            data.device = 'MSO9404A';
            data.model = 'Keysight MSO9404A';
            data.type = 'Scope';
            data.resourceName = char(obj.ResourceName);
            data.idn = obj.idn();
            data.timestamp = obj.buildTimestamp();
            data.npoints = npoints;
            data.srate = srate;
            data.res = 1 / srate;
            data.span = span;
            data.xunit = 's';
            data.yunit = 'V';
            data.traces = traces;

            if wasRunning
                obj.write(':RUN');
            end
        end
    end

    methods (Access = private)
        function preamble = parseWaveformPreamble(~, preambleRaw)
            values = textscan(char(string(preambleRaw)), '%q', 'Delimiter', ',');
            values = values{1};
            if numel(values) < 10
                error("labdevices:InvalidPreamble", ...
                    "Unexpected Keysight waveform preamble: %s", char(string(preambleRaw)));
            end

            preamble = struct();
            preamble.format = str2double(values{1});
            preamble.type = str2double(values{2});
            preamble.points = str2double(values{3});
            preamble.count = str2double(values{4});
            preamble.xIncrement = str2double(values{5});
            preamble.xOrigin = str2double(values{6});
            preamble.xReference = str2double(values{7});
            preamble.yIncrement = str2double(values{8});
            preamble.yOrigin = str2double(values{9});
            preamble.yReference = str2double(values{10});
        end

        function applyPerChannelNumericSetting(obj, valueStruct, commandFactory)
            if isempty(valueStruct) || ~isstruct(valueStruct)
                return;
            end

            fields = fieldnames(valueStruct);
            for idx = 1:numel(fields)
                fieldName = fields{idx};
                channel = obj.parseChannelFieldName(fieldName);
                if isnan(channel)
                    continue;
                end
                value = valueStruct.(fieldName);
                obj.write(commandFactory(channel, value));
            end
        end

        function channel = parseChannelFieldName(~, fieldName)
            token = regexp(lower(fieldName), '^ch(?:annel)?(\d+)$', 'tokens', 'once');
            if isempty(token)
                channel = NaN;
            else
                channel = str2double(token{1});
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
    end
end
