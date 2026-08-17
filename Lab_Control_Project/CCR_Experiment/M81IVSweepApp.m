classdef M81IVSweepApp < handle
    % M81IVSweepApp - Multiplexed DC I-V Sweep using M81 and 3706
    % Sweeps DC Current, Measures DC Voltage. 
    % Iterates complete sweeps channel-by-channel to preserve relays.
    
    properties
        UIFigure
        GridLayout
        
        % Data & State
        ChannelSets = {}
        IsRunning = false
        DataLines = {}
        CurrentFile = ''
        
        % Hardware Objects
        M81
        Switcher
    end
    
    properties (Access = private)
        % UI Handles
        AddrM81, AddrSwitch
        ConnectBtn, DisconnectBtn
        
        StartCurEdit, EndCurEdit, StepsEdit, DelayEdit
        MeasureRangeDrop % Voltage Range Dropdown
        CustomVRangeEdit % Custom Voltage Edit Field
        
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox
        FilePathEdit
        
        PlotAxes
        AutoscaleBtn
        RunBtn, StopBtn
    end
    
    methods
        function app = M81IVSweepApp()
            % Construct the GUI
            app.UIFigure = uifigure('Name', 'M81 Multiplexed I-V Sweep', 'Position', [100, 100, 1100, 750]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            controlLayout = uigridlayout(controlPanel, [6, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', '1x'}, 'Scrollable', 'on');
            
            app.createConnectionPanel(controlLayout);
            app.createParameterPanel(controlLayout);
            app.createChannelPanel(controlLayout);
            app.createFilePanel(controlLayout);
            app.createConfigPanel(controlLayout);
            app.createControlButtons(controlLayout);
            
            % Right Panel: Live Plot
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live I-V Curve');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {30, '1x'});
            
            app.AutoscaleBtn = uibutton(plotLayout, 'state', 'Text', 'Autoscale Y-Axis ON', ...
                'Value', true, 'ValueChangedFcn', @(src,event) app.toggleAutoscale());
            
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'I-V Sweep');
            xlabel(app.PlotAxes, 'Source Current (A)');
            ylabel(app.PlotAxes, 'Measured Voltage (V)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        %% --- UI Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'M81 USB/GPIB:'); app.AddrM81 = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '3706 Switch:'); app.AddrSwitch = uieditfield(g, 'text', 'Value', 'SIM');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end
        
        function createParameterPanel(app, parent)
            p = uipanel(parent, 'Title', 'DC I-V Sweep Parameters');
            g = uigridlayout(p, [3, 4]); 
            
            uilabel(g, 'Text', 'Start (A):');    app.StartCurEdit = uieditfield(g, 'numeric', 'Value', -10e-6);
            uilabel(g, 'Text', 'End (A):');      app.EndCurEdit = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Steps:');        app.StepsEdit = uieditfield(g, 'numeric', 'Value', 51);
            uilabel(g, 'Text', 'Delay/Pt (s):'); app.DelayEdit = uieditfield(g, 'numeric', 'Value', 0.2);
            
            uilabel(g, 'Text', 'V. Range:');
            app.MeasureRangeDrop = uidropdown(g, ...
                'Items', {'AUTO', '10 mV', '30 mV', '100 mV', '300 mV', '1 V', '3 V', '10 V', 'CUSTOM...'}, ...
                'ItemsData', {'AUTO', 10e-3, 30e-3, 100e-3, 300e-3, 1.0, 3.0, 10.0, 'CUSTOM'}, ...
                'Value', 'AUTO', 'ValueChangedFcn', @(s,e) app.onRangeChange());
                
            uilabel(g, 'Text', 'Custom (V):');
            app.CustomVRangeEdit = uieditfield(g, 'numeric', 'Value', 0.05, 'Enable', 'off');
        end
        
        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', '3706 Switcher (Column Indices 1-16)');
            g = uigridlayout(p, [4, 4], 'RowHeight', {'fit', 'fit', 'fit', 80}); 
            
            uilabel(g, 'Text', '+I (Row 1):'); app.ChanPosI = uieditfield(g, 'numeric', 'Value', 1);
            uilabel(g, 'Text', '-I (Row 2):'); app.ChanNegI = uieditfield(g, 'numeric', 'Value', 2);
            uilabel(g, 'Text', '+V (Row 3):'); app.ChanPosV = uieditfield(g, 'numeric', 'Value', 1);
            uilabel(g, 'Text', '-V (Row 4):'); app.ChanNegV = uieditfield(g, 'numeric', 'Value', 2);
            
            addBtn = uibutton(g, 'Text', 'Add Set', 'ButtonPushedFcn', @(src,event) app.addChannelSet());
            addBtn.Layout.Column = [1 2];
            
            remBtn = uibutton(g, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(src,event) app.removeChannelSet());
            remBtn.Layout.Column = [3 4];
            
            app.ChannelListBox = uilistbox(g, 'Items', {}); 
            app.ChannelListBox.Layout.Column = [1 4];
        end
        
        function createFilePanel(app, parent)
            p = uipanel(parent, 'Title', 'Save Data File Location');
            g = uigridlayout(p, [1, 2], 'ColumnWidth', {'1x', 70});
            
            app.FilePathEdit = uieditfield(g, 'text', 'Placeholder', 'Leave empty to prompt on run...');
            uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(src,event) app.browseFile());
        end
        
        function createConfigPanel(app, parent)
            p = uipanel(parent, 'Title', 'Experiment Config');
            g = uigridlayout(p, [1, 2]);
            uibutton(g, 'Text', 'Load Setup', 'ButtonPushedFcn', @(src,event) app.loadConfig());
            uibutton(g, 'Text', 'Save Setup', 'ButtonPushedFcn', @(src,event) app.saveConfig());
        end
        
        function createControlButtons(app, parent)
            g = uigridlayout(parent, [1, 2]);
            app.RunBtn = uibutton(g, 'Text', 'START', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.runExperiment());
            app.StopBtn = uibutton(g, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.stopExperiment());
        end
        
        %% --- UI Callbacks ---
        function onRangeChange(app)
            if ischar(app.MeasureRangeDrop.Value) && strcmp(app.MeasureRangeDrop.Value, 'CUSTOM')
                app.CustomVRangeEdit.Enable = 'on';
            else
                app.CustomVRangeEdit.Enable = 'off';
            end
        end
        
        %% --- Hardware Connections ---
        function disconnectHardware(app)
            try delete(app.M81); app.M81 = []; catch; end
            try delete(app.Switcher); app.Switcher = []; catch; end
            app.ConnectBtn.Text = 'Connect';
            app.ConnectBtn.BackgroundColor = [0.96 0.96 0.96];
            app.ConnectBtn.Enable = 'on';
            app.DisconnectBtn.Enable = 'off';
            app.RunBtn.Enable = 'off';
        end
        
        function connectHardware(app)
            app.disconnectHardware();
            try
                app.ConnectBtn.Text = 'Connecting...'; app.ConnectBtn.Enable = 'off'; drawnow;
                app.M81 = Lakeshore.LakeshoreM81(app.AddrM81.Value);
                app.Switcher = Keithley.Keithley3706(app.AddrSwitch.Value);
                
                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.DisconnectBtn.Enable = 'on';
                app.RunBtn.Enable = 'on';
            catch ME
                app.disconnectHardware();
                app.ConnectBtn.Text = 'Connection Failed';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                uialert(app.UIFigure, ME.message, 'Hardware Connection Error');
            end
        end

        %% --- Configuration File & List Logic ---
        function saveConfig(app)
            [file, path] = uiputfile('*.mat', 'Save Configuration');
            if file ~= 0
                config = struct('AddrM81', app.AddrM81.Value, 'AddrSwitch', app.AddrSwitch.Value, ...
                    'StartCur', app.StartCurEdit.Value, 'EndCur', app.EndCurEdit.Value, ...
                    'Steps', app.StepsEdit.Value, 'Delay', app.DelayEdit.Value, ...
                    'VRange', app.MeasureRangeDrop.Value, 'CustomVRange', app.CustomVRangeEdit.Value, ... 
                    'ChannelSets', {app.ChannelSets}, 'ChannelItems', {app.ChannelListBox.Items});
                save(fullfile(path, file), 'config');
            end
        end
        
        function loadConfig(app)
            [file, path] = uigetfile('*.mat', 'Load Configuration');
            if file ~= 0
                data = load(fullfile(path, file), 'config'); c = data.config;
                app.AddrM81.Value = c.AddrM81; app.AddrSwitch.Value = c.AddrSwitch;
                app.StartCurEdit.Value = c.StartCur; app.EndCurEdit.Value = c.EndCur;
                app.StepsEdit.Value = c.Steps; app.DelayEdit.Value = c.Delay;
                try app.MeasureRangeDrop.Value = c.VRange; catch; end 
                try app.CustomVRangeEdit.Value = c.CustomVRange; catch; end 
                app.ChannelSets = c.ChannelSets; app.ChannelListBox.Items = c.ChannelItems;
                app.onRangeChange(); 
            end
        end
        
        function addChannelSet(app)
            vec = [app.ChanPosI.Value, app.ChanNegI.Value, app.ChanPosV.Value, app.ChanNegV.Value, 0, 0];
            chanStr = sprintf('Set %d: +I(c%d), -I(c%d), +V(c%d), -V(c%d)', length(app.ChannelSets)+1, vec(1), vec(2), vec(3), vec(4));
            app.ChannelSets{end+1} = vec;
            app.ChannelListBox.Items{end+1} = chanStr;
            app.ChannelListBox.Value = chanStr;
        end
        
        function removeChannelSet(app)
            if ~isempty(app.ChannelListBox.Items)
                idx = find(strcmp(app.ChannelListBox.Items, app.ChannelListBox.Value));
                if ~isempty(idx)
                    app.ChannelListBox.Items(idx) = []; app.ChannelSets(idx) = [];
                    if ~isempty(app.ChannelListBox.Items); app.ChannelListBox.Value = app.ChannelListBox.Items{end}; end
                end
            end
        end
        
        function browseFile(app)
            [file, path] = uiputfile('*.csv', 'Select Save Location');
            if file ~= 0; app.FilePathEdit.Value = fullfile(path, file); end
        end
        
        function safeFile = resolveFilename(~, baseFile)
            [filepath, name, ext] = fileparts(baseFile); safeFile = baseFile; counter = 1;
            while isfile(safeFile)
                safeFile = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
                counter = counter + 1;
            end
        end
        
        %% --- Plot & Execution Logic ---
        function toggleAutoscale(app)
            if app.AutoscaleBtn.Value
                app.AutoscaleBtn.Text = 'Autoscale Y-Axis ON';
                app.PlotAxes.YLimMode = 'auto';
            else
                app.AutoscaleBtn.Text = 'Autoscale OFF (Manual)';
                app.PlotAxes.YLimMode = 'manual';
            end
        end
        
        function stopExperiment(app)
            app.IsRunning = false;
        end
        
        function runExperiment(app)
            numChannels = length(app.ChannelSets);
            if numChannels == 0
                uialert(app.UIFigure, 'Please add at least one channel set.', 'Configuration Error');
                return;
            end
            
            % Resolve Output File
            targetFile = app.FilePathEdit.Value;
            if isempty(targetFile)
                [file, path] = uiputfile('*.csv', 'Select File to Save Data');
                if file == 0; return; end 
                targetFile = fullfile(path, file);
            end
            
            app.CurrentFile = app.resolveFilename(targetFile);
            fileID = fopen(app.CurrentFile, 'w');
            if fileID == -1
                uialert(app.UIFigure, 'Could not open file for writing.', 'File Error');
                return;
            end
            
            % Generate the Current Sweep Array
            numSteps = max(app.StepsEdit.Value, 2);
            sweepCurrents = linspace(app.StartCurEdit.Value, app.EndCurEdit.Value, numSteps);
            
            % Write CSV Headers (Tall format for I-V multiplexing)
            fprintf(fileID, '%% Experiment Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Sweep: %e A to %e A (%d points)\n', app.StartCurEdit.Value, app.EndCurEdit.Value, numSteps);
            fprintf(fileID, 'Channel_Set,Current_A,Measured_Voltage_V\n');
            
            app.IsRunning = true;
            app.RunBtn.Enable = 'off'; app.StopBtn.Enable = 'on';
            
            cla(app.PlotAxes);
            app.DataLines = {}; colors = lines(numChannels);
            for c = 1:numChannels
                app.DataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, app.ChannelListBox.Items, 'Location', 'best');
            
            % Lock X-Axis to the sweep boundaries automatically
            xPad = abs(app.EndCurEdit.Value - app.StartCurEdit.Value) * 0.05;
            if xPad == 0; xPad = 1e-6; end
            app.PlotAxes.XLim = [min(sweepCurrents)-xPad, max(sweepCurrents)+xPad];
            
            try
                app.M81.setOutputState(false); 
                
                % Resolve User Selected Voltage Range
                if ischar(app.MeasureRangeDrop.Value) && strcmp(app.MeasureRangeDrop.Value, 'CUSTOM')
                    vRange = app.CustomVRangeEdit.Value;
                else
                    vRange = app.MeasureRangeDrop.Value;
                end
                
                % ==========================================
                % MAIN I-V MEASUREMENT LOOP
                % ==========================================
                % Outer Loop: Channels (To prevent destroying relays)
                for c = 1:numChannels
                    if ~app.IsRunning; break; end
                    
                    app.PlotAxes.Title.String = sprintf('Sweeping Channel %d of %d...', c, numChannels);
                    
                    % Format the string for the CSV file explicitly to prevent corruption
                    vec = app.ChannelSets{c};
                    chanLabel = sprintf('%d_%d_%d_%d', vec(1), vec(2), vec(3), vec(4));
                    
                    % 1. Switch matrix to current channel
                    app.Switcher.closeChannels(app.ChannelSets{c}); 
                    pause(0.5); 
                    
                    % 2. Configure M81 for DC Measurement
                    app.M81.setSourceMode('DC', sweepCurrents(1)); 
                    app.M81.setMeasureMode('DC');
                    app.M81.setMeasureRange(vRange); 
                    
                    % Smart 2-Wire vs 4-Wire
                    if (vec(1) == vec(3)) && (vec(2) == vec(4))
                        app.M81.configureResistanceMode('TWOWire', 'DC');
                    else
                        app.M81.configureResistanceMode('4WIRE', 'DC');
                    end
                    
                    % Turn source ON and let it settle initially
                    app.M81.setOutputState(true);    
                    if isnumeric(vRange)
                        pause(1.0); 
                    else
                        pause(3.0); % Wait longer for Auto-Range on first point
                    end
                    
                    % Inner Loop: Current Sweep
                    for i = 1:numSteps
                        if ~app.IsRunning; break; end
                        
                        targetI = sweepCurrents(i);
                        app.M81.setSourceMode('DC', targetI);
                        
                        % Pause for requested delay
                        pause(app.DelayEdit.Value);
                        
                        % Read DC Voltage
                        vVal = NaN;
                        for attempt = 1:3
                            try
                                vVal = app.M81.readDC();
                                if ~isnan(vVal) && abs(vVal) < 1e6; break; end
                            catch
                                pause(0.2); 
                            end
                        end
                        
                        % Plot Data
                        if abs(vVal) < 1e6 
                            addpoints(app.DataLines{c}, targetI, vVal);
                        end
                        
                        % --- CSV WRITE FIX ---
                        % Uses the properly formatted chanLabel string instead of the raw numeric array
                        fprintf(fileID, '%s,%e,%e\n', chanLabel, targetI, vVal);
                        
                        % --- DYNAMIC AUTOSCALING (Y-Axis Only) ---
                        if app.AutoscaleBtn.Value
                            globalYMin = inf; globalYMax = -inf; validDataFound = false;
                            for idx = 1:numChannels
                                [~, yData] = getpoints(app.DataLines{idx});
                                if length(yData) > 2
                                    globalYMin = min(globalYMin, min(yData));
                                    globalYMax = max(globalYMax, max(yData));
                                    validDataFound = true;
                                end
                            end
                            if validDataFound
                                if globalYMax > globalYMin
                                    yPad = (globalYMax - globalYMin) * 0.1;
                                    app.PlotAxes.YLim = [globalYMin - yPad, globalYMax + yPad];
                                else
                                    app.PlotAxes.YLim = [globalYMin - 1, globalYMax + 1];
                                end
                            end
                        end
                        drawnow limitrate;
                    end
                    
                    % Turn source OFF before switching to the next channel
                    app.M81.setOutputState(false);
                    pause(0.2);
                end
                
                % Clean Shutdown
                app.PlotAxes.Title.String = 'I-V Sweep Complete';
                app.Switcher.openAllChannels();
                fclose(fileID);
                app.RunBtn.Enable = 'on'; app.StopBtn.Enable = 'off';
                
            catch ME
                if ~isempty(app.M81); try app.M81.setOutputState(false); catch; end; end
                if ~isempty(app.Switcher); try app.Switcher.openAllChannels(); catch; end; end
                if exist('fileID', 'var'); fclose(fileID); end
                
                app.IsRunning = false;
                app.RunBtn.Enable = 'on'; app.StopBtn.Enable = 'off';
                uialert(app.UIFigure, sprintf('Error during measurement: %s', ME.message), 'Experiment Aborted');
            end
        end
    end
end