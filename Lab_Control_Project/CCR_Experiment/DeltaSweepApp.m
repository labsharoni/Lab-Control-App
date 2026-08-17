classdef DeltaSweepApp < handle
    % DeltaSweepApp - Multi-Instrument Field Sweep & Delta Mode Controller
    
    properties
        % UI Components
        UIFigure
        GridLayout
        
        % Data & State
        ChannelSets = {}
        IsRunning = false
        DataLines = {}
        CurrentFile = ''
        
        % Hardware Objects
        Magnet
        Switcher
        DeltaMode
    end
    
    properties (Access = private)
        % UI Handles
        AddrDelta, AddrSwitch, AddrDaq
        ConnectBtn
        
        FieldStart, FieldEnd, FieldSteps, FieldDelay, FieldRepeats
        DeltaPosI, DeltaNegI, DeltaRepeats, DeltaDelay
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox
        FilePathEdit
        PlotAxes
        AutoscaleBtn
        RunBtn, StopBtn
    end
    
    methods
        function app = DeltaSweepApp()
            % Construct the GUI
            app.UIFigure = uifigure('Name', 'Delta Mode & Field Sweep Controller', 'Position', [100, 100, 1100, 800]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            controlLayout = uigridlayout(controlPanel, [8, 1], 'RowHeight', {'fit','fit','fit','fit','fit','fit','fit','1x'});
            
            app.createConnectionPanel(controlLayout);
            app.createFieldPanel(controlLayout);
            app.createDeltaPanel(controlLayout);
            app.createChannelPanel(controlLayout);
            app.createFilePanel(controlLayout);
            app.createConfigPanel(controlLayout); % NEW: Save/Load Setup Panel
            app.createControlButtons(controlLayout);
            
            % Right Panel: Live Plot
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live Data');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {30, '1x'});
            
            % Autoscale Toggle
            app.AutoscaleBtn = uibutton(plotLayout, 'state', 'Text', 'Autoscale ON', ...
                'Value', true, 'ValueChangedFcn', @(src,event) app.toggleAutoscale());
            
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'Delta Voltage vs. Magnetic Field');
            xlabel(app.PlotAxes, 'Magnetic Field (Oe)');
            ylabel(app.PlotAxes, 'Delta Voltage (V)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        %% --- UI Component Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {100, '1x'});
            
            uilabel(g, 'Text', '6221/2182A:'); app.AddrDelta = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '3706 Switch:'); app.AddrSwitch = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '6002 DAQ Dev:'); app.AddrDaq = uieditfield(g, 'text', 'Value', 'SIM');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect Instruments', 'ButtonPushedFcn', @(src,event) app.connectHardware());
            app.ConnectBtn.Layout.Column = [1 2];
        end

        function createFieldPanel(app, parent)
            p = uipanel(parent, 'Title', 'Magnetic Field Sweep (6002)');
            g = uigridlayout(p, [3, 4]);
            
            uilabel(g, 'Text', 'Start (Oe):'); app.FieldStart = uieditfield(g, 'numeric', 'Value', -1000);
            uilabel(g, 'Text', 'End (Oe):');   app.FieldEnd = uieditfield(g, 'numeric', 'Value', 1000);
            uilabel(g, 'Text', 'Steps:');      app.FieldSteps = uieditfield(g, 'numeric', 'Value', 50);
            uilabel(g, 'Text', 'Delay (s):');  app.FieldDelay = uieditfield(g, 'numeric', 'Value', 1.0);
            uilabel(g, 'Text', 'Repeats:');    app.FieldRepeats = uieditfield(g, 'numeric', 'Value', 1);
        end
        
        function createDeltaPanel(app, parent)
            p = uipanel(parent, 'Title', 'Delta Mode Settings');
            g = uigridlayout(p, [2, 4]);
            
            uilabel(g, 'Text', '+ I (A):');    app.DeltaPosI = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', '- I (A):');    app.DeltaNegI = uieditfield(g, 'numeric', 'Value', -10e-6);
            uilabel(g, 'Text', 'Repeats:');    app.DeltaRepeats = uieditfield(g, 'numeric', 'Value', 3);
            uilabel(g, 'Text', 'Delay (s):');  app.DeltaDelay = uieditfield(g, 'numeric', 'Value', 0.1);
        end
        
        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', '3706 Switcher (Column Indices 1-16)');
            g = uigridlayout(p, [4, 4], 'RowHeight', {'fit', 'fit', 'fit', 80}); 
            
            uilabel(g, 'Text', '+I (Row 1):'); app.ChanPosI = uieditfield(g, 'numeric', 'Value', 11);
            uilabel(g, 'Text', '-I (Row 2):'); app.ChanNegI = uieditfield(g, 'numeric', 'Value', 12);
            uilabel(g, 'Text', '+V (Row 3):'); app.ChanPosV = uieditfield(g, 'numeric', 'Value', 13);
            uilabel(g, 'Text', '-V (Row 4):'); app.ChanNegV = uieditfield(g, 'numeric', 'Value', 14);
            
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
        
        % NEW: Save and Load Configuration Panel
        function createConfigPanel(app, parent)
            p = uipanel(parent, 'Title', 'Experiment Setup Configurations');
            g = uigridlayout(p, [1, 2]);
            
            uibutton(g, 'Text', 'Load Setup', 'ButtonPushedFcn', @(src,event) app.loadConfig());
            uibutton(g, 'Text', 'Save Setup', 'ButtonPushedFcn', @(src,event) app.saveConfig());
        end
        
        function createControlButtons(app, parent)
            g = uigridlayout(parent, [1, 2]);
            app.RunBtn = uibutton(g, 'Text', 'RUN EXPERIMENT', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(src,event) app.runExperiment());
            app.StopBtn = uibutton(g, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(src,event) app.stopExperiment());
        end
        
        %% --- Configuration Save/Load Logic ---
        function saveConfig(app)
            [file, path] = uiputfile('*.mat', 'Save Configuration File As');
            if file == 0; return; end
            
            % Gather all current UI values
            config = struct();
            config.AddrDelta    = app.AddrDelta.Value;
            config.AddrSwitch   = app.AddrSwitch.Value;
            config.AddrDaq      = app.AddrDaq.Value;
            config.FieldStart   = app.FieldStart.Value;
            config.FieldEnd     = app.FieldEnd.Value;
            config.FieldSteps   = app.FieldSteps.Value;
            config.FieldDelay   = app.FieldDelay.Value;
            config.FieldRepeats = app.FieldRepeats.Value;
            config.DeltaPosI    = app.DeltaPosI.Value;
            config.DeltaNegI    = app.DeltaNegI.Value;
            config.DeltaRepeats = app.DeltaRepeats.Value;
            config.DeltaDelay   = app.DeltaDelay.Value;
            config.ChannelSets  = app.ChannelSets;
            config.ChannelItems = app.ChannelListBox.Items;
            
            save(fullfile(path, file), 'config');
            uialert(app.UIFigure, 'Configuration successfully saved.', 'Success');
        end
        
        function loadConfig(app)
            [file, path] = uigetfile('*.mat', 'Select Configuration File');
            if file == 0; return; end
            
            try
                data = load(fullfile(path, file), 'config');
                c = data.config;
                
                % Apply saved values back to the UI
                app.AddrDelta.Value    = c.AddrDelta;
                app.AddrSwitch.Value   = c.AddrSwitch;
                app.AddrDaq.Value      = c.AddrDaq;
                app.FieldStart.Value   = c.FieldStart;
                app.FieldEnd.Value     = c.FieldEnd;
                app.FieldSteps.Value   = c.FieldSteps;
                app.FieldDelay.Value   = c.FieldDelay;
                app.FieldRepeats.Value = c.FieldRepeats;
                app.DeltaPosI.Value    = c.DeltaPosI;
                app.DeltaNegI.Value    = c.DeltaNegI;
                app.DeltaRepeats.Value = c.DeltaRepeats;
                app.DeltaDelay.Value   = c.DeltaDelay;
                
                % Restore channel list array
                app.ChannelSets = c.ChannelSets;
                app.ChannelListBox.Items = c.ChannelItems;
                if ~isempty(app.ChannelListBox.Items)
                    app.ChannelListBox.Value = app.ChannelListBox.Items{1};
                end
                
            catch ME
                uialert(app.UIFigure, 'Failed to load configuration. File may be corrupted or invalid.', 'Load Error');
            end
        end

        %% --- Logic & Execution ---
        
        function connectHardware(app)
            try
                app.ConnectBtn.Text = 'Connecting...'; drawnow;
                
                app.DeltaMode = Keithley.Keithley6221_2182A(app.AddrDelta.Value);
                app.Switcher  = Keithley.Keithley3706(app.AddrSwitch.Value);
                app.Magnet    = NI.USB6002(app.AddrDaq.Value, 'ao0'); 
                
                app.ConnectBtn.Text = 'Instruments Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.RunBtn.Enable = 'on';
            catch ME
                app.ConnectBtn.Text = 'Connection Failed';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                uialert(app.UIFigure, ME.message, 'Hardware Connection Error');
            end
        end

        function addChannelSet(app)
            vector = [app.ChanPosI.Value, app.ChanNegI.Value, app.ChanPosV.Value, app.ChanNegV.Value, 0, 0];
            chanStr = sprintf('Set %d: +I(c%d), -I(c%d), +V(c%d), -V(c%d)', ...
                length(app.ChannelSets)+1, vector(1), vector(2), vector(3), vector(4));
            
            app.ChannelSets{end+1} = vector;
            app.ChannelListBox.Items{end+1} = chanStr;
            app.ChannelListBox.Value = chanStr;
        end
        
        function removeChannelSet(app)
            if isempty(app.ChannelListBox.Items); return; end
            
            selectedValue = app.ChannelListBox.Value;
            idx = find(strcmp(app.ChannelListBox.Items, selectedValue));
            
            if ~isempty(idx)
                app.ChannelListBox.Items(idx) = [];
                app.ChannelSets(idx) = [];
                if ~isempty(app.ChannelListBox.Items)
                    app.ChannelListBox.Value = app.ChannelListBox.Items{end};
                end
            end
        end
        
        function browseFile(app)
            [file, path] = uiputfile('*.csv', 'Select Save Location');
            if file ~= 0
                app.FilePathEdit.Value = fullfile(path, file);
            end
        end
        
        function toggleAutoscale(app)
            if app.AutoscaleBtn.Value
                app.AutoscaleBtn.Text = 'Autoscale ON';
                app.PlotAxes.XLimMode = 'auto';
                app.PlotAxes.YLimMode = 'auto';
            else
                app.AutoscaleBtn.Text = 'Autoscale OFF (Manual)';
                app.PlotAxes.XLimMode = 'manual';
                app.PlotAxes.YLimMode = 'manual';
            end
        end
        
        function safeFile = resolveFilename(app, baseFile)
            [filepath, name, ext] = fileparts(baseFile);
            safeFile = baseFile;
            counter = 1;
            while isfile(safeFile)
                safeFile = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
                counter = counter + 1;
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
                app.FilePathEdit.Value = targetFile;
            end
            
            app.CurrentFile = app.resolveFilename(targetFile);
            
            % 1. Open File and Write Metadata Header
            fileID = fopen(app.CurrentFile, 'w');
            
            fprintf(fileID, '%% Experiment Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Delta Current (+I): %e A\n', app.DeltaPosI.Value);
            fprintf(fileID, '%% Delta Current (-I): %e A\n', app.DeltaNegI.Value);
            fprintf(fileID, '%% Delta Averages (Repeats): %d\n', app.DeltaRepeats.Value);
            fprintf(fileID, '%% Delta Delay: %f s\n', app.DeltaDelay.Value);
            fprintf(fileID, '%% Field Start: %f Oe | End: %f Oe | Steps: %d\n', app.FieldStart.Value, app.FieldEnd.Value, app.FieldSteps.Value);
            
            fprintf(fileID, '%% Channels Configured: ');
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                fprintf(fileID, '[+I:%d, -I:%d, +V:%d, -V:%d] ', vec(1), vec(2), vec(3), vec(4));
            end
            fprintf(fileID, '\n%%\n'); % Blank comment line separator
            
            % 2. Build and Write Column Headers
            headerStr = 'SweepRepeat,Field_Oe';
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                headerStr = sprintf('%s,%d_%d_%d_%d', headerStr, vec(1), vec(2), vec(3), vec(4));
            end
            fprintf(fileID, '%s\n', headerStr);
            
            % Setup UI State
            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            
            % Prepare Plot Lines
            cla(app.PlotAxes);
            app.DataLines = {};
            colors = lines(numChannels);
            for c = 1:numChannels
                app.DataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, app.ChannelListBox.Items, 'Location', 'best');
            
            % Generate Sweep Vector
            fields = linspace(app.FieldStart.Value, app.FieldEnd.Value, app.FieldSteps.Value);
            
            try
                % Main Experiment Loop
                for rep = 1:app.FieldRepeats.Value
                    for i = 1:length(fields)
                        if ~app.IsRunning; break; end 
                        
                        currentField = fields(i);
                        app.Magnet.setField(currentField);
                        pause(app.FieldDelay.Value); 
                        
                        % Array to hold the voltages for the current field step
                        stepVoltages = zeros(1, numChannels);
                        
                        for c = 1:numChannels
                            if ~app.IsRunning; break; end
                            
                            app.Switcher.closeChannels(app.ChannelSets{c});
                            pause(0.2); 
                            
                            app.DeltaMode.setupDeltaMode(app.DeltaPosI.Value, app.DeltaNegI.Value, ...
                                                         app.DeltaRepeats.Value, 'oneshot', app.DeltaDelay.Value);
                            
                            measV = app.DeltaMode.runDeltaMeasurement();
                            stepVoltages(c) = measV;
                            
                            addpoints(app.DataLines{c}, currentField, measV);
                        end
                        
                        % Write the completed row to the CSV file safely
                        if app.IsRunning
                            fprintf(fileID, '%d,%f', rep, currentField);
                            for c = 1:numChannels
                                fprintf(fileID, ',%e', stepVoltages(c));
                            end
                            fprintf(fileID, '\n');
                        end
                        
                        drawnow limitrate; 
                    end
                end
                
                app.Magnet.setField(0);
                app.Switcher.openAllChannels();
                
            catch ME
                app.Magnet.setField(0);
                app.Switcher.openAllChannels();
                fclose(fileID);
                app.IsRunning = false;
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                uialert(app.UIFigure, sprintf('Error during sweep: %s', ME.message), 'Experiment Aborted');
                return;
            end
            
            % Clean Stop
            fclose(fileID);
            app.IsRunning = false;
            app.RunBtn.Enable = 'on';
            app.StopBtn.Enable = 'off';
            uialert(app.UIFigure, sprintf('Data saved to:\n%s', app.CurrentFile), 'Experiment Complete');
        end
    end
end