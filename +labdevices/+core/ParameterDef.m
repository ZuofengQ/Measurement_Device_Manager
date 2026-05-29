classdef ParameterDef
    % ParameterDef — 仪器参数元数据定义
    %
    % 每种仪器类型有一组预定义的参数，描述其名称、标签、类型、默认值、可选值、单位。
    % UI 层读取这些定义后动态创建对应的输入控件。

    properties
        Name    string
        Label   string
        Type    string
        Default
        Choices
        Unit    string
        Tooltip string
    end

    methods
        function obj = ParameterDef(name, label, type, default, choices, unit, tooltip)
            if nargin == 0; return; end
            obj.Name    = string(name);
            obj.Label   = string(label);
            obj.Type    = string(type);
            obj.Default = default;
            obj.Choices = {};
            if nargin >= 5 && ~isempty(choices); obj.Choices = string(choices); end
            obj.Unit = "";
            if nargin >= 6 && ~isempty(unit); obj.Unit = string(unit); end
            obj.Tooltip = "";
            if nargin >= 7 && ~isempty(tooltip); obj.Tooltip = string(tooltip); end
        end
    end

    methods (Static)
        function params = forType(instrumentType)
            persistent cache;
            if isempty(cache); cache = containers.Map(); end
            key = char(upper(instrumentType));
            if cache.isKey(key); params = cache(key); return; end

            switch key
                case "ESA"
                    params = labdevices.core.ParameterDef.makeEsaDefaults();
                case "OSA"
                    params = labdevices.core.ParameterDef.makeOsaDefaults();
                case "VNA"
                    params = labdevices.core.ParameterDef.makeVnaDefaults();
                case "SCOPE"
                    params = labdevices.core.ParameterDef.makeScopeDefaults();
                otherwise
                    params = labdevices.core.ParameterDef.empty();
            end
            cache(key) = params;
        end

        function names = parameterNames(instrumentType)
            params = labdevices.core.ParameterDef.forType(instrumentType);
            if isempty(params)
                names = {};
            else
                names = cellstr([params.Name]);
            end
        end

        function params = makeEsaDefaults()
            P = @(varargin) labdevices.core.ParameterDef(varargin{:});
            params = [
                P("CenterFrequencyHz", "Center Frequency", "numeric", 1e9, {}, "Hz", "Center frequency in Hz")
                P("SpanHz", "Span", "numeric", 1e6, {}, "Hz", "Frequency span in Hz")
                P("ResolutionBandwidthHz", "Resolution BW", "choice", 1e3, {"1","3","10","30","100","300","1000","3000","10000","30000","100000","1000000"}, "Hz", "Resolution bandwidth")
                P("VideoBandwidthHz", "Video BW", "choice", 1e3, {"1","3","10","30","100","300","1000","3000","10000","30000","100000","1000000"}, "Hz", "Video bandwidth")
                P("Points", "Sweep Points", "numeric", 1001, {}, "", "Number of sweep points")
                P("Continuous", "Continuous Sweep", "logical", true, {}, "", "Continuous sweep mode")
                P("TraceNumbers", "Trace Numbers", "choice", "1", {"1","2","3","1,2","1,2,3"}, "", "Trace numbers to acquire")
            ];
        end

        function params = makeOsaDefaults()
            P = @(varargin) labdevices.core.ParameterDef(varargin{:});
            params = [
                P("CenterWavelengthNm", "Center Wavelength", "numeric", 1550, {}, "nm", "Center wavelength in nm")
                P("SpanNm", "Span", "numeric", 100, {}, "nm", "Wavelength span in nm")
                P("ResolutionNm", "Resolution", "choice", 0.02, {"0.01","0.02","0.05","0.1","0.2","0.5","1.0","2.0"}, "nm", "Resolution bandwidth")
                P("SweepMode", "Sweep Mode", "choice", "SING", {"SING","REP","AUTO"}, "", "Sweep mode")
                P("Trace", "Acquire Trace", "choice", "TRD", {"TRD","TRA","TRB","TRC"}, "", "Trace memory slot to acquire")
            ];
        end

        function params = makeVnaDefaults()
            P = @(varargin) labdevices.core.ParameterDef(varargin{:});
            params = [
                P("StartFrequencyHz", "Start Frequency", "numeric", 10e6, {}, "Hz", "Start frequency in Hz")
                P("StopFrequencyHz", "Stop Frequency", "numeric", 20e9, {}, "Hz", "Stop frequency in Hz")
                P("CenterFrequencyHz", "Center Frequency", "numeric", 10e9, {}, "Hz", "Center frequency")
                P("SpanHz", "Span", "numeric", 20e9, {}, "Hz", "Frequency span")
                P("PowerdBm", "Output Power", "numeric", -10, {}, "dBm", "RF output power")
                P("Points", "Sweep Points", "numeric", 201, {}, "", "Number of sweep points")
                P("ResolutionBandwidthHz", "IF Bandwidth", "choice", 1e4, {"10","30","100","300","1000","3000","10000","30000","100000"}, "Hz", "IF bandwidth")
                P("Continuous", "Continuous Sweep", "logical", false, {}, "", "Continuous sweep mode")
                P("Channels", "Channels", "choice", "1", {"1","2","3","4","1,2","1,2,3","1,2,3,4"}, "", "Channels to acquire")
            ];
        end

        function params = makeScopeDefaults()
            P = @(varargin) labdevices.core.ParameterDef(varargin{:});
            params = [
                P("TimeRangeS", "Time Range", "numeric", 1e-6, {}, "s", "Horizontal time range")
                P("Points", "Acquisition Points", "numeric", 1000, {}, "", "Number of points")
                P("SampleRateHz", "Sample Rate", "numeric", 1e9, {}, "Hz", "Sample rate")
                P("AverageCount", "Averaging", "numeric", 1, {}, "", "Number of averages")
                P("TriggerSource", "Trigger Source", "choice", "CHANNEL1", {"CHANNEL1","CHANNEL2","CHANNEL3","CHANNEL4","EXT","LINE"}, "", "Trigger source")
                P("TriggerSlope", "Trigger Slope", "choice", "POS", {"POS","NEG"}, "", "Trigger edge slope")
                P("TriggerLevelV", "Trigger Level", "numeric", 0.0, {}, "V", "Trigger level in volts")
                P("Channels", "Channels", "choice", "1", {"1","2","3","4","1,2","1,2,3","1,2,3,4","2,3","3,4"}, "", "Channels to acquire")
            ];
        end
    end
end
