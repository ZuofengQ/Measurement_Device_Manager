classdef KeysightE5080B < labdevices.core.VisaInstrument
    methods
        function obj = KeysightE5080B(resourceName)
            if nargin < 1 || isempty(resourceName)
                resourceName = labdevices.core.InstrumentRegistry.resource("keysight_e5080b_vna");
            end
            obj@labdevices.core.VisaInstrument(resourceName);
            obj.Name = "Keysight E5080B VNA";
            obj.Timeout = 15;
            obj.ReadTerminator = "LF";
            obj.WriteTerminator = "LF";
        end

        function configure(obj, varargin)
            p = inputParser();
            addParameter(p, "StartFrequencyHz", []);
            addParameter(p, "StopFrequencyHz", []);
            addParameter(p, "CenterFrequencyHz", []);
            addParameter(p, "SpanHz", []);
            addParameter(p, "PowerdBm", []);
            addParameter(p, "Points", []);
            addParameter(p, "ResolutionBandwidthHz", []);
            addParameter(p, "Continuous", []);
            parse(p, varargin{:});

            if ~isempty(p.Results.StartFrequencyHz)
                obj.write(sprintf('SENS:FREQ:STAR %.15g', p.Results.StartFrequencyHz));
            end
            if ~isempty(p.Results.StopFrequencyHz)
                obj.write(sprintf('SENS:FREQ:STOP %.15g', p.Results.StopFrequencyHz));
            end
            if ~isempty(p.Results.CenterFrequencyHz)
                obj.write(sprintf('SENS:FREQ:CENT %.15g', p.Results.CenterFrequencyHz));
            end
            if ~isempty(p.Results.SpanHz)
                obj.write(sprintf('SENS:FREQ:SPAN %.15g', p.Results.SpanHz));
            end
            if ~isempty(p.Results.PowerdBm)
                obj.write(sprintf('SOUR:POW %.15g', p.Results.PowerdBm));
            end
            if ~isempty(p.Results.Points)
                obj.write(sprintf('SENS:SWE:POIN %d', round(p.Results.Points)));
            end
            if ~isempty(p.Results.ResolutionBandwidthHz)
                obj.write(sprintf('SENS:BAND:RES %.15g', p.Results.ResolutionBandwidthHz));
            end
            if ~isempty(p.Results.Continuous)
                obj.write(sprintf('INIT:CONT %d', logical(p.Results.Continuous)));
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
            contState = NaN;
            if p.Results.Fresh
                contState = round(obj.queryDouble('INIT:CONT?'));
                obj.write('INIT:CONT OFF');
                obj.write('*WAI');
            end

            c = onCleanup(@() obj.restoreContState(contState));

            obj.write('FORM ASCII');
            traces = struct([]);

            for idx = 1:numel(channels)
                channel = channels(idx);
                [measurementName, measurementMode] = obj.getFirstMeasurement(channel);
                if strlength(measurementName) == 0
                    continue;
                end

                currentSelection = obj.safeQuery(sprintf('CALC%d:PAR:SEL?', channel), "");
                currentSelection = erase(string(currentSelection), '"');
                if currentSelection ~= measurementName
                    try
                        obj.write(sprintf('CALC%d:PAR:SEL ''%s''', channel, char(measurementName)));
                    catch
                    end
                end
                calcFormat = strtrim(obj.query('CALC:FORM?'));

                trace = struct();
                trace.name = sprintf('CHAN%d', channel);
                trace.index = channel;

                obj.write('CALC:FORM MLINEAR');
                obj.write('*WAI');
                trace.yLin = obj.queryAsciiArray('CALC:DATA? FDATA').';

                obj.write('CALC:FORM MLOG');
                obj.write('*WAI');
                trace.yLog = obj.queryAsciiArray('CALC:DATA? FDATA').';

                obj.write('CALC:FORM PHAS');
                obj.write('*WAI');
                trace.phase = obj.queryAsciiArray('CALC:DATA? FDATA').';

                obj.write('CALC:FORM REAL');
                obj.write('*WAI');
                trace.real = obj.queryAsciiArray('CALC:DATA? FDATA').';

                obj.write(sprintf('CALC:FORM %s', calcFormat));

                trace.x = obj.queryAsciiArray(sprintf('SENS%d:X?', channel)).';
                trace.mode = char(measurementMode);
                trace.rbw = obj.queryDouble(sprintf('SENS%d:BAND:RES?', channel));
                trace.npoints = round(obj.queryDouble(sprintf('SENS%d:SWE:POIN?', channel)));
                trace.powerdBm = obj.queryDouble(sprintf('SOUR%d:POW?', channel));
                trace.sweeptime = obj.queryDouble(sprintf('SENS%d:SWE:TIME?', channel));

                avgEnabled = round(obj.queryDouble(sprintf('SENS%d:AVER?', channel)));
                if avgEnabled
                    trace.navg = round(obj.queryDouble(sprintf('SENS%d:AVER:COUN?', channel)));
                    trace.avgType = strtrim(obj.query(sprintf('SENS%d:AVER:MODE?', channel)));
                else
                    trace.navg = 1;
                end

                traces = obj.appendStructItem(traces, trace);
            end

            data = struct();
            data.device = 'E5080B';
            data.model = 'Keysight E5080B';
            data.type = 'VNA';
            data.resourceName = char(obj.ResourceName);
            data.idn = obj.idn();
            data.timestamp = obj.buildTimestamp();
            data.xunit = 'Hz';
            data.yunit = 'varies';
            data.traces = traces;
        end

        function restoreContState(obj, contState)
            if contState == 1
                try; obj.write('INIT:CONT ON'); catch; end
            end
        end
    end

    methods (Access = private)
        function out = safeQuery(obj, command, fallback)
            try
                out = obj.query(command);
                if strlength(string(out)) == 0
                    out = fallback;
                end
            catch
                out = fallback;
            end
        end

        function [measurementName, measurementMode] = getFirstMeasurement(obj, channel)
            measurementName = "";
            measurementMode = "";

            try
                rawCatalog = obj.query(sprintf('CALC%d:PAR:CAT?', channel));
            catch
                return;
            end

            tokens = regexp(char(rawCatalog), '"?([^",]+),([^",]+)"?', 'tokens', 'once');
            if isempty(tokens)
                return;
            end

            measurementName = string(tokens{1});
            measurementMode = string(tokens{2});
        end
    end
end
