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
            obj.ParamControlCache = containers.Map();

            obj.createComponents();
            obj.populateInstrumentRows();
            obj.updateStatusColumn();
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

        % --- 仪器表格 ---
        InstrumentKeys      string
        InstrumentTable     matlab.ui.control.Table
        ConnectionFailed    logical = []

        % --- 参数面板 ---
        ParamGrid           matlab.ui.container.GridLayout
        ParamControls       struct
        ParamControlCache   containers.Map
        SelectedKey         string

        % --- 采集数据 ---
        AcquisitionTable    matlab.ui.control.Table
        AcquisitionStore    cell
        PlotTileLayout
        PlotAxesMap         containers.Map
        AcquireParamsMap    containers.Map
        LastSavedPaths      cell = {}

        % --- 绘图布局控制 ---
        PlotLayoutMode      string = 'Flow'
        PlotLayoutDropdown
        LogCollapsed        logical = false
        ToggleLogButton
        ElogCollapsed       logical = false

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
        AttachSnapshotCheck matlab.ui.control.CheckBox
        ElogStatusLabel     matlab.ui.control.Label
        DesignDrop          matlab.ui.control.DropDown
        WaferEdit           matlab.ui.control.EditField
        FieldEdit           matlab.ui.control.EditField
        ChipEdit            matlab.ui.control.EditField
        TypeDrop            matlab.ui.control.DropDown
        AutoElogCheck       matlab.ui.control.CheckBox
        ElogContentGrid     matlab.ui.container.GridLayout
        ElogToggleButton    matlab.ui.control.Button
        BottomLeftGrid      matlab.ui.container.GridLayout

        % --- 状态栏 & 日志 ---
        StatusLabel         matlab.ui.control.Label
        LogArea             matlab.ui.control.TextArea

        % --- 采集状态 ---
        IsBusy              logical = false
    end

    %% ======================== 设计系统常量 ========================
    properties (Constant, Access = private)
        % --- 色彩: 明亮光色主题 (Bright Light Professional) ---
        COLOR_PRIMARY       = [0.145 0.388 0.922]  % #2563EB 主按钮/选中
        COLOR_PRIMARY_LIGHT = [0.859 0.918 0.996]  % #DBEAFE 选中行背景
        COLOR_ACCENT        = [0.008 0.518 0.780]  % #0284C7 信息/次要强调
        COLOR_SUCCESS       = [0.086 0.639 0.290]  % #16A34A 成功/采集/保存
        COLOR_WARNING       = [0.918 0.345 0.047]  % #EA580C 警告/忙状态
        COLOR_DANGER        = [0.863 0.149 0.149]  % #DC2626 删除/断开/清除
        COLOR_BG            = [0.973 0.980 0.988]  % #F8FAFC Figure 全局背景
        COLOR_SURFACE       = [1.000 1.000 1.000]  % #FFFFFF 面板/卡片背景
        COLOR_SURFACE_ALT   = [0.945 0.953 0.976]  % #F1F5F9 表格交替行
        COLOR_TEXT          = [0.059 0.090 0.165]  % #0F172A 正文/标签
        COLOR_TEXT_SECONDARY= [0.278 0.333 0.412]  % #475569 辅助文字
        COLOR_TEXT_MUTED    = [0.580 0.639 0.722]  % #94A3B8 占位符/禁用
        COLOR_BORDER        = [0.886 0.910 0.941]  % #E2E8F0 面板边框
        COLOR_BORDER_LIGHT  = [0.945 0.953 0.976]  % #F1F5F9 极淡分隔线
        COLOR_LAMP_OFF      = [0.796 0.835 0.882]  % #CBD5E1 未连接
        COLOR_LAMP_ON       = [0.133 0.773 0.369]  % #22C55E 已连接
        COLOR_LAMP_BUSY     = [0.961 0.620 0.043]  % #F59E0B 采集中
        COLOR_BUTTON_BG     = [0.940 0.940 0.940]  % 默认按钮背景
        COLOR_TEAL          = [0.000 0.650 0.650]  % Apply 按钮
        COLOR_LOG_BG        = [0.970 0.970 0.970]  % 日志区背景

        % --- 排版层级 ---
        FONT_XL = 18  % 面板标题（与正文明显区分）
        FONT_LG = 16  % Section 标题
        FONT_MD = 14  % 正文/按钮/表格
        FONT_SM = 13  % 辅助文本/下拉框
        FONT_XS = 12  % 日志/状态栏/ELOG 字段

        % --- 间距体系 (4px 基准) ---
        SPACE_XS = 2
        SPACE_SM = 4
        SPACE_MD = 8
        SPACE_LG = 12
        SPACE_XL = 16
    end

    %% ======================== UI 构建 ========================
    methods (Access = private)
        function createComponents(obj)
            screenSize = get(0, 'ScreenSize');
            figW = min(1560, screenSize(3) * 0.85);
            figH = min(920, screenSize(4) * 0.88);
            figX = max(1, (screenSize(3) - figW) / 2);
            figY = max(1, (screenSize(4) - figH) / 2);
            obj.Figure = uifigure( ...
                'Name', 'Measurement Device Manager v2', ...
                'NumberTitle', 'off', ...
                'Position', [figX, figY, figW, figH], ...
                'Color', obj.COLOR_BG, ...
                'CloseRequestFcn', @(~,~) obj.onFigureClose(), ...
                'WindowKeyPressFcn', @(~,evt) obj.onKeyPress(evt), ...
                'Resize', 'on');

            obj.MainGrid = uigridlayout(obj.Figure, [3, 3]);
            obj.MainGrid.RowHeight = {'1x', '1x', 30};
            obj.MainGrid.ColumnWidth = {'1.1x', '1.5x', '0.4x'};
            obj.MainGrid.Padding = [obj.SPACE_MD, obj.SPACE_MD, obj.SPACE_MD, obj.SPACE_MD];
            obj.MainGrid.RowSpacing = obj.SPACE_SM;
            obj.MainGrid.ColumnSpacing = obj.SPACE_SM;
            obj.MainGrid.BackgroundColor = obj.COLOR_BG;

            % --- 左上: 仪器 + 参数（上下分栏，占行1）---
            leftWrapper = uigridlayout(obj.MainGrid, [2, 1]);
            leftWrapper.Layout.Row = 1;
            leftWrapper.Layout.Column = 1;
            leftWrapper.RowHeight = {'0.55x', '0.45x'};
            leftWrapper.Padding = [0, 0, 0, 0];
            leftWrapper.RowSpacing = obj.SPACE_SM;
            leftWrapper.BackgroundColor = obj.COLOR_BG;

            % 上栏: 仪器列表
            instrPanel = uipanel(leftWrapper, 'Title', 'Instruments', ...
                'FontSize', obj.FONT_XL, 'FontWeight', 'bold', ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', obj.COLOR_BORDER);
            instrPanel.Layout.Row = 1;

            instrumentGrid = uigridlayout(instrPanel, [2, 1]);
            instrumentGrid.RowHeight = {'1x', 'fit'};
            instrumentGrid.ColumnWidth = {'1x'};
            instrumentGrid.Padding = [obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM];
            instrumentGrid.RowSpacing = obj.SPACE_SM;
            instrumentGrid.BackgroundColor = obj.COLOR_SURFACE;

            % 表格 + Lamp 并排（Connect/Acquire 用 HTML 按钮在表格内，可随表滚动）
            instrTopGrid = uigridlayout(instrumentGrid, [1, 1]);
            instrTopGrid.Layout.Row = 1;
            instrTopGrid.Padding = [0, 0, 0, 0];

            obj.InstrumentTable = uitable(instrTopGrid);
            obj.InstrumentTable.Layout.Column = 1;
            obj.InstrumentTable.ColumnName = {'Instrument', 'Type', 'IP', 'Status', 'Connect', 'Acquire'};
            obj.InstrumentTable.ColumnWidth = {170, 55, 115, 70, 72, 72};
            obj.InstrumentTable.ColumnEditable = false(1, 6);
            obj.InstrumentTable.FontSize = obj.FONT_MD;
            obj.InstrumentTable.BackgroundColor = obj.COLOR_SURFACE;
            obj.InstrumentTable.CellSelectionCallback = @(~,evt) obj.onInstrumentSelected(evt);

            % 批量操作按钮
            buttonGrid = uigridlayout(instrumentGrid, [1, 3]);
            buttonGrid.Layout.Row = 2;
            buttonGrid.Padding = [0, 0, 0, 0];
            buttonGrid.ColumnWidth = {'1x', '1x', '1.15x'};
            buttonGrid.ColumnSpacing = obj.SPACE_MD;
            buttonGrid.BackgroundColor = obj.COLOR_BUTTON_BG;
            uibutton(buttonGrid, 'push', ...
                'Text', 'Connect All', 'FontSize', obj.FONT_MD, ...
                'BackgroundColor', obj.COLOR_PRIMARY, 'FontColor', [1 1 1], ...
                'Tooltip', 'Connect All (Ctrl+C)', ...
                'ButtonPushedFcn', @(~,~) obj.onConnectAll());
            uibutton(buttonGrid, 'push', ...
                'Text', 'Disconnect All', 'FontSize', obj.FONT_MD, ...
                'BackgroundColor', obj.COLOR_DANGER, 'FontColor', [1 1 1], ...
                'Tooltip', 'Disconnect All (Ctrl+D)', ...
                'ButtonPushedFcn', @(~,~) obj.onDisconnectAll());
            uibutton(buttonGrid, 'push', ...
                'Text', 'Acquire All Connected', 'FontSize', obj.FONT_MD, ...
                'ButtonPushedFcn', @(~,~) obj.onAcquireAll(), ...
                'Tooltip', 'Acquire All (Ctrl+Enter)', ...
                'BackgroundColor', obj.COLOR_SUCCESS, 'FontColor', [1 1 1]);

            % 下栏: 参数面板（内联显示，选中仪器即出现）
            paramPanel = uipanel(leftWrapper, 'Title', 'Parameters', ...
                'FontSize', obj.FONT_XL, 'FontWeight', 'bold', ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', obj.COLOR_BORDER);
            paramPanel.Layout.Row = 2;
            obj.ParamGrid = uigridlayout(paramPanel, [1, 1]);
            obj.ParamGrid.Padding = [obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM];
            obj.ParamGrid.RowSpacing = obj.SPACE_SM;
            obj.ParamGrid.BackgroundColor = obj.COLOR_SURFACE;

            paramPlaceholder = uilabel(obj.ParamGrid, ...
                'Text', 'Select an instrument to view and edit its parameters.', ...
                'FontSize', obj.FONT_LG, ...
                'HorizontalAlignment', 'center', ...
                'FontColor', obj.COLOR_TEXT_MUTED);
            paramPlaceholder.Layout.Row = 1;
            paramPlaceholder.Layout.Column = 1;

            % --- 右上: 数据绘图 + 采集表格 (跨行1-2) ---
            dataPanel = uipanel(obj.MainGrid, 'Title', 'Live Data View', ...
                'FontSize', obj.FONT_XL, 'FontWeight', 'bold', ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', obj.COLOR_BORDER);
            dataPanel.Layout.Row = [1, 2];
            dataPanel.Layout.Column = 2;
            dataGrid = uigridlayout(dataPanel, [2, 1]);
            dataGrid.RowHeight = {'3x', '1x'};
            dataGrid.Padding = [obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM];
            dataGrid.RowSpacing = obj.SPACE_SM;
            dataGrid.BackgroundColor = obj.COLOR_SURFACE;

            % 绘图容器: 工具栏 + tile 区域
            plotContainer = uigridlayout(dataGrid, [2, 1]);
            plotContainer.Layout.Row = 1;
            plotContainer.RowHeight = {32, '1x'};
            plotContainer.Padding = [0, 0, 0, 0];
            plotContainer.RowSpacing = obj.SPACE_XS;

            % 工具栏 (行1)
            toolbarGrid = uigridlayout(plotContainer, [1, 5]);
            toolbarGrid.Layout.Row = 1;
            toolbarGrid.ColumnWidth = {24, 42, 'fit', '1x', 88};
            toolbarGrid.Padding = [0, 0, 0, 0];
            toolbarGrid.ColumnSpacing = obj.SPACE_SM;

            uilabel(toolbarGrid, 'Text', char(9776), 'FontSize', obj.FONT_LG, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'center');

            uilabel(toolbarGrid, 'Text', 'Layout:', 'FontSize', obj.FONT_SM, ...
                'HorizontalAlignment', 'right');
            obj.PlotLayoutDropdown = uidropdown(toolbarGrid, ...
                'Items', {'Flow', '1x1', '2x1', '1x2', '2x2', '3x2', '3x3'}, ...
                'Value', 'Flow', ...
                'FontSize', obj.FONT_SM, ...
                'ValueChangedFcn', @(~,evt) obj.onPlotLayoutChanged(evt));

            obj.ToggleLogButton = uibutton(toolbarGrid, 'push', ...
                'Text', 'Hide Log', ...
                'FontSize', obj.FONT_XS, ...
                'BackgroundColor', obj.COLOR_BUTTON_BG, ...
                'Tooltip', 'Toggle Log (Ctrl+L)', ...
                'ButtonPushedFcn', @(~,~) obj.toggleLogCollapse());
            obj.ToggleLogButton.Layout.Column = 5;

            % 绘图 tile 区域 (行2)
            plotPanel = uipanel(plotContainer, 'BorderType', 'none');
            plotPanel.Layout.Row = 2;
            plotPanel.BackgroundColor = obj.COLOR_SURFACE;
            obj.PlotTileLayout = tiledlayout(plotPanel, 'flow');
            obj.PlotTileLayout.Padding = 'compact';
            obj.PlotTileLayout.TileSpacing = 'compact';
            title(obj.PlotTileLayout, 'Acquire data to display plots', 'FontSize', obj.FONT_SM);

            % 采集表格 (行2)
            obj.AcquisitionTable = uitable(dataGrid);
            obj.AcquisitionTable.Layout.Row = 2;
            obj.AcquisitionTable.ColumnName = {'Device', 'Type', 'Timestamp', 'Traces', 'Status'};
            obj.AcquisitionTable.ColumnWidth = {130, 65, 165, 70, 75};
            obj.AcquisitionTable.FontSize = obj.FONT_MD;
            obj.AcquisitionTable.BackgroundColor = obj.COLOR_SURFACE;
            obj.AcquisitionTable.Data = cell(0, 5);
            obj.AcquisitionTable.CellSelectionCallback = @(~,evt) obj.onDataRowSelected(evt);

            % --- 左下: 存储 + ELOG ---
            obj.BottomLeftGrid = uigridlayout(obj.MainGrid, [2, 1]);
            obj.BottomLeftGrid.Layout.Row = 2;
            obj.BottomLeftGrid.Layout.Column = 1;
            obj.BottomLeftGrid.RowHeight = {'fit', '1x'};
            obj.BottomLeftGrid.RowSpacing = obj.SPACE_SM;
            obj.BottomLeftGrid.Padding = [0, 0, 0, 0];

            obj.buildStoragePanel(obj.BottomLeftGrid);
            obj.buildElogPanel(obj.BottomLeftGrid);

            % --- 右列: 状态日志 (跨行1-2, 窄列) ---
            logPanel = uipanel(obj.MainGrid, 'Title', 'Status Log', ...
                'FontSize', obj.FONT_XL, 'FontWeight', 'bold', ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', obj.COLOR_BORDER);
            logPanel.Layout.Row = [1, 2];
            logPanel.Layout.Column = 3;
            logGrid = uigridlayout(logPanel, [1, 1]);
            logGrid.Padding = [obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM];

            obj.LogArea = uitextarea(logGrid, ...
                'Editable', 'off', ...
                'FontSize', obj.FONT_XS, ...
                'FontName', 'Consolas', ...
                'BackgroundColor', obj.COLOR_LOG_BG, ...
                'FontColor', obj.COLOR_TEXT_SECONDARY, ...
                'WordWrap', 'on', ...
                'Value', '');

            % --- 底部状态栏（第3行，跨所有列）---
            obj.StatusLabel = uilabel(obj.MainGrid, ...
                'Text', 'Ready', ...
                'FontSize', obj.FONT_SM, ...
                'FontWeight', 'bold', ...
                'FontColor', obj.COLOR_TEXT, ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'HorizontalAlignment', 'left');
            obj.StatusLabel.Layout.Row = 3;
            obj.StatusLabel.Layout.Column = [1, 3];
        end

        function buildStoragePanel(obj, parent)
            panel = uipanel(parent, 'Title', 'Data Storage', ...
                'FontSize', obj.FONT_XL, 'FontWeight', 'bold', ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', obj.COLOR_BORDER);
            panel.Layout.Row = 1;
            panel.Layout.Column = 1;

            storageGrid = uigridlayout(panel, [4, 5]);
            storageGrid.RowHeight = {28, 28, 28, 34};
            storageGrid.ColumnWidth = {'fit', '1x', 'fit', 'fit', 'fit'};
            storageGrid.Padding = [obj.SPACE_MD, obj.SPACE_MD, obj.SPACE_MD, obj.SPACE_MD];
            storageGrid.RowSpacing = obj.SPACE_SM;
            storageGrid.ColumnSpacing = obj.SPACE_SM;
            storageGrid.BackgroundColor = obj.COLOR_SURFACE;

            % 文件夹行
            uilabel(storageGrid, 'Text', 'Folder:', 'FontSize', obj.FONT_LG);
            obj.FolderEdit = uieditfield(storageGrid, 'text', ...
                'Value', obj.Config.Folder, 'FontSize', obj.FONT_MD, 'Editable', 'on');
            obj.FolderEdit.Layout.Column = [2, 4];
            browseButton = uibutton(storageGrid, 'push', 'Text', 'Browse', ...
                'FontSize', obj.FONT_MD, ...
                'BackgroundColor', obj.COLOR_BUTTON_BG, ...
                'ButtonPushedFcn', @(~,~) obj.onBrowseFolder());
            browseButton.Layout.Row = 1;
            browseButton.Layout.Column = 5;

            % 格式选择行
            uilabel(storageGrid, 'Text', 'Formats:', 'FontSize', obj.FONT_LG);
            formatSubGrid = uigridlayout(storageGrid, [1, 3]);
            formatSubGrid.Layout.Column = [2, 5];
            formatSubGrid.ColumnWidth = {'fit', 'fit', 'fit'};
            formatSubGrid.Padding = [0, 0, 0, 0];
            formatSubGrid.ColumnSpacing = obj.SPACE_LG;
            obj.MatCheck = uicheckbox(formatSubGrid, 'Text', 'MAT', ...
                'FontSize', obj.FONT_MD, 'Value', true);
            obj.CsvCheck = uicheckbox(formatSubGrid, 'Text', 'CSV', ...
                'FontSize', obj.FONT_MD, 'Value', true);
            obj.PngCheck = uicheckbox(formatSubGrid, 'Text', 'PNG', ...
                'FontSize', obj.FONT_MD, 'Value', false);

            % 操作行
            obj.AutoSaveCheck = uicheckbox(storageGrid, ...
                'Text', 'Auto-save after acquire', 'FontSize', obj.FONT_MD, 'Value', true);
            obj.AutoSaveCheck.Layout.Column = [1, 2];
            obj.AutoSaveCheck.Layout.Row = 3;

            saveAllButton = uibutton(storageGrid, 'push', 'Text', 'Save All', ...
                'FontSize', obj.FONT_MD, ...
                'BackgroundColor', obj.COLOR_PRIMARY, 'FontColor', [1 1 1], ...
                'Tooltip', 'Save All (Ctrl+S)', ...
                'ButtonPushedFcn', @(~,~) obj.onSaveAll());
            saveSessionButton = uibutton(storageGrid, 'push', 'Text', 'Save Session', ...
                'FontSize', obj.FONT_MD, ...
                'ButtonPushedFcn', @(~,~) obj.onSaveSession(), ...
                'BackgroundColor', obj.COLOR_SUCCESS, 'FontColor', [1 1 1]);
            saveSelectedButton = uibutton(storageGrid, 'push', 'Text', 'Save Selected', ...
                'FontSize', obj.FONT_MD, ...
                'BackgroundColor', obj.COLOR_ACCENT, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) obj.onSaveSelected());
            clearMemButton = uibutton(storageGrid, 'push', 'Text', 'Clear', ...
                'FontSize', obj.FONT_MD, ...
                'ButtonPushedFcn', @(~,~) obj.onClearMemory(), ...
                'BackgroundColor', obj.COLOR_DANGER, 'FontColor', [1 1 1]);
            saveAllButton.Layout.Row = 4;
            saveAllButton.Layout.Column = 1;
            saveSessionButton.Layout.Row = 4;
            saveSessionButton.Layout.Column = 2;
            saveSelectedButton.Layout.Row = 4;
            saveSelectedButton.Layout.Column = 3;
            clearMemButton.Layout.Row = 4;
            clearMemButton.Layout.Column = 4;
        end

        function buildElogPanel(obj, parent)
            panel = uipanel(parent, 'Title', '', ...
                'BackgroundColor', obj.COLOR_SURFACE, ...
                'BorderType', 'line', 'BorderWidth', 1, ...
                'HighlightColor', obj.COLOR_BORDER);
            panel.Layout.Row = 2;
            panel.Layout.Column = 1;

            % 外层: 头部栏 + 内容区
            outerGrid = uigridlayout(panel, [2, 1]);
            outerGrid.RowHeight = {30, '1x'};
            outerGrid.Padding = [0, 0, 0, 0];
            outerGrid.RowSpacing = 0;
            outerGrid.BackgroundColor = obj.COLOR_SURFACE;

            % 头部栏: [Toggle ▼/▲] [ELOG Upload title] [Status] [Upload button]
            headerGrid = uigridlayout(outerGrid, [1, 5]);
            headerGrid.Layout.Row = 1;
            headerGrid.ColumnWidth = {24, 'fit', '1x', 'fit', 60};
            headerGrid.Padding = [obj.SPACE_SM, obj.SPACE_XS, obj.SPACE_SM, obj.SPACE_XS];
            headerGrid.ColumnSpacing = obj.SPACE_SM;
            headerGrid.BackgroundColor = obj.COLOR_SURFACE_ALT;

            toggleBtn = uibutton(headerGrid, 'push', ...
                'Text', char(9660), 'FontSize', 10, ...
                'BackgroundColor', obj.COLOR_BUTTON_BG, ...
                'ButtonPushedFcn', @(~,~) obj.toggleElogCollapse());
            obj.ElogToggleButton = toggleBtn;

            uilabel(headerGrid, 'Text', 'ELOG Upload', ...
                'FontSize', obj.FONT_LG, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'left');

            obj.ElogStatusLabel = uilabel(headerGrid, ...
                'Text', 'Idle', 'FontSize', 10, ...
                'FontColor', obj.COLOR_TEXT_MUTED);
            obj.ElogStatusLabel.Layout.Column = 3;

            uploadBtn = uibutton(headerGrid, 'push', ...
                'Text', 'Upload', 'FontSize', obj.FONT_XS, ...
                'ButtonPushedFcn', @(~,~) obj.onUploadElog(), ...
                'BackgroundColor', obj.COLOR_PRIMARY, 'FontColor', [1 1 1]);
            uploadBtn.Layout.Column = 5;

            % 内容区 (可折叠)
            elogGrid = uigridlayout(outerGrid, [10, 4]);
            elogGrid.Layout.Row = 2;
            elogGrid.RowHeight = {24, 24, 24, 24, 24, 24, 24, 44, 26, 18};
            elogGrid.ColumnWidth = {'fit', '1x', 'fit', '1x'};
            elogGrid.Padding = [obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM];
            elogGrid.RowSpacing = obj.SPACE_SM;
            elogGrid.ColumnSpacing = obj.SPACE_SM;
            elogGrid.BackgroundColor = obj.COLOR_SURFACE;
            obj.ElogContentGrid = elogGrid;

            % 1: Server : Port
            uilabel(elogGrid, 'Text', 'Server:', 'FontSize', obj.FONT_XS);
            obj.ServerEdit = uieditfield(elogGrid, 'text', ...
                'Value', obj.Config.ElogServer, 'FontSize', obj.FONT_XS);
            obj.ServerEdit.Layout.Column = 2;
            uilabel(elogGrid, 'Text', 'Port:', 'FontSize', obj.FONT_XS);
            obj.PortEdit = uieditfield(elogGrid, 'numeric', ...
                'Value', obj.Config.ElogPort, 'FontSize', obj.FONT_XS, ...
                'Limits', [1, 65535], 'RoundFractionalValues', 'on');
            obj.PortEdit.Layout.Column = 4;

            % 2: Logbook
            uilabel(elogGrid, 'Text', 'Logbook:', 'FontSize', obj.FONT_XS);
            obj.LogbookDrop = uidropdown(elogGrid, 'FontSize', obj.FONT_XS, ...
                'Items', cellstr(string(obj.Config.ElogLogbooks)), ...
                'Value', obj.pickDropDownValue(obj.Config.ElogLogbooks, ...
                    obj.Config.ElogSelectedLogbook), ...
                'Editable', 'on');
            obj.LogbookDrop.Layout.Column = [2, 4];

            % 3: Author
            uilabel(elogGrid, 'Text', 'Author:', 'FontSize', obj.FONT_XS);
            obj.AuthorDrop = uidropdown(elogGrid, 'FontSize', obj.FONT_XS, ...
                'Items', cellstr(string(obj.Config.ElogAuthors)), ...
                'Value', obj.pickDropDownValue(obj.Config.ElogAuthors, ...
                    obj.Config.ElogSelectedAuthor), ...
                'Editable', 'on');
            obj.AuthorDrop.Layout.Column = [2, 4];

            % 4: XOI/Design : Type
            uilabel(elogGrid, 'Text', 'XOI/Design:', 'FontSize', obj.FONT_XS);
            obj.DesignDrop = uidropdown(elogGrid, 'FontSize', obj.FONT_XS, ...
                'Items', cellstr(string(obj.Config.ElogDesign)), ...
                'Value', obj.pickDropDownValue(obj.Config.ElogDesign, ...
                    obj.Config.ElogSelectedDesign), ...
                'Editable', 'off');
            obj.DesignDrop.Layout.Column = 2;
            uilabel(elogGrid, 'Text', 'Type:', 'FontSize', obj.FONT_XS);
            obj.TypeDrop = uidropdown(elogGrid, 'FontSize', obj.FONT_XS, ...
                'Items', cellstr(string(obj.Config.ElogType)), ...
                'Value', obj.pickDropDownValue(obj.Config.ElogType, ...
                    obj.Config.ElogSelectedType), ...
                'Editable', 'off');
            obj.TypeDrop.Layout.Column = 4;

            % 5: Wafer : Chip
            uilabel(elogGrid, 'Text', 'Wafer:', 'FontSize', obj.FONT_XS);
            obj.WaferEdit = uieditfield(elogGrid, 'text', 'FontSize', obj.FONT_XS, ...
                'Value', obj.Config.ElogWafer);
            obj.WaferEdit.Layout.Column = 2;
            uilabel(elogGrid, 'Text', 'Chip:', 'FontSize', obj.FONT_XS);
            obj.ChipEdit = uieditfield(elogGrid, 'text', 'FontSize', obj.FONT_XS, ...
                'Value', obj.Config.ElogChip);
            obj.ChipEdit.Layout.Column = 4;

            % 6: Field : Sample
            uilabel(elogGrid, 'Text', 'Field:', 'FontSize', obj.FONT_XS);
            obj.FieldEdit = uieditfield(elogGrid, 'text', 'FontSize', obj.FONT_XS, ...
                'Value', obj.Config.ElogField);
            obj.FieldEdit.Layout.Column = 2;
            uilabel(elogGrid, 'Text', 'Sample:', 'FontSize', obj.FONT_XS);
            obj.SampleEdit = uieditfield(elogGrid, 'text', 'FontSize', obj.FONT_XS, ...
                'Value', obj.Config.ElogSample);
            obj.SampleEdit.Layout.Column = 4;

            % 7: Measurement
            uilabel(elogGrid, 'Text', 'Meas.:', 'FontSize', obj.FONT_XS);
            obj.MeasurementEdit = uieditfield(elogGrid, 'text', 'FontSize', obj.FONT_XS, 'Value', '');
            obj.MeasurementEdit.Layout.Column = [2, 4];

            % 8: Comments (compact)
            uilabel(elogGrid, 'Text', 'Comments:', 'FontSize', obj.FONT_XS);
            obj.CommentsArea = uitextarea(elogGrid, 'FontSize', obj.FONT_XS, ...
                'Value', '', 'Placeholder', 'ELOG comments / notes...');
            obj.CommentsArea.Layout.Column = [2, 4];

            % 9: Upload row (checkboxes only — Upload button is in header)
            obj.AttachSnapshotCheck = uicheckbox(elogGrid, ...
                'Text', 'Attach snapshot (.png)', 'FontSize', obj.FONT_XS, 'Value', true);
            obj.AttachSnapshotCheck.Layout.Column = 1;
            obj.AttachSnapshotCheck.Layout.Row = 9;

            obj.AutoElogCheck = uicheckbox(elogGrid, ...
                'Text', 'Auto-upload on save', 'FontSize', obj.FONT_XS, ...
                'Value', obj.Config.ElogAutoUpload);
            obj.AutoElogCheck.Layout.Column = 2;
            obj.AutoElogCheck.Layout.Row = 9;

            % 10: Status (collapsed view shows this in header instead)
            elogStatusLine = uilabel(elogGrid, ...
                'Text', '', 'FontSize', 10, 'FontColor', obj.COLOR_TEXT_MUTED);
            elogStatusLine.Layout.Row = 10;
            elogStatusLine.Layout.Column = [1, 4];

            % 默认展开
            obj.ElogCollapsed = false;
        end

        function populateInstrumentRows(obj)
            registry = labdevices.core.InstrumentRegistry.all();
            allKeys = string(fieldnames(registry));
            obj.InstrumentKeys = allKeys;
            nInstruments = numel(allKeys);
            obj.ConnectionFailed = false(nInstruments, 1);

            % 表格数据（6列: Instrument, Type, IP, Status, Connect, Acquire）
            gray = obj.colorToHex(obj.COLOR_LAMP_OFF);
            tableData = cell(nInstruments, 6);
            for i = 1:nInstruments
                k = allKeys(i);
                entry = registry.(k);
                tableData{i, 1} = char(entry.displayName);
                tableData{i, 2} = char(entry.type);
                tableData{i, 3} = char(entry.ip);
                tableData{i, 4} = sprintf('<html><div style="background:%s;color:#475569;text-align:center;padding:2px 6px;border-radius:3px;font-weight:bold;">未连接</div></html>', gray);
                tableData{i, 5} = 'Connect';
                tableData{i, 6} = 'Acquire';
            end
            obj.InstrumentTable.Data = tableData;
            obj.InstrumentTable.UserData = allKeys;
        end

        function refreshParameterPanel(obj, key)
            % 隐藏所有已缓存的参数面板
            cacheKeys = obj.ParamControlCache.keys();
            for i = 1:numel(cacheKeys)
                entry = obj.ParamControlCache(cacheKeys{i});
                if isfield(entry, 'grid') && isvalid(entry.grid)
                    entry.grid.Visible = 'off';
                end
            end

            % 空选择 → 显示占位符
            if isempty(key) || strlength(key) == 0
                obj.ParamControls = struct();
                return;
            end

            registry = labdevices.core.InstrumentRegistry.all();
            k = char(key);
            if ~isfield(registry, k); return; end
            instrType = registry.(k).type;

            % 检查缓存：如果已有该仪器的面板，直接显示
            if obj.ParamControlCache.isKey(key)
                entry = obj.ParamControlCache(key);
                if isfield(entry, 'grid') && isvalid(entry.grid)
                    entry.grid.Visible = 'on';
                    obj.ParamControls = entry.controls;
                    return;
                end
            end

            % 未缓存 → 构建新面板
            params = labdevices.core.ParameterDef.forType(instrType);
            nParams = numel(params);

            if nParams == 0
                obj.ParamControls = struct();
                return;
            end

            fullParamGrid = uigridlayout(obj.ParamGrid, [nParams + 1, 3]);
            fullParamGrid.RowHeight = [repmat({'fit'}, 1, nParams), {'fit'}];
            fullParamGrid.ColumnWidth = {'1.5x', '2x', '0.5x'};
            fullParamGrid.Padding = [obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM, obj.SPACE_SM];
            fullParamGrid.RowSpacing = obj.SPACE_SM;
            fullParamGrid.ColumnSpacing = obj.SPACE_SM;
            fullParamGrid.BackgroundColor = obj.COLOR_SURFACE;
            fullParamGrid.Layout.Row = 1;
            fullParamGrid.Layout.Column = 1;

            newControls = struct();

            for i = 1:nParams
                pDef = params(i);

                lbl = uilabel(fullParamGrid, 'Text', char(pDef.Label), ...
                    'FontSize', obj.FONT_LG, 'Tooltip', char(pDef.Tooltip));
                lbl.Layout.Row = i;
                lbl.Layout.Column = 1;

                ctrlName = char(pDef.Name);
                switch pDef.Type
                    case "numeric"
                        ctrl = uieditfield(fullParamGrid, 'numeric', ...
                            'FontSize', obj.FONT_LG, 'Value', pDef.Default, ...
                            'Tooltip', char(pDef.Tooltip));
                    case "logical"
                        ctrl = uicheckbox(fullParamGrid, 'FontSize', obj.FONT_LG, ...
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
                        ctrl = uidropdown(fullParamGrid, 'FontSize', obj.FONT_LG, ...
                            'Items', items, 'Value', val, ...
                            'Tooltip', char(pDef.Tooltip));
                    otherwise
                        ctrl = uieditfield(fullParamGrid, 'text', 'FontSize', obj.FONT_LG, ...
                            'Value', string(pDef.Default));
                end
                ctrl.Layout.Row = i;
                ctrl.Layout.Column = 2;
                ctrl.Tag = ctrlName;

                if strlength(pDef.Unit) > 0
                    unitLbl = uilabel(fullParamGrid, 'Text', char(pDef.Unit), ...
                        'FontSize', obj.FONT_SM, 'FontColor', obj.COLOR_TEXT_SECONDARY);
                    unitLbl.Layout.Row = i;
                    unitLbl.Layout.Column = 3;
                end

                newControls.(ctrlName) = ctrl;
            end

            % 四按钮行
            btnRow = uigridlayout(fullParamGrid, [1, 5]);
            btnRow.Layout.Row = nParams + 1;
            btnRow.Layout.Column = [1, 3];
            btnRow.ColumnWidth = {'fit', 'fit', 'fit', '1x', 'fit'};
            btnRow.Padding = [0, obj.SPACE_SM, 0, 0];
            btnRow.ColumnSpacing = obj.SPACE_SM;

            uibutton(btnRow, 'push', 'Text', 'Apply', 'FontSize', obj.FONT_LG, ...
                'ButtonPushedFcn', @(~,~) obj.onApplyParameters(), ...
                'BackgroundColor', obj.COLOR_TEAL, 'FontColor', [1 1 1], ...
                'Tooltip', 'Apply configuration only (no acquisition)');
            uibutton(btnRow, 'push', 'Text', 'Acquire', 'FontSize', obj.FONT_LG, ...
                'ButtonPushedFcn', @(~,~) obj.onAcquireSelected(), ...
                'BackgroundColor', obj.COLOR_SUCCESS, 'FontColor', [1 1 1], ...
                'Tooltip', 'Acquire with stored parameters');
            uibutton(btnRow, 'push', 'Text', 'Apply+Acquire', 'FontSize', obj.FONT_LG, ...
                'ButtonPushedFcn', @(~,~) obj.onApplyAndAcquire(), ...
                'BackgroundColor', obj.COLOR_PRIMARY, 'FontColor', [1 1 1], ...
                'Tooltip', 'Configure then acquire');
            uibutton(btnRow, 'push', 'Text', 'Reset', 'FontSize', obj.FONT_LG, ...
                'BackgroundColor', obj.COLOR_BUTTON_BG, ...
                'ButtonPushedFcn', @(~,~) obj.resetParameterDefaults());

            % 存入缓存
            cacheEntry.grid = fullParamGrid;
            cacheEntry.controls = newControls;
            obj.ParamControlCache(key) = cacheEntry;
            obj.ParamControls = newControls;
        end
    end

    %% ======================== 回调: 仪器操作 ========================
    methods (Access = private)
        function onConnect(obj, key)
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end
            idx = find(obj.InstrumentKeys == key, 1);
            try
                obj.Station.connect(key);
                obj.ConnectionFailed(idx) = false;
                obj.logMessage(sprintf("Connected: %s", key), "info");
            catch ME
                obj.ConnectionFailed(idx) = true;
                obj.logMessage(sprintf("Connect failed (%s): %s", key, ME.message), "error");
            end
            obj.updateStatusColumn();
            obj.updateStatusBar();
        end

        function onDisconnect(obj, key)
            idx = find(obj.InstrumentKeys == key, 1);
            try
                obj.Station.disconnect(key);
                obj.ConnectionFailed(idx) = false;
                obj.logMessage(sprintf("Disconnected: %s", key), "info");
            catch ME
                obj.logMessage(sprintf("Disconnect failed (%s): %s", key, ME.message), "error");
            end
            obj.updateStatusColumn();
            obj.updateStatusBar();
        end

        function onConnectAll(obj, ~, ~)
            if obj.IsBusy; obj.logMessage("System busy.", "warn"); return; end
            obj.setBusy(true);
            for i = 1:numel(obj.InstrumentKeys)
                key = obj.InstrumentKeys(i);
                try
                    obj.Station.connect(key);
                    obj.ConnectionFailed(i) = false;
                catch ME
                    obj.ConnectionFailed(i) = true;
                    obj.logMessage(sprintf("Connect failed (%s): %s", key, ME.message), "error");
                end
            end
            nOk = sum(~obj.ConnectionFailed);
            obj.logMessage(sprintf("Connected: %d/%d instruments.", nOk, numel(obj.InstrumentKeys)), "info");
            obj.setBusy(false);
            obj.updateStatusColumn();
            obj.updateStatusBar();
        end

        function onDisconnectAll(obj, ~, ~)
            obj.Station.disconnectAll();
            obj.ConnectionFailed(:) = false;
            obj.logMessage("All instruments disconnected.", "info");
            obj.updateStatusColumn();
            obj.updateStatusBar();
        end

        function onInstrumentSelected(obj, evt)
            indices = evt.Indices;
            if isempty(indices); return; end
            row = indices(1); col = indices(2);
            key = obj.InstrumentKeys(row);

            % 6列: 1=Instrument,2=Type,3=IP,4=Status,5=Connect,6=Acquire
            if col == 5; obj.onConnect(key); return;
            elseif col == 6; obj.onAcquire(key); return;
            elseif col == 4; return;
            end

            obj.SelectedKey = key;
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
            total = numel(connected);
            obj.logMessage(sprintf("Acquiring all (%d instruments)...", total), "info");
            try
                results = obj.Station.acquireAll([], obj.AcquireParamsMap);
                resultKeys = results.keys();
                for i = 1:numel(resultKeys)
                    k = resultKeys{i};
                    obj.logMessage(sprintf("[%d/%d] Processing: %s", i, numel(resultKeys), k), "info");
                    obj.onAcquireDone(k, results(k));
                end
                obj.logMessage(sprintf("AcquireAll complete: %d/%d succeeded.", ...
                    results.Count, total), "info");
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

            try
                obj.plotAcquisitionData(char(key), data);
            catch ME
                obj.logMessage(sprintf("Plot failed (%s): %s", key, ME.message), "error");
            end

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

        %% ---- 绘图布局控制 ----
        function onPlotLayoutChanged(obj, evt)
            mode = evt.Value;
            if strcmp(mode, obj.PlotLayoutMode); return; end
            obj.logMessage(sprintf("Switching plot layout to: %s", mode), "info");
            obj.reconfigurePlotLayout(mode);
        end

        function reconfigurePlotLayout(obj, mode)
            wasFlow = strcmp(obj.PlotLayoutMode, 'Flow');
            isFlow = strcmp(mode, 'Flow');

            if strcmp(mode, 'Flow')
                gridRows = NaN; gridCols = NaN;
            else
                parts = split(mode, 'x');
                gridRows = str2double(parts{1});
                gridCols = str2double(parts{2});
            end

            hasPlots = keys(obj.PlotAxesMap);
            plotParent = obj.PlotTileLayout.Parent;

            % 仅在 flow↔fixed 切换时需要重建 tiledlayout
            needRebuild = (wasFlow ~= isFlow);

            if needRebuild
                delete(obj.PlotTileLayout);
                obj.PlotAxesMap = containers.Map();

                if isnan(gridRows)
                    obj.PlotTileLayout = tiledlayout(plotParent, 'flow');
                else
                    obj.PlotTileLayout = tiledlayout(plotParent, gridRows, gridCols);
                end
                obj.PlotTileLayout.Padding = 'compact';
                obj.PlotTileLayout.TileSpacing = 'compact';
                title(obj.PlotTileLayout, 'Acquire data to display plots', 'FontSize', obj.FONT_SM);
            else
                % 固定网格间切换：直接改 GridSize
                if ~isnan(gridRows)
                    obj.PlotTileLayout.GridSize = [gridRows, gridCols];
                end
            end

            obj.PlotLayoutMode = mode;

            % 恢复已有绘图
            if ~isempty(hasPlots) && ~isempty(obj.AcquisitionStore)
                replotCount = 0;
                maxTiles = gridRows * gridCols;

                for i = 1:numel(obj.AcquisitionStore)
                    entry = obj.AcquisitionStore{i};
                    key = entry{1}; data = entry{2};
                    if any(strcmp(hasPlots, key))
                        if ~isnan(maxTiles) && replotCount >= maxTiles
                            obj.logMessage(sprintf( ...
                                "Grid %s has only %d tiles; remaining plots not shown.", mode, maxTiles), "warn");
                            break;
                        end
                        obj.plotAcquisitionData(key, data);
                        replotCount = replotCount + 1;
                    end
                end

                if replotCount > 0
                    obj.logMessage(sprintf( ...
                        "Layout %s: %d plot(s) redistributed.", mode, replotCount), "info");
                end
            end
        end

        function toggleElogCollapse(obj)
            if obj.ElogCollapsed
                obj.ElogContentGrid.Visible = 'on';
                obj.ElogToggleButton.Text = char(9650);  % ▲
                obj.ElogCollapsed = false;
                obj.BottomLeftGrid.RowHeight{2} = '1x';
            else
                obj.ElogContentGrid.Visible = 'off';
                obj.ElogToggleButton.Text = char(9660);  % ▼
                obj.ElogCollapsed = true;
                obj.BottomLeftGrid.RowHeight{2} = 'fit';
            end
        end

        function toggleLogCollapse(obj)
            if obj.LogCollapsed
                obj.MainGrid.ColumnWidth = {'1.1x', '1.5x', '0.4x'};
                obj.ToggleLogButton.Text = 'Hide Log';
                obj.LogCollapsed = false;
                obj.logMessage('Log panel expanded.', 'info');
            else
                obj.MainGrid.ColumnWidth = {'1.1x', '1.5x', 28};
                obj.ToggleLogButton.Text = 'Show Log';
                obj.LogCollapsed = true;
                obj.logMessage('Log panel collapsed.', 'info');
            end
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
            if ~isfield(registry, k); args = {}; return; end
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
            total = numel(obj.AcquisitionStore);
            for i = 1:total
                try
                    entry = obj.AcquisitionStore{i};
                    obj.logMessage(sprintf("[%d/%d] Saving: %s", i, total, entry{1}), "info");
                    obj.doSave(entry{2}, entry{1});
                catch ME
                    obj.logMessage(sprintf("Save failed #%d: %s", i, ME.message), "error");
                end
            end
            obj.logMessage(sprintf("Saved %d acquisitions.", numel(obj.AcquisitionStore)), "info");
        end

        function onSaveSession(obj, ~, ~)
            % 仅保存每台仪器最新一次采集的结果
            if isempty(obj.AcquisitionStore)
                obj.logMessage("No data to save.", "warn"); return;
            end

            combined = struct();
            seen = containers.Map();
            % 从尾部向前遍历，每台仪器只取最新
            for i = numel(obj.AcquisitionStore):-1:1
                entry = obj.AcquisitionStore{i};
                key = entry{1};
                if seen.isKey(key); continue; end
                seen(key) = true;
                data = entry{2};
                fieldName = matlab.lang.makeValidName(key);
                combined.(fieldName) = data;
            end

            ts = datetime("now", "Format", "yyyy_MM_dd-HH_mm_ss");
            matPath = fullfile(obj.FolderEdit.Value, ['session_' char(ts) '.mat']);
            if ~isfolder(obj.FolderEdit.Value); mkdir(obj.FolderEdit.Value); end
            save(matPath, "-struct", "combined", "-v7.3");
            obj.rememberSavedFiles({matPath});
            obj.logMessage(sprintf("Session saved: %s (%d instruments, latest each)", ...
                matPath, seen.Count), "info");
        end

        function onSaveSelected(obj, ~, ~)
            if isempty(obj.AcquisitionStore)
                obj.logMessage("No data to save.", "warn"); return;
            end
            % 获取 AcquisitionTable 当前选中行
            sel = obj.getSelectedTableRows();
            if isempty(sel)
                obj.logMessage("No rows selected in acquisition table.", "warn"); return;
            end
            for r = 1:numel(sel)
                row = sel(r);
                if row > numel(obj.AcquisitionStore); continue; end
                try
                    entry = obj.AcquisitionStore{row};
                    obj.doSave(entry{2}, entry{1});
                catch ME
                    obj.logMessage(sprintf("Save row #%d failed: %s", row, ME.message), "error");
                end
            end
            obj.logMessage(sprintf("Saved %d selected acquisitions.", numel(sel)), "info");
        end

        function onClearMemory(obj, ~, ~)
            n = numel(obj.AcquisitionStore);
            if n == 0
                obj.logMessage("Memory already empty.", "info"); return;
            end
            answer = uiconfirm(obj.Figure, ...
                sprintf('Clear all %d acquisitions from memory?\nThis cannot be undone.', n), ...
                'Confirm Clear', 'Options', {'Clear', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(answer, 'Clear'); return; end
            obj.AcquisitionStore = {};
            obj.AcquisitionTable.Data = cell(0, 5);
            axKeys = obj.PlotAxesMap.keys();
            for i = 1:numel(axKeys)
                ax = obj.PlotAxesMap(axKeys{i});
                if isvalid(ax); cla(ax); end
            end
            remove(obj.PlotAxesMap, axKeys);
            obj.LastSavedPaths = {};
            obj.logMessage(sprintf("Cleared %d acquisitions from memory.", n), "info");
            obj.updateStatusBar();
        end

        function rows = getSelectedTableRows(obj)
            rows = [];
            try
                sel = obj.AcquisitionTable.Selection;
                if isempty(sel); return; end
                rows = unique(sel(:, 1))';
            catch
            end
        end

        function elog = collectElogParams(obj)
            elog = struct();
            elog.Server = char(string(obj.ServerEdit.Value));
            elog.Port = obj.PortEdit.Value;
            elog.Logbook = char(string(obj.LogbookDrop.Value));
            elog.Author = char(string(obj.AuthorDrop.Value));
            elog.Sample = obj.buildElogSampleIdentifier();
            elog.Measurement = char(string(obj.MeasurementEdit.Value));
            elog.Type = char(string(obj.TypeDrop.Value));
            elog.Comments = obj.buildElogBodyText();
            elog.AdditionalAttributes = struct( ...
                'XOI', char(string(obj.DesignDrop.Value)), ...
                'Measuretype', char(string(obj.TypeDrop.Value)));
            elog.Executable = char(string(obj.Config.ElogExecutable));
        end

        function saved = doSave(obj, data, key)
            formats = {};
            if obj.MatCheck.Value; formats{end + 1} = 'mat'; end %#ok<AGROW>
            if obj.CsvCheck.Value; formats{end + 1} = 'csv'; end %#ok<AGROW>
            if obj.PngCheck.Value; formats{end + 1} = 'png'; end %#ok<AGROW>
            if isempty(formats); obj.logMessage("No formats selected.", "warn"); saved = struct(); return; end

            uploadToElog = false;
            elogParams = struct();
            if obj.AutoElogCheck.Value
                uploadToElog = true;
                elogParams = obj.collectElogParams();
            end

            saved = labdevices.core.DataExporter.saveAcquisition(data, ...
                'Folder', obj.resolveInstrumentSaveFolder(data), 'Formats', formats, ...
                'UploadToElog', uploadToElog, 'ElogParams', elogParams);
            obj.rememberSavedFiles(saved);
            if isfield(saved, 'mat')
                obj.logMessage(sprintf("Saved: %s", saved.mat), "info");
            end
        end

        function onUploadElog(obj, ~, ~)
            if isempty(char(string(obj.LogbookDrop.Value)))
                obj.ElogStatusLabel.Text = 'Missing logbook';
                obj.ElogStatusLabel.FontColor = obj.COLOR_DANGER; return;
            end
            if isempty(char(string(obj.AuthorDrop.Value)))
                obj.ElogStatusLabel.Text = 'Missing author';
                obj.ElogStatusLabel.FontColor = obj.COLOR_DANGER; return;
            end

            obj.ElogStatusLabel.Text = 'Uploading...';
            obj.ElogStatusLabel.FontColor = obj.COLOR_WARNING;
            drawnow;

            opts = obj.collectElogParams();

            if obj.AttachSnapshotCheck.Value
                opts.Snapshot = obj.Station.getSnapshot();
            end

            [opts.Attachments, ~] = obj.createElogAttachments();

            try
                [success, response] = labdevices.core.DataExporter.uploadToElog(opts);
                if success
                    obj.ElogStatusLabel.Text = 'Upload OK';
                    obj.ElogStatusLabel.FontColor = obj.COLOR_SUCCESS;
                    obj.appendElogLog(response, opts);
                    obj.logMessage(sprintf("ELOG upload OK: %s", strtrim(response)), "info");
                else
                    obj.ElogStatusLabel.Text = 'Upload failed';
                    obj.ElogStatusLabel.FontColor = obj.COLOR_DANGER;
                    obj.appendElogLog(response, opts);
                    obj.logMessage(sprintf("ELOG upload failed: %s", response), "error");
                end
            catch ME
                obj.ElogStatusLabel.Text = 'Upload error';
                obj.ElogStatusLabel.FontColor = obj.COLOR_DANGER;
                obj.appendElogLog(ME.message, opts);
                obj.logMessage(sprintf("ELOG upload error: %s", ME.message), "error");
            end
        end
    end

    %% ======================== 回调: 生命周期 ========================
    methods (Access = private)
        function onFigureClose(obj, ~, ~)
            obj.delete();
        end

        function onKeyPress(obj, evt)
            modifiers = evt.Modifier;
            key = evt.Key;
            ctrl = any(strcmp(modifiers, 'control'));

            if ctrl
                switch key
                    case 'return'
                        obj.onAcquireAll();
                    case 's'
                        obj.onSaveAll();
                    case 'd'
                        obj.onDisconnectAll();
                    case 'l'
                        obj.toggleLogCollapse();
                    case 'e'
                        obj.toggleElogCollapse();
                    case 'c'
                        obj.onConnectAll();
                    otherwise
                        return;
                end
                obj.logMessage(sprintf("Shortcut: Ctrl+%s", upper(key)), "info");
            end
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

        function updateStatusColumn(obj)
            data = obj.InstrumentTable.Data;
            green = obj.colorToHex(obj.COLOR_LAMP_ON);
            red = obj.colorToHex(obj.COLOR_DANGER);
            gray = obj.colorToHex(obj.COLOR_LAMP_OFF);
            for i = 1:numel(obj.InstrumentKeys)
                if i <= size(data, 1)
                    if obj.Station.isConnected(obj.InstrumentKeys(i))
                        data{i, 4} = sprintf('<html><div style="background:%s;color:#166534;text-align:center;padding:2px 6px;border-radius:3px;font-weight:bold;">已连接</div></html>', green);
                    elseif obj.ConnectionFailed(i)
                        data{i, 4} = sprintf('<html><div style="background:%s;color:#991b1b;text-align:center;padding:2px 6px;border-radius:3px;font-weight:bold;">连接失败</div></html>', red);
                    else
                        data{i, 4} = sprintf('<html><div style="background:%s;color:#475569;text-align:center;padding:2px 6px;border-radius:3px;font-weight:bold;">未连接</div></html>', gray);
                    end
                end
            end
            obj.InstrumentTable.Data = data;
        end

        function hex = colorToHex(~, rgb)
            hex = sprintf('#%02X%02X%02X', round(rgb * 255));
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
                obj.StatusLabel.FontColor = obj.COLOR_WARNING;
                drawnow;
            else
                obj.StatusLabel.FontColor = obj.COLOR_TEXT;
                obj.updateStatusBar();
            end
        end

        function config = loadConfig(~, configPath)
            config = struct();
            config.Folder = fullfile(fileparts(mfilename('fullpath')), 'output');
            config.ElogServer = '192.168.1.72';
            config.ElogPort = 8080;
            config.ElogLogbooks = {'EPIC', 'LabLog', 'MeasurementLog'};
            config.ElogAuthors = {'Li_Yansong', 'Yang_Nianjia', 'Wu_Xinyi', 'Other'};
            config.ElogSelectedLogbook = 'EPIC';
            config.ElogSelectedAuthor = 'Li_Yansong';
            config.ElogExecutable = 'D:\Program Files (x86)\ELOG\elog.exe';
            config.ElogDesign = {'SiN', 'LNOI'};
            config.ElogSelectedDesign = '';
            config.ElogWafer = '';
            config.ElogField = '';
            config.ElogChip = '';
            config.ElogType = {'MRR', 'OFDR', 'PHASE'};
            config.ElogSelectedType = '';
            config.ElogSample = '';
            config.ElogAutoUpload = false;

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

            if isfield(config, 'ElogServer')
                currentServer = char(string(config.ElogServer));
                if any(strcmpi(currentServer, {'lpqm1srv2.epfl.ch', '192.168.1.9'}))
                    config.ElogServer = '192.168.1.72';
                end
            end
        end

        function saveConfig(obj)
            appConfig = obj.Config;
            appConfig.Folder = obj.FolderEdit.Value;
            appConfig.ElogServer = obj.ServerEdit.Value;
            appConfig.ElogPort = obj.PortEdit.Value;
            appConfig.ElogLogbooks = cellstr(string(obj.LogbookDrop.Items));
            appConfig.ElogAuthors = cellstr(string(obj.AuthorDrop.Items));
            appConfig.ElogSelectedLogbook = char(string(obj.LogbookDrop.Value));
            appConfig.ElogSelectedAuthor = char(string(obj.AuthorDrop.Value));
            appConfig.ElogExecutable = obj.Config.ElogExecutable;
            appConfig.ElogDesign = cellstr(string(obj.DesignDrop.Items));
            appConfig.ElogSelectedDesign = char(string(obj.DesignDrop.Value));
            appConfig.ElogWafer = char(string(obj.WaferEdit.Value));
            appConfig.ElogField = char(string(obj.FieldEdit.Value));
            appConfig.ElogChip = char(string(obj.ChipEdit.Value));
            appConfig.ElogType = cellstr(string(obj.TypeDrop.Items));
            appConfig.ElogSelectedType = char(string(obj.TypeDrop.Value));
            appConfig.ElogSample = char(string(obj.SampleEdit.Value));
            appConfig.ElogAutoUpload = obj.AutoElogCheck.Value;
            folder = fileparts(obj.ConfigPath);
            if ~isempty(folder) && ~isfolder(folder); mkdir(folder); end
            save(obj.ConfigPath, 'appConfig');
        end

        function value = pickDropDownValue(~, items, preferred)
            items = cellstr(string(items));
            preferred = char(string(preferred));
            if isempty(items)
                value = '';
            elseif ~isempty(preferred) && any(strcmp(items, preferred))
                value = preferred;
            else
                value = items{1};
            end
        end

        function body = buildElogBodyText(obj)
            sections = {};

            sampleId = obj.buildElogSampleIdentifier();
            if ~isempty(sampleId)
                sections{end + 1} = labdevices.core.DataExporter.escapeElogText(sampleId); %#ok<AGROW>
            end

            commentText = obj.textValueToBlock(obj.CommentsArea.Value);
            if ~isempty(commentText)
                sections{end + 1} = sprintf('Comments:\\n%s', commentText); %#ok<AGROW>
            end

            savedSummary = obj.buildSavedFilesSummary();
            if ~isempty(savedSummary)
                sections{end + 1} = savedSummary; %#ok<AGROW>
            end

            if isempty(sections)
                body = ' ';
            else
                body = strjoin(sections, '\n\n');
            end
        end

        function sampleId = buildElogSampleIdentifier(obj)
            design = strtrim(char(string(obj.DesignDrop.Value)));
            wafer = strtrim(char(string(obj.WaferEdit.Value)));
            field = strtrim(char(string(obj.FieldEdit.Value)));
            chip = strtrim(char(string(obj.ChipEdit.Value)));
            sample = strtrim(char(string(obj.SampleEdit.Value)));

            if isempty(wafer) && isempty(field) && isempty(chip) && isempty(sample)
                sampleId = '';
                return;
            end

            if ~isempty(design) && ~isempty(wafer) && contains(wafer, design, 'IgnoreCase', true)
                sampleId = sprintf('%s_%s_%s_%s_%s', design, wafer, field, chip, sample);
            else
                sampleId = sprintf('%s_%s_%s_%s', wafer, field, chip, sample);
            end

            sampleId = regexprep(sampleId, '_+$', '');
            sampleId = regexprep(sampleId, '^_+', '');
        end

        function text = textValueToBlock(~, value)
            if isempty(value)
                text = '';
                return;
            end

            if iscell(value)
                lines = string(value(:));
            elseif isstring(value)
                lines = value(:);
            else
                lines = string(value);
            end

            lines = lines(strlength(strtrim(lines)) > 0);
            if isempty(lines)
                text = '';
                return;
            end

            escaped = arrayfun(@(s) string(labdevices.core.DataExporter.escapeElogText(char(s))), ...
                lines, 'UniformOutput', true);
            text = strjoin(cellstr(escaped), '\n');
        end

        function summary = buildSavedFilesSummary(obj)
            if isempty(obj.LastSavedPaths)
                summary = '';
                return;
            end

            existing = obj.LastSavedPaths(cellfun(@(p) isfile(p), obj.LastSavedPaths));
            if isempty(existing)
                summary = '';
                return;
            end

            maxCount = min(6, numel(existing));
            lines = cell(1, maxCount + 1);
            lines{1} = 'Saved files:';
            for i = 1:maxCount
                lines{i + 1} = sprintf('- %s', ...
                    labdevices.core.DataExporter.escapeElogText(existing{i}));
            end
            summary = strjoin(lines, '\n');
        end

        function rememberSavedFiles(obj, saved)
            paths = {};

            if isstruct(saved)
                if isfield(saved, 'mat') && ~isempty(saved.mat)
                    paths{end + 1} = char(string(saved.mat)); %#ok<AGROW>
                end
                if isfield(saved, 'png') && ~isempty(saved.png)
                    paths{end + 1} = char(string(saved.png)); %#ok<AGROW>
                end
                if isfield(saved, 'csv') && ~isempty(saved.csv)
                    csvPaths = saved.csv;
                    if ischar(csvPaths) || isstring(csvPaths)
                        paths{end + 1} = char(string(csvPaths)); %#ok<AGROW>
                    elseif iscell(csvPaths)
                        for c = 1:numel(csvPaths)
                            paths{end + 1} = char(string(csvPaths{c})); %#ok<AGROW>
                        end
                    end
                end
            elseif iscell(saved)
                paths = cellfun(@(p) char(string(p)), saved, 'UniformOutput', false);
            elseif ischar(saved) || isstring(saved)
                paths = {char(string(saved))};
            end

            if isempty(paths)
                return;
            end

            obj.LastSavedPaths = [paths(:)', obj.LastSavedPaths];
            obj.LastSavedPaths = unique(obj.LastSavedPaths, 'stable');
            if numel(obj.LastSavedPaths) > 20
                obj.LastSavedPaths = obj.LastSavedPaths(1:20);
            end
        end

        function [attachments, cleanupPaths] = createElogAttachments(obj)
            attachments = {};
            cleanupPaths = {};

            if ~obj.AttachSnapshotCheck.Value
                return;
            end

            % Save to output folder (follow FitResGui pattern)
            outFolder = char(string(obj.FolderEdit.Value));
            if ~isfolder(outFolder); mkdir(outFolder); end
            snapshotPath = fullfile(outFolder, sprintf('elog_snapshot_%s.png', ...
                char(datetime("now", "Format", "yyyyMMdd_HHmmss_SSS"))));
            try
                exportgraphics(obj.Figure, snapshotPath, 'Resolution', 150);
            catch ME
                obj.logMessage(sprintf("Snapshot export failed: %s", ME.message), "warn");
                return;
            end

            if isfile(snapshotPath)
                attachments{end + 1} = snapshotPath; %#ok<AGROW>
            end
        end

        function cleanupTemporaryFiles(~, paths)
            for i = 1:numel(paths)
                try
                    if isfile(paths{i})
                        delete(paths{i});
                    end
                catch
                end
            end
        end

        function folder = resolveInstrumentSaveFolder(obj, data)
            baseFolder = strtrim(char(string(obj.FolderEdit.Value)));
            deviceName = 'acquisition';
            if isfield(data, 'device') && ~isempty(data.device)
                deviceName = char(string(data.device));
            end
            dateFolder = char(datetime("now", "Format", "yyyy_MM_dd"));
            folder = fullfile(baseFolder, deviceName, dateFolder);
            if ~isfolder(folder)
                mkdir(folder);
            end
        end

        function appendElogLog(obj, response, opts)
            logFolder = fullfile(obj.FolderEdit.Value, '_elog_log');
            if ~isfolder(logFolder)
                mkdir(logFolder);
            end

            stamp = char(datetime("now", "Format", "yyyy_MM_dd-HH_mm_ss_SSS"));
            logPath = fullfile(logFolder, ['elog_' stamp '.txt']);
            fid = fopen(logPath, 'w');
            if fid < 0
                return;
            end

            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'Time: %s\n', char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS")));
            fprintf(fid, 'Server: %s:%d\n', char(string(opts.Server)), opts.Port);
            fprintf(fid, 'Logbook: %s\n', opts.Logbook);
            fprintf(fid, 'Author: %s\n', opts.Author);
            fprintf(fid, 'Sample: %s\n', opts.Sample);
            fprintf(fid, 'Measurement: %s\n', opts.Measurement);
            fprintf(fid, 'Type: %s\n', opts.Type);
            if isfield(opts, 'AdditionalAttributes') && isstruct(opts.AdditionalAttributes)
                if isfield(opts.AdditionalAttributes, 'XOI')
                    fprintf(fid, 'XOI: %s\n', opts.AdditionalAttributes.XOI);
                end
                if isfield(opts.AdditionalAttributes, 'Measuretype')
                    fprintf(fid, 'Measuretype: %s\n', opts.AdditionalAttributes.Measuretype);
                end
            end
            fprintf(fid, 'Result: %s\n', strtrim(char(string(response))));
        end

        function plotAcquisitionData(obj, key, data)
            if ~isfield(data, 'traces') || isempty(data.traces); return; end

            % 从 PlotAxesMap 获取或创建 tile
            if obj.PlotAxesMap.isKey(key)
                ax = obj.PlotAxesMap(key);
            else
                try
                    ax = nexttile(obj.PlotTileLayout);
                catch
                    obj.logMessage(sprintf( ...
                        "No free tile for: %s. Change layout or use Flow.", key), "warn");
                    return;
                end
                obj.PlotAxesMap(key) = ax;
                ax.XGrid = 'on'; ax.YGrid = 'on'; ax.Box = 'on';
                ax.FontSize = obj.FONT_SM;
            end

            cla(ax); hold(ax, 'on');

            firstLabel = 'y';
            for i = 1:numel(data.traces)
                trace = data.traces(i);
                [x, y, yLabel] = labdevices.core.DataExporter.pickPlotVectors(trace);
                if isempty(y); continue; end
                if i == 1; firstLabel = char(yLabel); end
                if isempty(x); x = (1:numel(y)).'; end

                traceName = '';
                if isfield(trace, 'name'); traceName = char(trace.name); end
                plot(ax, x, y, 'LineWidth', 1.0, 'DisplayName', traceName);
            end

            grid(ax, 'on');
            if numel(data.traces) > 1
                legend(ax, 'show', 'Location', 'best', 'FontSize', obj.FONT_XS);
            end

            xlabel(ax, labdevices.core.DataExporter.pickField(data, 'xunit', 'x'), 'FontSize', obj.FONT_SM);
            ylabel(ax, firstLabel, 'FontSize', obj.FONT_SM);

            titleStr = labdevices.core.DataExporter.pickField(data, 'device', key);
            if isfield(data, 'timestamp')
                titleStr = [titleStr, '  (', char(data.timestamp), ')'];
            end
            title(ax, titleStr, 'Interpreter', 'none', 'FontSize', obj.FONT_SM);

            hold(ax, 'off');
        end
    end
end
