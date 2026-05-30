classdef Station < handle
    % Station — 仪器容器和采集调度中心
    %
    % 职责：
    %   - 持有所有 VisaInstrument 实例
    %   - 管理仪器连接生命周期
    %   - 提供 station 整体状态快照（用于 ELOG 和日志）
    %   - 按优先级调度批量采集
    %
    % 不负责：
    %   - UI 渲染（由 MeasurementManagerApp 负责）
    %   - 数据持久化（由 DataExporter 负责）
    %   - ELOG 上传（由 DataExporter 负责）

    properties
        PriorityOrder cell = {'OSA', 'ESA', 'VNA', 'Scope'}
    end

    properties (SetAccess = private)
        Instruments  % containers.Map: registry_key (char) → VisaInstrument
    end

    properties (Dependent)
        ConnectedCount
        TotalCount
    end

    methods
        function obj = Station()
            obj.Instruments = containers.Map();
        end

        function delete(obj)
            obj.disconnectAll();
        end

        function register(obj, key)
            % 注册仪器实例（从工厂创建但不连接）
            %
            % key — InstrumentRegistry 中的字段名，如 'keysight_n9020a_esa'
            k = char(string(key));
            if obj.Instruments.isKey(k)
                return;  % 已注册，跳过
            end
            try
                instrument = labdevices.core.Station.createInstrument(k);
            catch
                return;  % 驱动未实现等，静默跳过
            end
            if isempty(instrument)
                return;
            end
            obj.Instruments(k) = instrument;
        end

        function registerAll(obj)
            % 注册 InstrumentRegistry 中的所有仪器
            registry = labdevices.core.InstrumentRegistry.all();
            allKeys = fieldnames(registry);
            for idx = 1:numel(allKeys)
                obj.register(allKeys{idx});
            end
        end

        function remove(obj, key)
            % 断开并移除仪器
            k = char(string(key));
            if ~obj.Instruments.isKey(k)
                return;
            end
            instrument = obj.Instruments(k);
            try
                instrument.disconnect();
            catch
            end
            obj.Instruments.remove(k);
        end

        function connect(obj, key)
            % 连接指定仪器（先注册后连接）
            k = char(string(key));
            if ~obj.Instruments.isKey(k)
                obj.register(k);
            end
            instrument = obj.Instruments(k);
            if ~instrument.isConnected()
                instrument.connect();
            end
        end

        function disconnect(obj, key)
            % 断开指定仪器（不移除注册）
            k = char(string(key));
            if ~obj.Instruments.isKey(k)
                return;
            end
            instrument = obj.Instruments(k);
            if instrument.isConnected()
                instrument.disconnect();
            end
        end

        function connectAll(obj)
            % 连接所有已注册仪器
            obj.registerAll();
            allKeys = obj.Instruments.keys();
            for idx = 1:numel(allKeys)
                try
                    obj.connect(allKeys{idx});
                catch ME
                    warning("labdevices:StationConnectFailed", ...
                        "Failed to connect %s: %s", allKeys{idx}, ME.message);
                end
            end
        end

        function disconnectAll(obj)
            % 断开所有已连接仪器
            if obj.Instruments.Count == 0
                return;
            end
            allKeys = obj.Instruments.keys();
            for idx = 1:numel(allKeys)
                obj.disconnect(allKeys{idx});
            end
        end

        function tf = isConnected(obj, key)
            k = char(string(key));
            if ~obj.Instruments.isKey(k)
                tf = false;
                return;
            end
            instrument = obj.Instruments(k);
            tf = instrument.isConnected();
        end

        function instrument = getInstrument(obj, key)
            % 获取已注册的仪器实例
            k = char(string(key));
            if obj.Instruments.isKey(k)
                instrument = obj.Instruments(k);
            else
                instrument = [];
            end
        end

        function keys = connectedKeys(obj)
            % 返回所有已连接仪器的 key 列表
            keys = {};
            if obj.Instruments.Count == 0
                return;
            end
            allKeys = obj.Instruments.keys();
            for idx = 1:numel(allKeys)
                k = allKeys{idx};
                instrument = obj.Instruments(k);
                if instrument.isConnected()
                    keys{end + 1} = k; %#ok<AGROW>
                end
            end
        end

        function count = get.ConnectedCount(obj)
            count = numel(obj.connectedKeys());
        end

        function count = get.TotalCount(obj)
            count = obj.Instruments.Count;
        end

        function snapshot = getSnapshot(obj)
            % 返回当前 station 完整状态快照（struct）
            %
            % 包含每个已连接仪器的：key, displayName, type, model, idn, resourceName, timestamp
            % 用于 ELOG 上传时的仪器状态附件和调试日志
            snapshot = struct();
            snapshot.timestamp = char(datetime("now", "Format", "yyyy_MM_dd-HH_mm_ss_SSS"));
            snapshot.instruments = struct([]);

            allKeys = obj.Instruments.keys();
            for idx = 1:numel(allKeys)
                k = allKeys{idx};
                instrument = obj.Instruments(k);

                entry = struct();
                entry.key = k;
                entry.connected = instrument.isConnected();
                entry.resourceName = char(instrument.ResourceName);
                entry.name = char(instrument.Name);

                if instrument.isConnected()
                    try
                        entry.idn = instrument.idn();
                    catch
                        entry.idn = 'N/A';
                    end
                else
                    entry.idn = 'N/A';
                end

                if isempty(snapshot.instruments)
                    snapshot.instruments = entry;
                else
                    snapshot.instruments(end + 1) = entry; %#ok<AGROW>
                end
            end
        end

        function [results] = acquireAll(obj, priorityOrder, acquireParamsMap)
            % 按优先级顺序批量采集所有已连接仪器
            %
            % priorityOrder     — 可选，仪器类型优先级 cell array
            % acquireParamsMap  — 可选，containers.Map(key → acquire 参数 cell)
            %
            % 返回 containers.Map: key → data struct

            if nargin < 2 || isempty(priorityOrder)
                priorityOrder = obj.PriorityOrder;
            end
            if nargin < 3
                acquireParamsMap = containers.Map();
            end

            results = containers.Map();
            connected = obj.connectedKeys();

            % 解析每个已连接仪器的类型
            registry = labdevices.core.InstrumentRegistry.all();
            keyTypes = cell(numel(connected), 2);
            for idx = 1:numel(connected)
                k = connected{idx};
                if isfield(registry, k)
                    keyTypes(idx, :) = {k, registry.(k).type};
                else
                    keyTypes(idx, :) = {k, 'Unknown'};
                end
            end

            % 按优先级排序
            orderedKeys = {};
            for p = 1:numel(priorityOrder)
                for idx = 1:size(keyTypes, 1)
                    if strcmpi(keyTypes{idx, 2}, priorityOrder{p})
                        orderedKeys{end + 1} = keyTypes{idx, 1}; %#ok<AGROW>
                    end
                end
            end
            % 追加未匹配优先级的仪器
            for idx = 1:size(keyTypes, 1)
                if ~ismember(keyTypes{idx, 1}, orderedKeys)
                    orderedKeys{end + 1} = keyTypes{idx, 1}; %#ok<AGROW>
                end
            end

            % 顺序采集
            for idx = 1:numel(orderedKeys)
                k = orderedKeys{idx};
                try
                    instrument = obj.Instruments(k);
                    if acquireParamsMap.isKey(k)
                        args = acquireParamsMap(k);
                    else
                        args = labdevices.core.Station.defaultAcquireArgs(registry.(k).type);
                    end
                    data = instrument.acquire(args{:});
                    results(k) = data;
                catch ME
                    warning("labdevices:StationAcquireFailed", ...
                        "Failed to acquire from %s: %s", k, ME.message);
                end
            end
        end
    end

    methods (Static)
        function args = defaultAcquireArgs(instrType)
            switch upper(char(instrType))
                case 'OSA';   args = {{'TRD'}};
                case 'SCOPE'; args = {[1]};
                case 'ESA';   args = {[1]};
                case 'VNA';   args = {[1]};
                otherwise;    args = {};
            end
        end

        function instrument = createInstrument(key)
            % 工厂方法：registry key → VisaInstrument 子类实例
            %
            % 集中管理仪器类型映射。新增仪器类型时只需在此处添加一个 case。
            k = char(string(key));

            switch k
                case "keysight_n9020a_esa"
                    instrument = labdevices.esa.KeysightN9020A();
                case "ceyear_osa_6362d_white"
                    instrument = labdevices.osa.CeyearOSA6362D("white");
                case "ceyear_osa_6362d_black"
                    instrument = labdevices.osa.CeyearOSA6362D("black");
                case "keysight_e5080b_vna"
                    instrument = labdevices.vna.KeysightE5080B();
                case "siglent_sna5003x_e_vna"
                    warning("labdevices:InstrumentNotImplemented", ...
                        "No driver class exists yet for SIGLENT SNA5003X-E. Skipping.");
                    instrument = [];
                case "keysight_mso9404a_scope"
                    instrument = labdevices.scope.KeysightMSO9404A();
                case "rigol_dho4204_scope"
                    instrument = labdevices.scope.RigolDHO4204();
                otherwise
                    error("labdevices:UnknownInstrumentKey", ...
                        "No driver mapping for key: %s", k);
            end
        end
    end
end
