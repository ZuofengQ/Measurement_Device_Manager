classdef KeysightN9020A < labdevices.core.VisaInstrument
    methods
        function obj = KeysightN9020A(resourceName)
            if nargin < 1 || isempty(resourceName)
                resourceName = labdevices.core.InstrumentRegistry.resource("keysight_n9020a_esa");
            end
            obj@labdevices.core.VisaInstrument(resourceName);
            obj.Name = "Keysight N9020A ESA";
            obj.Timeout = 10;
            obj.ReadTerminator = "LF";
            obj.WriteTerminator = "LF";
        end

        function configure(obj, varargin)
            p = inputParser();
            addParameter(p, "CenterFrequencyHz", []);
            addParameter(p, "SpanHz", []);
            addParameter(p, "ResolutionBandwidthHz", []);
            addParameter(p, "VideoBandwidthHz", []);
            addParameter(p, "Points", []);
            addParameter(p, "Continuous", []);
            parse(p, varargin{:});

            if ~isempty(p.Results.CenterFrequencyHz)
                obj.write(sprintf('SENS:FREQ:CENT %.15g', p.Results.CenterFrequencyHz));
            end
            if ~isempty(p.Results.SpanHz)
                obj.write(sprintf('SENS:FREQ:SPAN %.15g', p.Results.SpanHz));
            end
            if ~isempty(p.Results.ResolutionBandwidthHz)
                obj.write(sprintf('BAND %.15g', p.Results.ResolutionBandwidthHz));
            end
            if ~isempty(p.Results.VideoBandwidthHz)
                obj.write(sprintf('BAND:VID %.15g', p.Results.VideoBandwidthHz));
            end
            if ~isempty(p.Results.Points)
                obj.write(sprintf('SENS:SWE:POIN %d', round(p.Results.Points)));
            end
            if ~isempty(p.Results.Continuous)
                obj.write(sprintf('INIT:CONT %d', logical(p.Results.Continuous)));
            end
        end

        function data = acquire(obj, traceNumbers, varargin)
            if nargin < 2 || isempty(traceNumbers)
                traceNumbers = 1;
            end

            p = inputParser();
            addParameter(p, "Fresh", true);
            parse(p, varargin{:});

            traceNumbers = traceNumbers(traceNumbers >= 1 & traceNumbers <= 6);
            if isempty(traceNumbers)
                error("labdevices:InvalidTrace", "No valid ESA trace numbers were requested.");
            end

            contState = NaN;
            obj.write('FORM:TRACE:DATA ASCII');

            if p.Results.Fresh
                contState = round(obj.queryDouble('INIT:CONT?'));
                obj.write('INIT:CONT OFF');
                obj.write('INIT:IMM; *WAI');
            end

            % 无论成功或失败都恢复仪器状态
            c = onCleanup(@() obj.restoreContState(contState));

            traces = struct([]);
            for idx = 1:numel(traceNumbers)
                traceNumber = traceNumbers(idx);
                samples = obj.queryAsciiArray(sprintf('FETC:SAN%d?', traceNumber));
                trace = struct();
                trace.name = sprintf('TRACE%d', traceNumber);
                trace.index = traceNumber;
                trace.x = samples(1:2:end).';
                trace.y = samples(2:2:end).';
                trace.mode = strtrim(obj.query(sprintf('TRACE%d:TYPE?', traceNumber)));
                trace.detector = strtrim(obj.query(sprintf('SENS:DET:TRACE%d?', traceNumber)));
                trace.navg = 1;
                if strcmpi(trace.mode, 'AVER')
                    trace.navg = round(obj.queryDouble('SENS:AVER:COUN?'));
                    trace.avgType = strtrim(obj.query('SENS:AVER:TYPE?'));
                end
                traces = obj.appendStructItem(traces, trace);
                obj.waitForOperation();
            end

            data = struct();
            data.device = 'N9020A';
            data.model = 'Keysight N9020A';
            data.type = 'ESA';
            data.resourceName = char(obj.ResourceName);
            data.idn = obj.idn();
            data.timestamp = obj.buildTimestamp();
            data.res = obj.queryDouble('BAND?');
            data.vbw = obj.queryDouble('BAND:VID?');
            data.cf = obj.queryDouble('SENS:FREQ:CENT?');
            data.span = obj.queryDouble('SENS:FREQ:SPAN?');
            data.npoints = round(obj.queryDouble('SENS:SWE:POIN?'));
            data.sweeptime = obj.queryDouble('SWE:TIME?');
            data.yscale = strtrim(obj.query('DISP:WIND:TRAC:Y:SPAC?'));
            data.xunit = 'Hz';
            data.yunit = strtrim(obj.query('UNIT:POW?'));
            data.traces = traces;
        end

        function restoreContState(obj, contState)
            if contState == 1
                try; obj.write('INIT:CONT ON'); catch; end
            end
        end
    end
end
