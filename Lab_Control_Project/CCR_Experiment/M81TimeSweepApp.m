classdef M81TimeSweepApp < handle
    % M81TimeSweepApp - Multiplexed Resistance vs. Time tracking
    % Includes Hot Swapping for high-speed multiplexing and Direct Lock-In X-math.
    
    properties
        UIFigure
        GridLayout
        
        ChannelSets = {}
        IsRunning = false
        DataLines = {}
        CurrentFile = ''
        StartTime
        
        M81
        Switcher
    end
    
    properties (Access = private)
        AddrM81, AddrSwitch
        ConnectBtn, DisconnectBtn
        
        CurrentEdit, FreqEdit, TCEdit, IntervalEdit
        MeasureRangeDrop 
        CustomVRangeEdit 
        HotSwapCheckBox 
        
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox
        FilePathEdit
        
        PlotAxes
        AutoscaleBtn
        RunBtn, StopBtn
    end
    
    methods
        function app = M81TimeSweepApp()
            app.UIFigure = uifigure('Name', 'M81 Multiplexed Lock-In Time Sweep', 'Position', [100, 100, 1100, 750]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});
            
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            controlLayout = uigridlayout(controlPanel, [6, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', '1x'});
            
            app.createConnectionPanel(controlLayout);
            app.createParameterPanel(controlLayout);
            app.createChannelPanel(controlLayout);
            app.createFilePanel(controlLayout);
            app.createConfigPanel(controlLayout);
            app.createControlButtons(controlLayout);
            
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live Time Series');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {30, '1x'});
            
            app.AutoscaleBtn = uibutton(plotLayout, 'state', 'Text', 'Autoscale ON', ...
                'Value', true, 'ValueChangedFcn', @(src,event) app.toggleAutoscale());
            
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'Lock-In Resistance vs. Time');
            xlabel(app.PlotAxes, 'Time (Seconds)');
            ylabel(app.PlotAxes, 'Resistance (\Omega)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'M81 USB/GPIB:'); app.AddrM81 = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '3706 Switch:'); app.AddrSwitch = uieditfield(g, 'text', 'Value', 'SIM');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end
        
        function createParameterPanel(app, parent)
            p = uipanel(parent, 'Title', 'Lock-In Parameters');
            g = uigridlayout(p, [4, 4]); 
            
            uilabel(g, 'Text', 'Current (A):');  app.CurrentEdit = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Freq (Hz):');    app.FreqEdit = uieditfield(g, 'numeric', 'Value', 13.0);
            uilabel(g, 'Text', 'TC (s):');       app.TCEdit = uieditfield(g, 'numeric', 'Value', 0.6);
            uilabel(g, 'Text', 'Interval (s):'); app.IntervalEdit = uieditfield(g, 'numeric', 'Value', 2.0);
            
            uilabel(g, 'Text', 'V. Range:');
            app.MeasureRangeDrop = uidropdown(g, ...
                'Items', {'AUTO', '10 mV', '30 mV', '100 mV', '300 mV', '1 V', '3 V', '10 V', 'CUSTOM...'}, ...
                'ItemsData', {'AUTO', 10e-3, 30e-3, 100e-3, 300e-3, 1.0, 3.0, 10.0, 'CUSTOM'}, ...
                'Value', 'AUTO', 'ValueChangedFcn', @(s,e) app.onRangeChange());
                
            uilabel(g, 'Text', 'Custom (V):');
            app.CustomVRangeEdit = uieditfield(g, 'numeric', 'Value', 0.05, 'Enable', 'off');
            
            app.HotSwapCheckBox = uicheckbox(g, 'Text', 'Enable Hot Swap (Faster, Low Current Only)', 'Value', true);
            app.HotSwapCheckBox.Layout.Row = 4; app.HotSwapCheckBox.Layout.Column = [1 4];
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
        
        function onRangeChange(app)
            if ischar(app.MeasureRangeDrop.Value) && strcmp(app.MeasureRangeDrop.Value, 'CUSTOM')
                app.CustomVRangeEdit.Enable = 'on';
            else
                app.CustomVRangeEdit.Enable = 'off';
            end
        end
        
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

        function saveConfig(app)
            [file, path] = uiputfile('*.mat', 'Save Configuration');
            if file ~= 0
                config = struct('AddrM81', app.AddrM81.Value, 'AddrSwitch', app.AddrSwitch.Value, ...
                    'Current', app.CurrentEdit.Value, 'Freq', app.FreqEdit.Value, ...
                    'TC', app.TCEdit.Value, 'Interval', app.IntervalEdit.Value, ...
                    'VRange', app.MeasureRangeDrop.Value, 'CustomVRange', app.CustomVRangeEdit.Value, ...
                    'HotSwap', app.HotSwapCheckBox.Value, ...
                    'ChannelSets', {app.ChannelSets}, 'ChannelItems', {app.ChannelListBox.Items});
                save(fullfile(path, file), 'config');
            end
        end
        
        function loadConfig(app)
            [file, path] = uigetfile('*.mat', 'Load Configuration');
            if file ~= 0
                data = load(fullfile(path, file), 'config'); c = data.config;
                app.AddrM81.Value = c.AddrM81; app.AddrSwitch.Value = c.AddrSwitch;
                app.CurrentEdit.Value = c.Current; app.FreqEdit.Value = c.Freq;
                app.TCEdit.Value = c.TC; app.IntervalEdit.Value = c.Interval;
                try app.MeasureRangeDrop.Value = c.VRange; catch; end 
                try app.CustomVRangeEdit.Value = c.CustomVRange; catch; end 
                try app.HotSwapCheckBox.Value = c.HotSwap; catch; end
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
        
        function toggleAutoscale(app)
            if app.AutoscaleBtn.Value
                app.AutoscaleBtn.Text = 'Autoscale ON';
                app.PlotAxes.XLimMode = 'auto'; app.PlotAxes.YLimMode = 'auto';
            else
                app.AutoscaleBtn.Text = 'Autoscale OFF (Manual)';
                app.PlotAxes.XLimMode = 'manual'; app.PlotAxes.YLimMode = 'manual';
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
            
            targetFile = app.FilePathEdit.Value;
            if isempty(targetFile)
                [file, path] = uiputfile('*.csv', 'Select File to Save Data');
                if file == 0; return; end 
                targetFile = fullfile(path, file);
            end
            
            app.CurrentFile = app.resolveFilename(targetFile);
            fileID = fopen(app.CurrentFile, 'w');
            
            fprintf(fileID, '%% Experiment Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Lock-In Current: %e A | Freq: %f Hz | TC: %f s\n', app.CurrentEdit.Value, app.FreqEdit.Value, app.TCEdit.Value);
            
            headerStr = 'Time_s';
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                headerStr = sprintf('%s,%d_%d_%d_%d', headerStr, vec(1), vec(2), vec(3), vec(4));
            end
            fprintf(fileID, '%s\n', headerStr);
            
            app.IsRunning = true;
            app.RunBtn.Enable = 'off'; app.StopBtn.Enable = 'on';
            
            cla(app.PlotAxes);
            app.DataLines = {}; colors = lines(numChannels);
            for c = 1:numChannels
                app.DataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, app.ChannelListBox.Items, 'Location', 'best');
            
            try
                app.M81.setOutputState(false); 
                
                if ischar(app.MeasureRangeDrop.Value) && strcmp(app.MeasureRangeDrop.Value, 'CUSTOM')
                    vRange = app.CustomVRangeEdit.Value;
                else
                    vRange = app.MeasureRangeDrop.Value;
                end
                
                % INITIAL INSTRUMENT SETUP
                app.M81.setSourceMode('AC', app.CurrentEdit.Value, 0.0, app.FreqEdit.Value);
                app.M81.setSourceRange(app.CurrentEdit.Value); 
                app.M81.setMeasureMode('LIA');
                app.M81.setMeasureRange(vRange); 
                app.M81.setTimeConstant(app.TCEdit.Value); 
                
                % If single channel or Hot Swap is ON, turn source ON now and leave it ON
                if numChannels == 1 || app.HotSwapCheckBox.Value == true
                    app.Switcher.closeChannels(app.ChannelSets{1});
                    pause(0.2);
                    
                    vec = app.ChannelSets{1};
                    if (vec(1) == vec(3)) && (vec(2) == vec(4))
                        app.M81.configureResistanceMode('TWOWire', 'AC'); 
                    else
                        app.M81.configureResistanceMode('4WIRE', 'AC');
                    end
                    
                    app.M81.setOutputState(true);
                    pause(max(app.TCEdit.Value * 10, 4.0)); % One-time startup wait
                end
                
                title(app.PlotAxes, 'Lock-In Resistance vs. Time');
                app.StartTime = tic;
                activeChannel = 1;
                
                % ==========================================
                % MAIN MEASUREMENT LOOP
                % ==========================================
                while app.IsRunning
                    loopTimer = tic;
                    elapsedTime = toc(app.StartTime);
                    stepVoltages = zeros(1, numChannels);
                    
                    for c = 1:numChannels
                        if ~app.IsRunning; break; end
                        
                        % MULTIPLEXING LOGIC
                        if activeChannel ~= c || (numChannels > 1 && c == 1)
                            vec = app.ChannelSets{c};
                            if (vec(1) == vec(3)) && (vec(2) == vec(4))
                                targetMode = 'TWOWire';
                            else
                                targetMode = '4WIRE';
                            end
                            
                            if app.HotSwapCheckBox.Value == true
                                % --- HOT SWAP (Much Faster) ---
                                app.Switcher.closeChannels(app.ChannelSets{c}); 
                                app.M81.configureResistanceMode(targetMode, 'AC');
                                % Wait a fraction of the time since source never turned off
                                pause(max(app.TCEdit.Value * 4, 0.5)); 
                            else
                                % --- COLD SWAP (Slower, Safer) ---
                                app.M81.setOutputState(false);                  
                                pause(0.5); 
                                app.Switcher.closeChannels(app.ChannelSets{c}); 
                                pause(0.2); 
                                
                                app.M81.configureResistanceMode(targetMode, 'AC');
                                app.M81.setOutputState(true);    
                                pause(max(app.TCEdit.Value * 10, 4.0));
                            end
                            activeChannel = c;
                        end
                        
                        % ========================================================
                        % BLAZING FAST READ: Bypass M81 CALC module timeouts!
                        % Directly fetch Lock-In X-Voltage and do the R = V / I math
                        % ========================================================
                        rVal = NaN;
                        for attempt = 1:4
                            try
                                [X_real, ~, ~, ~] = app.M81.readLockIn();
                                rVal = X_real ./ app.CurrentEdit.Value;
                                rTamar = app.M81.readResistance()
                                
                                if ~isnan(rVal) && abs(rVal) < 1e6; break; end
                            catch
                                pause(0.1); 
                            end
                        end
                        
                        % Record valid data
                        stepVoltages(c) = rVal;
                        if abs(rVal) < 1e6 
                            addpoints(app.DataLines{c}, elapsedTime, rVal);
                        end
                        
                    end % End of Multiplexing Loop
                    
                    % --- GLOBAL DYNAMIC AUTOSCALING ---
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
                    
                    if app.IsRunning
                        fprintf(fileID, '%f', elapsedTime);
                        for c = 1:numChannels
                            fprintf(fileID, ',%e', stepVoltages(c));
                        end
                        fprintf(fileID, '\n');
                    end
                    
                    timeTaken = toc(loopTimer);
                    remainingWait = app.IntervalEdit.Value - timeTaken;
                    if remainingWait > 0; pause(remainingWait); else; drawnow; end
                end
                
                app.M81.setOutputState(false);
                pause(0.5); 
                app.Switcher.openAllChannels();
                fclose(fileID);
                app.RunBtn.Enable = 'on'; app.StopBtn.Enable = 'off';
                
            catch ME
                if ~isempty(app.M81); try app.M81.setOutputState(false); pause(0.5); catch; end; end
                if ~isempty(app.Switcher); try app.Switcher.openAllChannels(); catch; end; end
                if exist('fileID', 'var'); fclose(fileID); end
                
                app.IsRunning = false;
                app.RunBtn.Enable = 'on'; app.StopBtn.Enable = 'off';
                uialert(app.UIFigure, sprintf('Error during measurement: %s', ME.message), 'Experiment Aborted');
            end
        end
    end
end