classdef CeyearOSA6362D < labdevices.core.VisaInstrument
    methods
        function obj = CeyearOSA6362D(resourceNameOrAlias)
            if nargin < 1 || isempty(resourceNameOrAlias)
                resourceNameOrAlias = "black";
            end

            [resourceName, displayName] = labdevices.osa.CeyearOSA6362D.resolveResource(resourceNameOrAlias);

            obj@labdevices.core.VisaInstrument(resourceName);
            obj.Name = displayName;
            obj.Timeout = 15;
            obj.ReadTerminator = "CR/LF";
            obj.WriteTerminator = "LF";
        end

        function connect(obj)
            connect@labdevices.core.VisaInstrument(obj);
            try
                obj.query('OPEN "anonymous"');
            catch
            end
            try
                obj.query(':FORM?');
            catch
            end
        end

        function configure(obj, varargin)
            p = inputParser();
            addParameter(p, "CenterWavelengthNm", []);
            addParameter(p, "SpanNm", []);
            addParameter(p, "ResolutionNm", []);
            addParameter(p, "SweepMode", []);
            parse(p, varargin{:});

            if ~isempty(p.Results.CenterWavelengthNm)
                obj.write(sprintf(':SENS:WAV:CENT %.15g', p.Results.CenterWavelengthNm * 1e-9));
            end
            if ~isempty(p.Results.SpanNm)
                obj.write(sprintf(':SENS:WAV:SPAN %.15g', p.Results.SpanNm * 1e-9));
            end
            if ~isempty(p.Results.ResolutionNm)
                obj.write(sprintf(':SENS:BAND %.15g', p.Results.ResolutionNm * 1e-9));
            end
            if ~isempty(p.Results.SweepMode)
                obj.write(sprintf(':INIT:SMODE %s', char(string(p.Results.SweepMode))));
            end
        end

        function data = acquire(obj, traceNames, varargin)
            if nargin < 2 || isempty(traceNames)
                traceNames = {'TRD'};
            end

            p = inputParser();
            addParameter(p, "Fresh", true);
            addParameter(p, "FinalSweepMode", 0);
            parse(p, varargin{:});

            if p.Results.Fresh
                obj.write(':INIT:SMODE SING');
                obj.write(':INIT');
                obj.write('*WAI');
            end

            modeNames = {'WRITE', 'FIX', 'MAX', 'MIN', 'RAVG', 'CALC'};
            traces = struct([]);
            for idx = 1:numel(traceNames)
                traceName = char(traceNames{idx});
                y = obj.queryAsciiArray(sprintf(':TRACE:Y? %s', traceName));
                x = obj.queryAsciiArray(sprintf(':TRACE:X? %s', traceName)) * 1e9;

                modeIndex = round(obj.queryDouble(sprintf(':TRAC:ATTR:%s?', traceName))) + 1;
                modeIndex = max(1, min(modeIndex, numel(modeNames)));

                trace = struct();
                trace.name = traceName;
                trace.x = x(:);
                trace.y = y(:);
                trace.mode = modeNames{modeIndex};
                trace.navg = round(obj.queryDouble(sprintf(':TRAC:ATTR:RAVG:%s?', traceName)));
                trace.npoints = numel(x);
                traces = obj.appendStructItem(traces, trace);
            end

            data = struct();
            data.device = 'OSA6362D';
            data.model = 'Ceyear OSA6362D';
            data.type = 'OSA';
            data.resourceName = char(obj.ResourceName);
            data.idn = obj.idn();
            data.timestamp = obj.buildTimestamp();
            data.res = obj.queryDouble(':SENS:BAND?') * 1e9;
            data.cf = obj.queryDouble(':SENS:WAV:CENT?') * 1e9;
            data.span = obj.queryDouble(':SENS:WAV:SPAN?') * 1e9;
            data.xunit = 'nm';
            data.yunit = 'dBm';
            data.traces = traces;

            if p.Results.Fresh
                obj.write(sprintf(':INIT:SMODE %d', p.Results.FinalSweepMode));
            end
        end

        function stop(obj)
            obj.write(':ABORt');
        end
    end

    methods (Static)
        function obj = whiteUnit()
            obj = labdevices.osa.CeyearOSA6362D("white");
        end

        function obj = blackUnit()
            obj = labdevices.osa.CeyearOSA6362D("black");
        end
    end

    methods (Access = private, Static)
        function [resourceName, displayName] = resolveResource(resourceNameOrAlias)
            alias = lower(string(resourceNameOrAlias));

            if contains(alias, "::")
                resourceName = string(resourceNameOrAlias);
                displayName = "Ceyear OSA6362D";
                return;
            end

            switch alias
                case {"1", "unit1", "osa1", "white", "white_osa", "6362d_white", "osa_white", "ceyear_osa_6362d_white"}
                    entry = labdevices.core.InstrumentRegistry.get("ceyear_osa_6362d_white");
                case {"2", "unit2", "osa2", "black", "black_osa", "6362d_black", "osa_black", "ceyear_osa_6362d_black"}
                    entry = labdevices.core.InstrumentRegistry.get("ceyear_osa_6362d_black");
                otherwise
                    error("labdevices:UnknownOsaAlias", ...
                        "Unknown Ceyear OSA alias: %s", char(alias));
            end

            resourceName = string(entry.resourceName);
            displayName = string(entry.displayName);
        end
    end
end
