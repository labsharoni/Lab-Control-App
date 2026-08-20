classdef TC335SweepApp < handle
    % TC335SweepApp - Lake Shore 335 Temperature Monitor & Control GUI
    
    properties
        % UI Components
        UIFigure
        GridLayout
        
        % Hardware Object
        TC
        
        % Monitoring & Logging State
        IsMonitoring = false
        IsLogging    = false
        PollTimer
        StartTime
        CurrentFile  = ''
        FileID       = -1
        
        % Plot Lines
        LineTempA
        LineTempB
        LineSetpoint
    end
    
    properties (Access = private)
        % UI Handles
        AddrTC, ConnectBtn
        
        % Temperature & Control Handles
        SetpointEdit, ApplySetpointBtn
        RampCheckbox, RampRateEdit
        HeaterRangeDrop
        LoopSelectDrop, SensorInputDrop
        PEdit, IEdit, DEdit, ApplyPIDBtn
        
        % Live Display Labels
        LabelTempA, LabelTempB, LabelHtrPower, LabelRampStatus
        
        % File & Logging Handles
        FilePathEdit, LogToggleBtn
        PlotAxes
        AutoscaleBtn
    end
    
    methods
        %% Constructor
        function app = TC335SweepApp()
            % Build Main Window
            app.UIFigure = uifigure('Name', 'Lake Shore 335 Temperature Controller', 'Position', [100, 100, 1150, 780]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {390, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Instrument & Control Setup');
            controlLayout = uigridlayout(controlPanel, [6, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', '1x'});
            
            app.createConnectionPanel(controlLayout);
            app.createSetpointPanel(controlLayout);
            app.createHeaterPIDPanel(controlLayout);
            app.createLoggingPanel(controlLayout);
            app.createStatusPanel(controlLayout);
            
            % Right Panel: Live Temperature & Output Plot
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live Temperature Monitor');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {35, '1x'});
            
            % Autoscale & Clear Buttons
            topBar = uigridlayout(plotLayout, [1, 3], 'ColumnWidth', {140, 100, '1x'});
            app.AutoscaleBtn = uibutton(topBar, 'state', 'Text', 'Autoscale ON', ...
                'Value', true, 'ValueChangedFcn', @(src,event) app.toggleAutoscale());
            uibutton(topBar, 'Text', 'Clear Plot', 'ButtonPushedFcn', @(src,event) app.clearPlot());
            
            % Axes Setup
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'Temperature vs. Time');
            xlabel(app.PlotAxes, 'Time (s)');
            ylabel(app.PlotAxes, 'Temperature (K)');
            grid(app.PlotAxes, 'on');
            enableDefaultInteractivity(app.PlotAxes);
            
            % Initialize Animated Lines
            app.LineTempA = animatedline(app.PlotAxes, 'Color', [0 0.447 0.741], 'LineWidth', 1.8, 'DisplayName', 'Sensor A');
            app.LineTempB = animatedline(app.PlotAxes, 'Color', [0.85 0.325 0.098], 'LineWidth', 1.5, 'LineStyle', '--', 'DisplayName', 'Sensor B');
            app.LineSetpoint = animatedline(app.PlotAxes, 'Color', [0.466 0.674 0.188], 'LineWidth', 1.2, 'LineStyle', ':', 'DisplayName', 'Setpoint');
            legend(app.PlotAxes, 'Location', 'best');
            
            % Initialize Polling Timer
            app.PollTimer = timer('ExecutionMode', 'fixedRate', 'Period', 1.0, ...
                                  'TimerFcn', @(~,~) app.pollHardware());
                              
            % Window Close Callback
            app.UIFigure.CloseRequestFcn = @(src,event) app.closeApp();
        end
        
        %% --- UI Component Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', '1. Hardware Connection');
            g = uigridlayout(p, [2, 2], 'ColumnWidth', {90, '1x'});
            
            uilabel(g, 'Text', 'VISA Address:');
            app.AddrTC = uieditfield(g, 'text', 'Value', 'GPIB0::5::INSTR');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect Controller', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src,event) app.connectHardware());
            app.ConnectBtn.Layout.Column = [1 2];
        end
        
        function createSetpointPanel(app, parent)
            p = uipanel(parent, 'Title', '2. Setpoint & Ramp Control');
            g = uigridlayout(p, [3, 4], 'RowHeight', {'fit', 'fit', 'fit'});
            
            uilabel(g, 'Text', 'Target (K):');
            app.SetpointEdit = uieditfield(g, 'numeric', 'Value', 295.0);
            
            uilabel(g, 'Text', 'Loop:');
            app.LoopSelectDrop = uidropdown(g, 'Items', {'1', '2'}, 'Value', '1');
            
            uilabel(g, 'Text', 'Ramp (K/min):');
            app.RampRateEdit = uieditfield(g, 'numeric', 'Value', 2.0);
            app.RampRateEdit.Tooltip = 'Ramp rate in Kelvin per minute';
            
            app.RampCheckbox = uicheckbox(g, 'Text', 'Enable Ramp', 'Value', false);
            app.RampCheckbox.Layout.Column = [3 4];
            
            app.ApplySetpointBtn = uibutton(g, 'Text', 'SET SETPOINT / RAMP', ...
                'BackgroundColor', [0.2 0.6 0.9], 'FontColor', 'w', 'FontWeight', 'bold', ...
                'Enable', 'off', 'ButtonPushedFcn', @(src,event) app.applySetpoint());
            app.ApplySetpointBtn.Layout.Column = [1 4];
        end
        
        function createHeaterPIDPanel(app, parent)
            p = uipanel(parent, 'Title', '3. Heater & Loop Parameters');
            g = uigridlayout(p, [3, 4]);
            
            uilabel(g, 'Text', 'Heater Range:');
            app.HeaterRangeDrop = uidropdown(g, 'Items', {'OFF', 'LOW', 'MED', 'HIGH'}, ...
                'Value', 'OFF', 'ValueChangedFcn', @(src,event) app.updateHeaterRange());
            app.HeaterRangeDrop.Layout.Column = [2 4];
            
            uilabel(g, 'Text', 'P (Gain):'); app.PEdit = uieditfield(g, 'numeric', 'Value', 20);
            uilabel(g, 'Text', 'I (Reset):'); app.IEdit = uieditfield(g, 'numeric', 'Value', 50);
            uilabel(g, 'Text', 'D (Rate):');  app.DEdit = uieditfield(g, 'numeric', 'Value', 0);
            
            app.ApplyPIDBtn = uibutton(g, 'Text', 'Apply PID', 'Enable', 'off', ...
                'ButtonPushedFcn', @(src,event) app.applyPID());
        end
        
        function createLoggingPanel(app, parent)
            p = uipanel(parent, 'Title', '4. CSV Data Logging');
            g = uigridlayout(p, [2, 2], 'ColumnWidth', {'1x', 80});
            
            app.FilePathEdit = uieditfield(g, 'text', 'Placeholder', 'Leave empty to auto-prompt...');
            uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(src,event) app.browseFile());
            
            app.LogToggleBtn = uibutton(g, 'state', 'Text', 'START LOGGING', ...
                'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', ...
                'ValueChangedFcn', @(src,event) app.toggleLogging());
            app.LogToggleBtn.Layout.Column = [1 2];
        end
        
        function createStatusPanel(app, parent)
            p = uipanel(parent, 'Title', 'Live Telemetry Readout');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {120, '1x'});
            
            uilabel(g, 'Text', 'Sensor A:', 'FontWeight', 'bold');
            app.LabelTempA = uilabel(g, 'Text', '--- K', 'FontSize', 14, 'FontColor', [0 0.45 0.74]);
            
            uilabel(g, 'Text', 'Sensor B:', 'FontWeight', 'bold');
            app.LabelTempB = uilabel(g, 'Text', '--- K', 'FontSize', 14, 'FontColor', [0.85 0.33 0.1]);
            
            uilabel(g, 'Text', 'Heater Output:', 'FontWeight', 'bold');
            app.LabelHtrPower = uilabel(g, 'Text', '0.0 %', 'FontSize', 13);
            
            uilabel(g, 'Text', 'Ramp Status:', 'FontWeight', 'bold');
            app.LabelRampStatus = uilabel(g, 'Text', 'Idle', 'FontSize', 13);
        end
        
        %% --- Hardware Callbacks & Polling ---
        function connectHardware(app)
            try
                app.ConnectBtn.Text = 'Connecting...'; drawnow;
                
                % Release any orphaned VISA handles
                existing = visadevfind("ResourceName", app.AddrTC.Value);
                if ~isempty(existing); delete(existing); end
                
                % Instantiate Lakeshore335 driver
                app.TC = Lakeshore.Lakeshore335(app.AddrTC.Value, 'A', 1);
                
                % Sync live controller parameters to GUI
                currLoop = str2double(app.LoopSelectDrop.Value);
                app.SetpointEdit.Value = app.TC.getSetpoint(currLoop);
                [p, i, d] = app.TC.getPID(currLoop);
                app.PEdit.Value = p; app.IEdit.Value = i; app.DEdit.Value = d;
                
                % Update UI State
                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.ApplySetpointBtn.Enable = 'on';
                app.ApplyPIDBtn.Enable = 'on';
                app.LogToggleBtn.Enable = 'on';
                
                % Start Live Polling
                app.StartTime = tic;
                if strcmp(app.PollTimer.Running, 'off')
                    start(app.PollTimer);
                end
            catch ME
                app.ConnectBtn.Text = 'Connection Failed';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                uialert(app.UIFigure, ME.message, 'Connection Error');
            end
        end
        
        function pollHardware(app)
            if isempty(app.TC); return; end
            
            try
                tElapsed = toc(app.StartTime);
                tA = app.TC.readTemp('A');
                tB = app.TC.readTemp('B');
                currLoop = str2double(app.LoopSelectDrop.Value);
                sp = app.TC.getSetpoint(currLoop);
                htr = app.TC.getHeaterOutput(1);
                isRamping = app.TC.isRamping(currLoop);
                
                % Update Numerical Labels
                app.LabelTempA.Text = sprintf('%.3f K', tA);
                app.LabelTempB.Text = sprintf('%.3f K', tB);
                app.LabelHtrPower.Text = sprintf('%.1f %%', htr);
                if isRamping
                    app.LabelRampStatus.Text = 'Ramping Active';
                    app.LabelRampStatus.FontColor = [0.8 0.4 0];
                else
                    app.LabelRampStatus.Text = 'Holding / Idle';
                    app.LabelRampStatus.FontColor = [0 0.5 0];
                end
                
                % Update Live Graph
                addpoints(app.LineTempA, tElapsed, tA);
                addpoints(app.LineTempB, tElapsed, tB);
                addpoints(app.LineSetpoint, tElapsed, sp);
                drawnow limitrate;
                
                % Log to CSV if enabled
                if app.IsLogging && app.FileID ~= -1
                    fprintf(app.FileID, '%.2f,%.4f,%.4f,%.4f,%.2f,%d\n', ...
                        tElapsed, tA, tB, sp, htr, double(isRamping));
                end
            catch
            end
        end
        
        function applySetpoint(app)
            if isempty(app.TC); return; end
            loopNum = str2double(app.LoopSelectDrop.Value);
            targetK = app.SetpointEdit.Value;
            rampActive = app.RampCheckbox.Value;
            rampRate = app.RampRateEdit.Value;
            
            app.TC.setRamp(rampActive, rampRate, loopNum);
            app.TC.setSetpoint(targetK, loopNum);
        end
        
        function updateHeaterRange(app)
            if isempty(app.TC); return; end
            loopNum = str2double(app.LoopSelectDrop.Value);
            app.TC.setHeaterRange(app.HeaterRangeDrop.Value, loopNum);
        end
        
        function applyPID(app)
            if isempty(app.TC); return; end
            loopNum = str2double(app.LoopSelectDrop.Value);
            app.TC.setPID(app.PEdit.Value, app.IEdit.Value, app.DEdit.Value, loopNum);
        end
        
        %% --- Logging & Utility Helpers ---
        function browseFile(app)
            [file, path] = uiputfile('*.csv', 'Select Log Destination');
            if file ~= 0
                app.FilePathEdit.Value = fullfile(path, file);
            end
        end
        
        function toggleLogging(app)
            if app.LogToggleBtn.Value
                target = app.FilePathEdit.Value;
                if isempty(target)
                    [file, path] = uiputfile('*.csv', 'Save Log As');
                    if file == 0
                        app.LogToggleBtn.Value = false;
                        return;
                    end
                    target = fullfile(path, file);
                    app.FilePathEdit.Value = target;
                end
                
                app.CurrentFile = target;
                app.FileID = fopen(app.CurrentFile, 'w');
                fprintf(app.FileID, '%% Lake Shore 335 Log Started: %s\n', datestr(now));
                fprintf(app.FileID, 'Time_s,TempA_K,TempB_K,Setpoint_K,Heater_pct,Ramping\n');
                
                app.IsLogging = true;
                app.LogToggleBtn.Text = 'STOP LOGGING';
                app.LogToggleBtn.BackgroundColor = [0.8 0.2 0.2];
            else
                app.IsLogging = false;
                if app.FileID ~= -1
                    fclose(app.FileID);
                    app.FileID = -1;
                end
                app.LogToggleBtn.Text = 'START LOGGING';
                app.LogToggleBtn.BackgroundColor = [0.2 0.8 0.2];
            end
        end
        
        function toggleAutoscale(app)
            if app.AutoscaleBtn.Value
                app.AutoscaleBtn.Text = 'Autoscale ON';
                app.PlotAxes.YLimMode = 'auto';
            else
                app.AutoscaleBtn.Text = 'Autoscale OFF';
                app.PlotAxes.YLimMode = 'manual';
            end
        end
        
        function clearPlot(app)
            clearpoints(app.LineTempA);
            clearpoints(app.LineTempB);
            clearpoints(app.LineSetpoint);
            app.StartTime = tic;
        end
        
        function closeApp(app)
            % 1. Stop and delete polling timer first so no new queries are sent
            if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                stop(app.PollTimer);
                delete(app.PollTimer);
            end
            
            % 2. Close logging file if open
            if app.FileID ~= -1
                fclose(app.FileID);
            end
            
            % 3. Safely shut down heaters and close VISA object
            if ~isempty(app.TC) && isvalid(app.TC)
                try
                    app.TC.unlockKeypad();
                catch
                end
                delete(app.TC);
            end
            
            % 4. Force release any remaining VISA handles to this address
            try
                existing = visadevfind("ResourceName", app.AddrTC.Value);
                if ~isempty(existing); delete(existing); end
            catch
            end
            
            % 5. Close UI
            delete(app.UIFigure);
        end
    end
end