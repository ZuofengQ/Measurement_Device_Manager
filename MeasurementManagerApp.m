classdef MeasurementManagerApp < handle
    % MeasurementManagerApp — 测量设备管理器 GUI
    %
    % 基于 uifigure + uigridlayout 的程序化 App Designer 界面，
    % 用于统一管理所有仪器的连接/断开、数据采集/存储，以及 ELOG 上传。
    % 支持多仪器同屏显示、通道/trace 选择、合并保存。

    %% ======================== 公共接口 ========================
    methods (Access = public)
        function obj = MeasurementManagerApp(configPath)
            if nargin < 1 || isempty(configPath)
                configPath = fullfile(fileparts(mfilename('fullpath')), 'app_config.mat');
            end
            obj.ConfigPath = configPath;
            obj.Config = obj.loadConfig(configPath);
            obj.Station = labdevices.core.Station();
            obj.AcquireParamsMap = containers.Map();
            obj.PlotAxesMap = containers.Map();

            obj.createComponents();
            obj.populateInstrumentRows();
            obj.updateStatusLamps();
            obj.updateStatusBar();
            obj.logMessage("App initialized. Ready.", "info");
        end

        function delete(obj)
            try; obj.saveConfig(); catch; end
            try; obj.Station.disconnectAll(); catch; end
            try; if isvalid(obj.Figure); delete(obj.Figure); end; catch; end
        end
    end

    %% ======================== 属性 ========================
    properties (Access = private)
        % --- 核心对象 ---
        Station     labdevices.core.Station
        Config      struct
        ConfigPath  string

        % --- UI 根 ---
        Figure      matlab.ui.Figure
        MainGrid    matlab.ui.container.GridLayout
        TabGroup    matlab.ui.container.TabGroup

        % --- 仪器表格 ---
        InstrumentKeys      string
        StatusLamps         matlab.ui.control.Lamp
        InstrumentTable     matlab.ui.control.Table

        % --- 参数面板 ---
        ParamGrid           matlab.ui.container.GridLayout
        ParamControls       struct
        SelectedKey         string

        % --- 采集数据 ---
        AcquisitionTable    matlab.ui.control.Table
        AcquisitionStore    cell
        PlotTileLayout
        PlotAxesMap         containers.Map
        AcquireParamsMap    containers.Map

        % --- 存储面板 ---
        FolderEdit          matlab.ui.control.EditField
        MatCheck            matlab.ui.control.CheckBox
        CsvCheck            matlab.ui.control.CheckBox
        PngCheck            matlab.ui.control.CheckBox
        AutoSaveCheck       matlab.ui.control.CheckBox

        % --- ELOG 面板 ---
        ServerEdit          matlab.ui.control.EditField
        PortEdit            matlab.ui.control.NumericEditField
        LogbookDrop         matlab.ui.control.DropDown
        AuthorDrop          matlab.ui.control.DropDown
        SampleEdit          matlab.ui.control.EditField
        MeasurementEdit     matlab.ui.control.EditField
        CommentsArea        matlab.ui.control.TextArea
        NoteEdit            matlab.ui.control.EditField
        AttachSnapshotCheck matlab.ui.control.CheckBox
        ElogStatusLabel     matlab.ui.control.Label

        % --- 状态栏 & 日志 ---
        StatusLabel         matlab.ui.control.Label
        LogArea             matlab.ui.control.TextArea

        % --- 采集状态 ---
        IsBusy              logical = false
    end

    %% ======================== UI 构建 ========================
    methods (Access = private)
        function createComponents(obj)
            obj.Figure = uifigure( ...
                'Name', 'Measurement Device Manager', ...
                'NumberTitle', 'off', ...
                'Position', [100, 100, 1400, 850], ...
                'CloseRequestFcn', @(~,~) obj.onFigureClose(), ...
                'Resize', 'on');

            obj.MainGrid = uigridlayout(obj.Figure, [3, 2]);
            obj.MainGrid.RowHeight = {'1.8x', '1.2x', 20};
            obj.MainGrid.ColumnWidth = {'2x', '3x'};
            obj.MainGrid.Padding = [4, 4, 4, 4];
            obj.MainGrid.RowSpacing = 3;
            obj.MainGrid.ColumnSpacing = 3;

            % --- 左上: TabGroup (仪器 + 参数) ---
            obj.TabGroup = uitabgroup(obj.MainGrid);
            obj.TabGroup.Layout.Row = 1;
            obj.TabGroup.Layout.Column = 1;

            % 仪器 Tab
            instrumentTab = uitab(obj.TabGroup, 'Title', 'Instruments');
            instrumentGrid = uigridlayout(instrumentTab, [2, 1]);
            instrumentGrid.RowHeight = {'1x', 'fit'};
            instrumentGrid.ColumnWidth = {'1x'};
            instrumentGrid.Padding = [4, 4, 4, 4];
            instrumentGrid.RowSpacing = 3;

            % 表格 + Lamp 并排
            instrTopGrid = uigridlayout(instrumentGrid, [1, 2]);
            instrTopGrid.Layout.Row = 1;
            instrTopGrid.ColumnWidth = {'1x', 40};
            instrTopGrid.Padding = [0, 0, 0, 0];
            instrTopGrid.ColumnSpacing = 2;

            obj.InstrumentTable = uitable(instrTopGrid);
            obj.InstrumentTable.Layout.Column = 1;
            obj.InstrumentTable.ColumnName = {'Instrument', 'Type', 'IP', 'Connect', 'Disconnect', 'Acquire'};
            obj.InstrumentTable.ColumnWidth = {190, 70, 150, 85, 95, 85};
            obj.InstrumentTable.ColumnEditable = false(1, 6);
            obj.InstrumentTable.FontSize = 14;
            obj.InstrumentTable.CellSelectionCallback = @(~,evt) obj.onInstrumentSelected(evt);

            % Lamp 列
            lampCol = uigridlayout(instrTopGrid, [1, 1]);
            lampCol.Layout.Column = 2;
            lampCol.Padding = [0, 2, 0, 2];
            lampCol.RowSpacing = 0;
            lampCol.Tag = 'LampColumnGrid';
            % Lamps created in populateInstrumentRows

            % 操作按钮
            buttonGrid = uigridlayout(instrumentGrid, [1, 3]);
            buttonGrid.Layout.Row = 2;
            buttonGrid.Padding = [0, 0, 0, 0];
            buttonGrid.ColumnSpacing = 6;
            buttonGrid.BackgroundColor = [0.94, 0.94, 0.94];
            uibutton(buttonGrid, 'push', ...
                'Text', 'Connect All', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onConnectAll());
            uibutton(buttonGrid, 'push', ...
                'Text', 'Disconnect All', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onDisconnectAll());
            uibutton(buttonGrid, 'push', ...
                'Text', 'Acquire All Connected', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onAcquireAll(), ...
                'BackgroundColor', [0.2, 0.6, 1.0]);

            % 参数 Tab
            paramTab = uitab(obj.TabGroup, 'Title', 'Parameters');
            obj.ParamGrid = uigridlayout(paramTab, [1, 1]);
            obj.ParamGrid.Padding = [4, 4, 4, 4];
            obj.ParamGrid.RowSpacing = 3;

            paramPlaceholder = uilabel(obj.ParamGrid, ...
                'Text', 'Select an instrument to view and edit its parameters.', ...
                'FontSize', 14, ...
                'HorizontalAlignment', 'center', ...
                'FontColor', [0.5, 0.5, 0.5]);
            paramPlaceholder.Layout.Row = 1;
            paramPlaceholder.Layout.Column = 1;

            % --- 右上: 数据绘图 + 采集表格 ---
            dataPanel = uipanel(obj.MainGrid, 'Title', 'Live Data View', 'FontSize', 14);
            dataPanel.Layout.Row = 1;
            dataPanel.Layout.Column = 2;
            dataGrid = uigridlayout(dataPanel, [2, 1]);
            dataGrid.RowHeight = {'3x', '1x'};
            dataGrid.Padding = [4, 4, 4, 4];
            dataGrid.RowSpacing = 3;

            plotPanel = uipanel(dataGrid, 'BorderType', 'none');
            plotPanel.Layout.Row = 1;
            obj.PlotTileLayout = tiledlayout(plotPanel, 'flow');
            obj.PlotTileLayout.Padding = 'compact';
            obj.PlotTileLayout.TileSpacing = 'compact';
            title(obj.PlotTileLayout, 'Acquire data to display plots', 'FontSize', 12);

            obj.AcquisitionTable = uitable(dataGrid);
            obj.AcquisitionTable.Layout.Row = 2;
            obj.AcquisitionTable.ColumnName = {'Device', 'Type', 'Timestamp', 'Traces', 'Status'};
            obj.AcquisitionTable.ColumnWidth = {90, 55, 130, 55, 60};
            obj.AcquisitionTable.FontSize = 14;
            obj.AcquisitionTable.Data = cell(0, 5);
            obj.AcquisitionTable.CellSelectionCallback = @(~,evt) obj.onDataRowSelected(evt);

            % --- 左下: 存储 + ELOG ---
            bottomLeft = uigridlayout(obj.MainGrid, [2, 1]);
            bottomLeft.Layout.Row = 2;
            bottomLeft.Layout.Column = 1;
            bottomLeft.RowHeight = {'1x', '1.5x'};
            bottomLeft.RowSpacing = 3;
            bottomLeft.Padding = [0, 0, 0, 0];

            obj.buildStoragePanel(bottomLeft);
            obj.buildElogPanel(bottomLeft);

            % --- 右下: 状态日志 ---
            logPanel = uipanel(obj.MainGrid, 'Title', 'Status Log', 'FontSize', 14);
            logPanel.Layout.Row = 2;
            logPanel.Layout.Column = 2;
            logGrid = uigridlayout(logPanel, [1, 1]);
            logGrid.Padding = [4, 4, 4, 4];

            obj.LogArea = uitextarea(logGrid, ...
                'Editable', 'off', ...
                'FontSize', 12, ...
                'WordWrap', 'on', ...
                'Value', '');

            % --- 底部状态栏（第3行，跨两列）---
            obj.StatusLabel = uilabel(obj.MainGrid, ...
                'Text', 'Ready', ...
                'FontSize', 11, ...
                'HorizontalAlignment', 'left');
            obj.StatusLabel.Layout.Row = 3;
            obj.StatusLabel.Layout.Column = [1, 2];
        end

        function buildStoragePanel(obj, parent)
            panel = uipanel(parent, 'Title', 'Data Storage', 'FontSize', 14);
            panel.Layout.Row = 1;
            panel.Layout.Column = 1;

            storageGrid = uigridlayout(panel, [3, 5]);
            storageGrid.RowHeight = {'fit', 'fit', 'fit'};
            storageGrid.ColumnWidth = {'fit', '1x', 'fit', 'fit', 'fit'};
            storageGrid.Padding = [4, 4, 4, 4];
            storageGrid.RowSpacing = 3;
            storageGrid.ColumnSpacing = 4;

            % 文件夹行
            uilabel(storageGrid, 'Text', 'Folder:', 'FontSize', 14);
            obj.FolderEdit = uieditfield(storageGrid, 'text', ...
                'Value', obj.Config.Folder, 'FontSize', 14, 'Editable', 'on');
            obj.FolderEdit.Layout.Column = [2, 4];
            uibutton(storageGrid, 'push', 'Text', 'Browse', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onBrowseFolder());

            % 格式选择行
            uilabel(storageGrid, 'Text', 'Formats:', 'FontSize', 14);
            formatSubGrid = uigridlayout(storageGrid, [1, 3]);
            formatSubGrid.Layout.Column = [2, 5];
            formatSubGrid.ColumnWidth = {'fit', 'fit', 'fit'};
            formatSubGrid.Padding = [0, 0, 0, 0];
            formatSubGrid.ColumnSpacing = 10;
            obj.MatCheck = uicheckbox(formatSubGrid, 'Text', 'MAT', 'FontSize', 14, 'Value', true);
            obj.CsvCheck = uicheckbox(formatSubGrid, 'Text', 'CSV', 'FontSize', 14, 'Value', true);
            obj.PngCheck = uicheckbox(formatSubGrid, 'Text', 'PNG', 'FontSize', 14, 'Value', false);

            % 操作行
            obj.AutoSaveCheck = uicheckbox(storageGrid, ...
                'Text', 'Auto-save after acquire', 'FontSize', 14, 'Value', true);
            obj.AutoSaveCheck.Layout.Column = [1, 2];
            uibutton(storageGrid, 'push', 'Text', 'Save All', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onSaveAll());
            uibutton(storageGrid, 'push', 'Text', 'Save Session', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onSaveSession(), ...
                'BackgroundColor', [0.0, 0.5, 0.2]);
            uibutton(storageGrid, 'push', 'Text', 'Save Selected', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onSaveSelected());
        end

        function buildElogPanel(obj, parent)
            panel = uipanel(parent, 'Title', 'ELOG Upload', 'FontSize', 14);
            panel.Layout.Row = 2;
            panel.Layout.Column = 1;

            elogGrid = uigridlayout(panel, [8, 3]);
            elogGrid.RowHeight = repmat({'fit'}, 1, 8);
            elogGrid.ColumnWidth = {'fit', '1x', 'fit'};
            elogGrid.Padding = [4, 4, 4, 4];
            elogGrid.RowSpacing = 2;
            elogGrid.ColumnSpacing = 4;

            % 1: Server : Port
            uilabel(elogGrid, 'Text', 'Server:', 'FontSize', 14);
            obj.ServerEdit = uieditfield(elogGrid, 'text', ...
                'Value', obj.Config.ElogServer, 'FontSize', 14);
            uilabel(elogGrid, 'Text', 'Port:', 'FontSize', 14);
            obj.ServerEdit.Layout.Column = 2;
            obj.PortEdit = uieditfield(elogGrid, 'numeric', ...
                'Value', obj.Config.ElogPort, 'FontSize', 14, ...
                'Limits', [1, 65535], 'RoundFractionalValues', 'on');
            obj.PortEdit.Layout.Column = 3;

            % 2: Logbook
            uilabel(elogGrid, 'Text', 'Logbook:', 'FontSize', 14);
            obj.LogbookDrop = uidropdown(elogGrid, 'FontSize', 14, ...
                'Items', obj.Config.ElogLogbooks, ...
                'Value', obj.Config.ElogLogbooks{1}, 'Editable', 'on');
            obj.LogbookDrop.Layout.Column = [2, 3];

            % 3: Author
            uilabel(elogGrid, 'Text', 'Author:', 'FontSize', 14);
            obj.AuthorDrop = uidropdown(elogGrid, 'FontSize', 14, ...
                'Items', obj.Config.ElogAuthors, ...
                'Value', obj.Config.ElogAuthors{1}, 'Editable', 'on');
            obj.AuthorDrop.Layout.Column = [2, 3];

            % 4: Sample
            uilabel(elogGrid, 'Text', 'Sample:', 'FontSize', 14);
            obj.SampleEdit = uieditfield(elogGrid, 'text', 'FontSize', 14, 'Value', '');
            obj.SampleEdit.Layout.Column = [2, 3];

            % 5: Measurement
            uilabel(elogGrid, 'Text', 'Measurement:', 'FontSize', 14);
            obj.MeasurementEdit = uieditfield(elogGrid, 'text', 'FontSize', 14, 'Value', '');
            obj.MeasurementEdit.Layout.Column = [2, 3];

            % 6: Comments
            uilabel(elogGrid, 'Text', 'Comments:', 'FontSize', 14);
            obj.CommentsArea = uitextarea(elogGrid, 'FontSize', 14, ...
                'Value', '', 'Placeholder', 'Enter comments for the ELOG entry...');
            obj.CommentsArea.Layout.Column = [2, 3];

            % 7: Note
            uilabel(elogGrid, 'Text', 'Note:', 'FontSize', 14);
            obj.NoteEdit = uieditfield(elogGrid, 'text', 'FontSize', 14, ...
                'Value', '', 'Placeholder', 'Additional note / remarks');
            obj.NoteEdit.Layout.Column = [2, 3];

            % 8: Upload row
            obj.AttachSnapshotCheck = uicheckbox(elogGrid, ...
                'Text', 'Attach instrument snapshot', 'FontSize', 14, 'Value', true);
            obj.AttachSnapshotCheck.Layout.Column = [1, 2];
            uibutton(elogGrid, 'push', ...
                'Text', 'Upload to ELOG', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onUploadElog(), ...
                'BackgroundColor', [0.1, 0.4, 0.8]);
            obj.ElogStatusLabel = uilabel(elogGrid, ...
                'Text', 'Idle', 'FontSize', 12, 'FontColor', [0.5, 0.5, 0.5]);
        end

        function populateInstrumentRows(obj)
            registry = labdevices.core.InstrumentRegistry.all();
            allKeys = string(fieldnames(registry));
            obj.InstrumentKeys = allKeys;
            nInstruments = numel(allKeys);

            % 表格数据（6列，无Status列）
            tableData = cell(nInstruments, 6);
            for i = 1:nInstruments
                k = allKeys(i);
                entry = registry.(k);
                tableData{i, 1} = char(entry.displayName);
                tableData{i, 2} = char(entry.type);
                tableData{i, 3} = char(entry.ip);
                tableData{i, 4} = 'Connect';
                tableData{i, 5} = 'Disconnect';
                tableData{i, 6} = 'Acquire';
            end
            obj.InstrumentTable.Data = tableData;
            obj.InstrumentTable.UserData = allKeys;

            % 创建 Lamp 控件（在 instrTopGrid 的 lampCol 中）
            % 找到 lamp 列 grid（通过 Tag 查找）
            lampParent = obj.InstrumentTable.Parent;
            lampCol = findobj(lampParent.Children, 'flat', 'Tag', 'LampColumnGrid');
            if ~isempty(lampCol) && isa(lampCol, 'matlab.ui.container.GridLayout')
                % 清除旧内容，重建
                delete(lampCol.Children);
                % 首行留空给表头偏移，后续每行一个 lamp
                lampCol.RowHeight = [{'1x'}, repmat({'1x'}, 1, nInstruments)];
                obj.StatusLamps = matlab.ui.control.Lamp.empty();
                for i = 1:nInstruments
                    obj.StatusLamps(i) = uilamp(lampCol, ...
                        'Color', [0.55, 0.55, 0.55]);
                    obj.StatusLamps(i).Layout.Row = i + 1;
                end
            end
        end

        function refreshParameterPanel(obj, key)
            if ~isempty(obj.ParamControls)
                fns = fieldnames(obj.ParamControls);
                for i = 1:numel(fns)
                    ctrl = obj.ParamControls.(fns{i});
                    if isvalid(ctrl); delete(ctrl); end
                end
                obj.ParamControls = struct();
            end
            children = obj.ParamGrid.Children;
            for i = 1:numel(children)
                delete(children(i));
            end

            if isempty(key) || strlength(key) == 0
                placeholder = uilabel(obj.ParamGrid, ...
                    'Text', 'Select an instrument to view and edit its parameters.', ...
                    'FontSize', 14, 'HorizontalAlignment', 'center', ...
                    'FontColor', [0.5, 0.5, 0.5]);
                placeholder.Layout.Row = 1;
                placeholder.Layout.Column = 1;
                return;
            end

            registry = labdevices.core.InstrumentRegistry.all();
            k = char(key);
            if ~isfield(registry, k); return; end
            instrType = registry.(k).type;

            params = labdevices.core.ParameterDef.forType(instrType);
            nParams = numel(params);

            if nParams == 0
                placeholder = uilabel(obj.ParamGrid, ...
                    'Text', sprintf('No configurable parameters for %s.', instrType), ...
                    'FontSize', 14, 'HorizontalAlignment', 'center', ...
                    'FontColor', [0.5, 0.5, 0.5]);
                placeholder.Layout.Row = 1;
                placeholder.Layout.Column = 1;
                return;
            end

            fullParamGrid = uigridlayout(obj.ParamGrid, [nParams + 1, 3]);
            fullParamGrid.RowHeight = [repmat({'fit'}, 1, nParams), {'fit'}];
            fullParamGrid.ColumnWidth = {'1.5x', '2x', '0.5x'};
            fullParamGrid.Padding = [4, 4, 4, 4];
            fullParamGrid.RowSpacing = 3;
            fullParamGrid.ColumnSpacing = 4;
            fullParamGrid.Layout.Row = 1;
            fullParamGrid.Layout.Column = 1;

            obj.ParamControls = struct();

            for i = 1:nParams
                pDef = params(i);

                lbl = uilabel(fullParamGrid, 'Text', char(pDef.Label), ...
                    'FontSize', 14, 'Tooltip', char(pDef.Tooltip));
                lbl.Layout.Row = i;
                lbl.Layout.Column = 1;

                ctrlName = char(pDef.Name);
                switch pDef.Type
                    case "numeric"
                        ctrl = uieditfield(fullParamGrid, 'numeric', ...
                            'FontSize', 14, 'Value', pDef.Default, ...
                            'Tooltip', char(pDef.Tooltip));
                    case "logical"
                        ctrl = uicheckbox(fullParamGrid, 'FontSize', 14, ...
                            'Text', char(pDef.Label), 'Value', pDef.Default);
                        lbl.Text = '';
                    case "choice"
                        items = pDef.Choices;
                        if isempty(items)
                            items = {char(string(pDef.Default))};
                        elseif iscell(items)
                            items = string(items);
                        end
                        val = string(pDef.Default);
                        if ~any(strcmp(string(items), val))
                            val = items(1);
                        end
                        ctrl = uidropdown(fullParamGrid, 'FontSize', 14, ...
                            'Items', items, 'Value', val, ...
                            'Tooltip', char(pDef.Tooltip));
                    otherwise
                        ctrl = uieditfield(fullParamGrid, 'text', 'FontSize', 14, ...
                            'Value', string(pDef.Default));
                end
                ctrl.Layout.Row = i;
                ctrl.Layout.Column = 2;
                ctrl.Tag = ctrlName;

                if strlength(pDef.Unit) > 0
                    unitLbl = uilabel(fullParamGrid, 'Text', char(pDef.Unit), ...
                        'FontSize', 12, 'FontColor', [0.4, 0.4, 0.4]);
                    unitLbl.Layout.Row = i;
                    unitLbl.Layout.Column = 3;
                end

                obj.ParamControls.(ctrlName) = ctrl;
            end

            % 四按钮行
            btnRow = uigridlayout(fullParamGrid, [1, 5]);
            btnRow.Layout.Row = nParams + 1;
            btnRow.Layout.Column = [1, 3];
            btnRow.ColumnWidth = {'fit', 'fit', 'fit', '1x', 'fit'};
            btnRow.Padding = [0, 4, 0, 0];
            btnRow.ColumnSpacing = 4;

            uibutton(btnRow, 'push', 'Text', 'Apply', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onApplyParameters(), ...
                'BackgroundColor', [0.0, 0.7, 0.7], ...
                'Tooltip', 'Apply configuration only (no acquisition)');
            uibutton(btnRow, 'push', 'Text', 'Acquire', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onAcquireSelected(), ...
                'BackgroundColor', [0.2, 0.7, 0.3], ...
                'Tooltip', 'Acquire with stored parameters');
            uibutton(btnRow, 'push', 'Text', 'Apply+Acquire', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.onApplyAndAcquire(), ...
                'BackgroundColor', [0.2, 0.6, 1.0], ...
                'Tooltip', 'Configure then acquire');
            uibutton(btnRow, 'push', 'Text', 'Reset', 'FontSize', 14, ...
                'ButtonPushedFcn', @(~,~) obj.resetParameterDefaults());
        end
    end

    %% ======================== 回调: 仪器操作 ========================
    methods (Access = private)
        function onConnect(obj, key)
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end
            try
                obj.Station.connect(key);
                obj.logMessage(sprintf("Connected: %s", key), "info");
            catch ME
                obj.logMessage(sprintf("Connect failed (%s): %s", key, ME.message), "error");
            end
            obj.updateStatusLamps();
            obj.updateStatusBar();
        end

        function onDisconnect(obj, key)
            try
                obj.Station.disconnect(key);
                obj.logMessage(sprintf("Disconnected: %s", key), "info");
            catch ME
                obj.logMessage(sprintf("Disconnect failed (%s): %s", key, ME.message), "error");
            end
            obj.updateStatusLamps();
            obj.updateStatusBar();
        end

        function onConnectAll(obj, ~, ~)
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end
            obj.setBusy(true);
            try
                obj.Station.connectAll();
                obj.logMessage("All instruments connected.", "info");
            catch ME
                obj.logMessage(sprintf("ConnectAll error: %s", ME.message), "error");
            end
            obj.setBusy(false);
            obj.updateStatusLamps();
            obj.updateStatusBar();
        end

        function onDisconnectAll(obj, ~, ~)
            obj.Station.disconnectAll();
            obj.logMessage("All instruments disconnected.", "info");
            obj.updateStatusLamps();
            obj.updateStatusBar();
        end

        function onInstrumentSelected(obj, evt)
            indices = evt.Indices;
            if isempty(indices); return; end
            row = indices(1); col = indices(2);
            key = obj.InstrumentKeys(row);

            % 6列: 1=Name,2=Type,3=IP,4=Connect,5=Disconnect,6=Acquire
            if col == 4; obj.onConnect(key); return;
            elseif col == 5; obj.onDisconnect(key); return;
            elseif col == 6; obj.onAcquire(key); return;
            end

            obj.SelectedKey = key;
            obj.TabGroup.SelectedTab = obj.TabGroup.Children(2);
            obj.refreshParameterPanel(obj.SelectedKey);
            obj.logMessage(sprintf("Selected: %s", obj.SelectedKey), "info");
        end
    end

    %% ======================== 回调: 采集 ========================
    methods (Access = private)
        function onAcquire(obj, key)
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end
            if ~obj.Station.isConnected(key)
                obj.logMessage(sprintf("Not connected: %s", key), "warn"); return;
            end

            obj.setBusy(true);
            obj.logMessage(sprintf("Acquiring: %s ...", key), "info");
            try
                instrument = obj.Station.getInstrument(key);
                if obj.AcquireParamsMap.isKey(key)
                    args = obj.AcquireParamsMap(key);
                else
                    args = obj.buildAcquireArgs(key, {});
                end
                data = instrument.acquire(args{:});
                obj.onAcquireDone(key, data);
            catch ME
                obj.logMessage(sprintf("Acquire failed (%s): %s", key, ME.message), "error");
            end
            obj.setBusy(false);
        end

        function onAcquireAll(obj, ~, ~)
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end
            connected = obj.Station.connectedKeys();
            if isempty(connected); obj.logMessage("No instruments connected.", "warn"); return; end

            obj.setBusy(true);
            obj.logMessage(sprintf("Acquiring all (%d instruments)...", numel(connected)), "info");
            try
                results = obj.Station.acquireAll([], obj.AcquireParamsMap);
                resultKeys = results.keys();
                for i = 1:numel(resultKeys)
                    k = resultKeys{i};
                    obj.onAcquireDone(k, results(k));
                end
                obj.logMessage(sprintf("AcquireAll complete: %d/%d succeeded.", ...
                    results.Count, numel(connected)), "info");
            catch ME
                obj.logMessage(sprintf("AcquireAll error: %s", ME.message), "error");
            end
            obj.setBusy(false);
        end

        function onApplyParameters(obj, ~, ~)
            % 仅应用配置参数，不采集
            if isempty(obj.SelectedKey) || strlength(obj.SelectedKey) == 0
                obj.logMessage("No instrument selected.", "warn"); return;
            end
            if ~obj.Station.isConnected(obj.SelectedKey)
                obj.logMessage(sprintf("Not connected: %s", obj.SelectedKey), "warn"); return;
            end

            allArgs = obj.collectParameterValues();
            [configArgs, acquireArgs] = obj.splitAcquireParams(allArgs, obj.SelectedKey);

            if ~isempty(configArgs)
                try
                    instrument = obj.Station.getInstrument(obj.SelectedKey);
                    instrument.configure(configArgs{:});
                    obj.logMessage(sprintf("Configured %s (%d params).", ...
                        obj.SelectedKey, numel(configArgs)/2), "info");
                catch ME
                    obj.logMessage(sprintf("Configure failed: %s", ME.message), "error");
                    return;
                end
            end

            % 存储 acquire 参数供后续使用
            acqCell = obj.buildAcquireArgs(obj.SelectedKey, acquireArgs);
            obj.AcquireParamsMap(obj.SelectedKey) = acqCell;
            obj.logMessage(sprintf("Acquire params stored for: %s", obj.SelectedKey), "info");
        end

        function onAcquireSelected(obj, ~, ~)
            % 仅采集（使用已存储的参数）
            if isempty(obj.SelectedKey) || strlength(obj.SelectedKey) == 0
                obj.logMessage("No instrument selected.", "warn"); return;
            end
            obj.onAcquire(obj.SelectedKey);
        end

        function onApplyAndAcquire(obj, ~, ~)
            % 配置并采集
            if isempty(obj.SelectedKey) || strlength(obj.SelectedKey) == 0
                obj.logMessage("No instrument selected.", "warn"); return;
            end
            if ~obj.Station.isConnected(obj.SelectedKey)
                obj.logMessage(sprintf("Not connected: %s", obj.SelectedKey), "warn"); return;
            end
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end

            allArgs = obj.collectParameterValues();
            [configArgs, acquireArgs] = obj.splitAcquireParams(allArgs, obj.SelectedKey);

            if ~isempty(configArgs)
                try
                    instrument = obj.Station.getInstrument(obj.SelectedKey);
                    instrument.configure(configArgs{:});
                    obj.logMessage(sprintf("Configured %s (%d params).", ...
                        obj.SelectedKey, numel(configArgs)/2), "info");
                catch ME
                    obj.logMessage(sprintf("Configure failed: %s", ME.message), "error");
                    return;
                end
            end

            acqCell = obj.buildAcquireArgs(obj.SelectedKey, acquireArgs);
            obj.AcquireParamsMap(obj.SelectedKey) = acqCell;

            obj.onAcquire(obj.SelectedKey);
        end

        function onAcquireDone(obj, key, data)
            if isempty(obj.AcquisitionStore)
                obj.AcquisitionStore = {};
            end
            obj.AcquisitionStore{end + 1} = {char(key), data};

            deviceName = ''; deviceType = ''; timestamp = ''; nTraces = 0;
            if isfield(data, 'device'); deviceName = char(data.device); end
            if isfield(data, 'type'); deviceType = char(data.type); end
            if isfield(data, 'timestamp'); timestamp = char(data.timestamp); end
            if isfield(data, 'traces') && ~isempty(data.traces)
                nTraces = numel(data.traces);
            end

            existingData = obj.AcquisitionTable.Data;
            newRow = {deviceName, deviceType, timestamp, nTraces, 'OK'};
            obj.AcquisitionTable.Data = [existingData; newRow];

            obj.logMessage(sprintf("Acquired: %s (%d traces, %s)", ...
                deviceName, nTraces, timestamp), "info");
            obj.updateStatusBar();

            obj.plotAcquisitionData(char(key), data);

            if obj.AutoSaveCheck.Value
                try; obj.doSave(data, key); catch ME;
                    obj.logMessage(sprintf("Auto-save failed: %s", ME.message), "error");
                end
            end
        end

        function configArgs = collectParameterValues(obj)
            configArgs = {};
            if isempty(obj.ParamControls); return; end
            fns = fieldnames(obj.ParamControls);
            for i = 1:numel(fns)
                ctrlName = fns{i};
                ctrl = obj.ParamControls.(ctrlName);
                if ~isvalid(ctrl); continue; end
                val = obj.getControlValue(ctrl);
                if ~isempty(val)
                    configArgs{end + 1} = ctrlName; %#ok<AGROW>
                    configArgs{end + 1} = val; %#ok<AGROW>
                end
            end
        end

        function val = getControlValue(~, ctrl)
            if isa(ctrl, 'matlab.ui.control.CheckBox')
                val = ctrl.Value;
            elseif isa(ctrl, 'matlab.ui.control.DropDown')
                itemStr = string(ctrl.Value);
                val = str2double(itemStr);
                if isnan(val); val = char(itemStr); end
            elseif isa(ctrl, 'matlab.ui.control.NumericEditField')
                val = ctrl.Value;
            elseif isa(ctrl, 'matlab.ui.control.EditField')
                itemStr = string(ctrl.Value);
                val = str2double(itemStr);
                if isnan(val); val = char(itemStr); end
            else
                val = [];
            end
        end

        function resetParameterDefaults(obj)
            obj.SelectedKey = '';
            obj.refreshParameterPanel('');
            obj.logMessage("Parameters reset.", "info");
        end

        function onDataRowSelected(obj, evt)
            indices = evt.Indices;
            if isempty(indices); return; end
            row = indices(1);
            if row > numel(obj.AcquisitionStore); return; end
            entry = obj.AcquisitionStore{row};
            key = entry{1};
            data = entry{2};
            obj.plotAcquisitionData(key, data);
            deviceName = '';
            if isfield(data, 'device'); deviceName = char(data.device); end
            obj.logMessage(sprintf("Plotting: %s (row %d)", deviceName, row), "info");
        end

        %% ---- 参数分流辅助方法 ----
        function [configArgs, acquireArgs] = splitAcquireParams(obj, allArgs, key)
            configArgs = {}; acquireArgs = {};
            registry = labdevices.core.InstrumentRegistry.all();
            k = char(key);
            if ~isfield(registry, k); configArgs = allArgs; return; end
            acquireNames = obj.getAcquireParamNames(registry.(k).type);

            for i = 1:2:numel(allArgs)
                name = allArgs{i}; val = allArgs{i+1};
                if ismember(name, acquireNames)
                    acquireArgs{end+1} = name; %#ok<AGROW>
                    acquireArgs{end+1} = val; %#ok<AGROW>
                else
                    configArgs{end+1} = name; %#ok<AGROW>
                    configArgs{end+1} = val; %#ok<AGROW>
                end
            end
        end

        function names = getAcquireParamNames(~, instrType)
            switch upper(instrType)
                case 'OSA'; names = {'Trace'};
                case 'SCOPE'; names = {'Channels'};
                case 'ESA'; names = {'TraceNumbers'};
                case 'VNA'; names = {'Channels'};
                otherwise; names = {};
            end
        end

        function args = buildAcquireArgs(obj, key, acquireArgsCell)
            registry = labdevices.core.InstrumentRegistry.all();
            k = char(key);
            instrType = registry.(k).type;

            switch upper(instrType)
                case 'OSA'
                    traceStr = obj.extractNamedParam(acquireArgsCell, 'Trace');
                    if isempty(traceStr); args = {{'TRD'}};
                    else; args = {{char(traceStr)}}; end
                case 'SCOPE'
                    chStr = obj.extractNamedParam(acquireArgsCell, 'Channels');
                    if isempty(chStr); args = {[1]};
                    else
                        channels = str2double(strsplit(char(chStr), ','));
                        channels = unique(channels(~isnan(channels)));
                        args = {channels};
                    end
                case 'ESA'
                    trStr = obj.extractNamedParam(acquireArgsCell, 'TraceNumbers');
                    if isempty(trStr); args = {[1]};
                    else
                        traces = str2double(strsplit(char(trStr), ','));
                        traces = unique(traces(~isnan(traces)));
                        args = {traces};
                    end
                case 'VNA'
                    chStr = obj.extractNamedParam(acquireArgsCell, 'Channels');
                    if isempty(chStr); args = {[1]};
                    else
                        channels = str2double(strsplit(char(chStr), ','));
                        channels = unique(channels(~isnan(channels)));
                        args = {channels};
                    end
                otherwise; args = {};
            end
        end

        function val = extractNamedParam(~, argsCell, name)
            val = [];
            for i = 1:2:numel(argsCell)
                if strcmp(argsCell{i}, name)
                    val = argsCell{i+1}; return;
                end
            end
        end
    end

    %% ======================== 回调: 存储 & ELOG ========================
    methods (Access = private)
        function onBrowseFolder(obj, ~, ~)
            folder = uigetdir(obj.FolderEdit.Value, 'Select output folder');
            if folder ~= 0
                obj.FolderEdit.Value = folder;
                obj.logMessage(sprintf("Output folder: %s", folder), "info");
            end
        end

        function onSaveAll(obj, ~, ~)
            if isempty(obj.AcquisitionStore)
                obj.logMessage("No data to save.", "warn"); return;
            end
            for i = 1:numel(obj.AcquisitionStore)
                try
                    entry = obj.AcquisitionStore{i};
                    obj.doSave(entry{2}, entry{1});
                catch ME
                    obj.logMessage(sprintf("Save failed #%d: %s", i, ME.message), "error");
                end
            end
            obj.logMessage(sprintf("Saved %d acquisitions.", numel(obj.AcquisitionStore)), "info");
        end

        function onSaveSession(obj, ~, ~)
            % 将所有采集数据合并存入单个 .mat 文件
            if isempty(obj.AcquisitionStore)
                obj.logMessage("No data to save.", "warn"); return;
            end

            combined = struct();
            for i = 1:numel(obj.AcquisitionStore)
                entry = obj.AcquisitionStore{i};
                key = entry{1};
                data = entry{2};

                fieldName = matlab.lang.makeValidName(key);
                if isfield(combined, fieldName)
                    suffix = 2;
                    while isfield(combined, [fieldName '_' num2str(suffix)])
                        suffix = suffix + 1;
                    end
                    fieldName = [fieldName '_' num2str(suffix)];
                end
                combined.(fieldName) = data;
            end

            ts = datestr(now, 'yyyy_mm_dd_HH_MM');
            matPath = fullfile(obj.FolderEdit.Value, ['session_' ts '.mat']);
            if ~isfolder(obj.FolderEdit.Value); mkdir(obj.FolderEdit.Value); end
            save(matPath, "-struct", "combined", "-v7.3");
            obj.logMessage(sprintf("Session saved: %s (%d instruments)", ...
                matPath, numel(fieldnames(combined))), "info");
        end

        function onSaveSelected(obj, ~, ~)
            obj.logMessage("Save Selected: click a row in the acquisition table.", "info");
        end

        function saved = doSave(obj, data, key)
            formats = {};
            if obj.MatCheck.Value; formats{end + 1} = 'mat'; end %#ok<AGROW>
            if obj.CsvCheck.Value; formats{end + 1} = 'csv'; end %#ok<AGROW>
            if obj.PngCheck.Value; formats{end + 1} = 'png'; end %#ok<AGROW>
            if isempty(formats); obj.logMessage("No formats selected.", "warn"); saved = struct(); return; end

            saved = labdevices.core.DataExporter.saveAcquisition(data, ...
                'Folder', obj.FolderEdit.Value, 'Formats', formats);
            if isfield(saved, 'mat')
                obj.logMessage(sprintf("Saved: %s", saved.mat), "info");
            end
        end

        function onUploadElog(obj, ~, ~)
            logbook = char(string(obj.LogbookDrop.Value));
            author = char(string(obj.AuthorDrop.Value));
            if isempty(logbook)
                obj.ElogStatusLabel.Text = 'Missing logbook';
                obj.ElogStatusLabel.FontColor = [1, 0, 0]; return;
            end
            if isempty(author)
                obj.ElogStatusLabel.Text = 'Missing author';
                obj.ElogStatusLabel.FontColor = [1, 0, 0]; return;
            end

            obj.ElogStatusLabel.Text = 'Uploading...';
            obj.ElogStatusLabel.FontColor = [1, 0.6, 0];
            drawnow;

            opts = struct();
            opts.Server = char(string(obj.ServerEdit.Value));
            opts.Port = obj.PortEdit.Value;
            opts.Logbook = logbook;
            opts.Author = author;
            opts.Sample = char(string(obj.SampleEdit.Value));
            opts.Measurement = char(string(obj.MeasurementEdit.Value));
            opts.Type = 'ManualSave';
            opts.Comments = char(string(obj.CommentsArea.Value));

            % 追加 Note 到 Comments
            noteStr = char(string(obj.NoteEdit.Value));
            if ~isempty(noteStr)
                opts.Comments = [opts.Comments, newline, '--- Note ---', newline, noteStr];
            end

            if obj.AttachSnapshotCheck.Value
                opts.Snapshot = obj.Station.getSnapshot();
            end

            try
                [success, response] = labdevices.core.DataExporter.uploadToElog(opts);
                if success
                    obj.ElogStatusLabel.Text = 'Upload OK';
                    obj.ElogStatusLabel.FontColor = [0, 0.6, 0];
                    obj.logMessage(sprintf("ELOG upload OK: %s", strtrim(response)), "info");
                else
                    obj.ElogStatusLabel.Text = 'Upload failed';
                    obj.ElogStatusLabel.FontColor = [1, 0, 0];
                    obj.logMessage(sprintf("ELOG upload failed: %s", response), "error");
                end
            catch ME
                obj.ElogStatusLabel.Text = 'Upload error';
                obj.ElogStatusLabel.FontColor = [1, 0, 0];
                obj.logMessage(sprintf("ELOG upload error: %s", ME.message), "error");
            end
        end
    end

    %% ======================== 回调: 生命周期 ========================
    methods (Access = private)
        function onFigureClose(obj, ~, ~)
            obj.delete();
        end
    end

    %% ======================== 工具方法 ========================
    methods (Access = private)
        function logMessage(obj, msg, level)
            if nargin < 3; level = 'info'; end
            ts = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
            switch level
                case 'info'; prefix = '[INFO] ';
                case 'warn'; prefix = '[WARN] ';
                case 'error'; prefix = '[ERROR] ';
                otherwise; prefix = '';
            end
            line = [ts, ' ', prefix, char(msg)];
            current = obj.LogArea.Value;
            if isempty(current) || (isstring(current) && strlength(current) == 0)
                obj.LogArea.Value = line;
            else
                if iscell(current)
                    obj.LogArea.Value = [current; {line}];
                else
                    obj.LogArea.Value = [cellstr(current); {line}];
                end
            end
            drawnow;
        end

        function updateStatusLamps(obj)
            for i = 1:numel(obj.InstrumentKeys)
                if i <= numel(obj.StatusLamps) && isvalid(obj.StatusLamps(i))
                    if obj.Station.isConnected(obj.InstrumentKeys(i))
                        obj.StatusLamps(i).Color = [0, 0.8, 0];
                    else
                        obj.StatusLamps(i).Color = [0.55, 0.55, 0.55];
                    end
                end
            end
        end

        function updateStatusBar(obj)
            connected = obj.Station.ConnectedCount;
            total = numel(obj.InstrumentKeys);
            lastAcq = 'N/A';
            if ~isempty(obj.AcquisitionStore)
                entry = obj.AcquisitionStore{end};
                if iscell(entry) && numel(entry) >= 2
                    data = entry{2};
                    if isfield(data, 'timestamp'); lastAcq = data.timestamp; end
                end
            end
            obj.StatusLabel.Text = sprintf( ...
                'Connected: %d/%d  |  Last acquisition: %s', ...
                connected, total, char(lastAcq));
        end

        function setBusy(obj, tf)
            obj.IsBusy = tf;
            if tf
                obj.StatusLabel.Text = [obj.StatusLabel.Text, '  |  BUSY...'];
                drawnow;
            else
                obj.updateStatusBar();
            end
        end

        function config = loadConfig(~, configPath)
            config = struct();
            config.Folder = fullfile(fileparts(mfilename('fullpath')), 'output');
            config.ElogServer = 'lpqm1srv2.epfl.ch';
            config.ElogPort = 8081;
            config.ElogLogbooks = {'LabLog', 'MeasurementLog'};
            config.ElogAuthors = {'User', 'Operator'};

            if isfile(configPath)
                try
                    saved = load(configPath, 'appConfig');
                    if isfield(saved, 'appConfig') && isstruct(saved.appConfig)
                        fns = fieldnames(saved.appConfig);
                        for i = 1:numel(fns)
                            config.(fns{i}) = saved.appConfig.(fns{i});
                        end
                    end
                catch
                end
            end
        end

        function saveConfig(obj)
            appConfig = obj.Config;
            appConfig.Folder = obj.FolderEdit.Value;
            appConfig.ElogServer = obj.ServerEdit.Value;
            appConfig.ElogPort = obj.PortEdit.Value;
            folder = fileparts(obj.ConfigPath);
            if ~isempty(folder) && ~isfolder(folder); mkdir(folder); end
            save(obj.ConfigPath, 'appConfig');
        end

        function plotAcquisitionData(obj, key, data)
            if ~isfield(data, 'traces') || isempty(data.traces); return; end

            % 从 PlotAxesMap 获取或创建 tile
            if obj.PlotAxesMap.isKey(key)
                ax = obj.PlotAxesMap(key);
            else
                ax = nexttile(obj.PlotTileLayout);
                obj.PlotAxesMap(key) = ax;
                ax.XGrid = 'on'; ax.YGrid = 'on'; ax.Box = 'on';
                ax.FontSize = 12;
            end

            cla(ax); hold(ax, 'on');

            for i = 1:numel(data.traces)
                trace = data.traces(i);
                [x, y, yLabel] = labdevices.core.DataExporter.pickPlotVectors(trace);
                if isempty(y); continue; end
                if isempty(x); x = (1:numel(y)).'; end

                traceName = '';
                if isfield(trace, 'name'); traceName = char(trace.name); end
                plot(ax, x, y, 'LineWidth', 1.0, 'DisplayName', traceName);
            end

            grid(ax, 'on');
            if numel(data.traces) > 1
                legend(ax, 'show', 'Location', 'best', 'FontSize', 10);
            end

            xlabel(ax, labdevices.core.DataExporter.pickField(data, 'xunit', 'x'), 'FontSize', 12);
            ylabel(ax, labdevices.core.DataExporter.pickField(data, 'yunit', 'y'), 'FontSize', 12);

            titleStr = labdevices.core.DataExporter.pickField(data, 'device', key);
            if isfield(data, 'timestamp')
                titleStr = [titleStr, '  (', char(data.timestamp), ')'];
            end
            title(ax, titleStr, 'Interpreter', 'none', 'FontSize', 12);

            hold(ax, 'off');
        end
    end
end
