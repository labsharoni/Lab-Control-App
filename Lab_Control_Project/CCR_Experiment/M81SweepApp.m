classdef M81SweepApp < handle
    % M81SweepApp - Multi-Instrument Field Sweep & M81 Controller
    
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
        M81
    end
    
    properties (Access = private)
        % UI Handles
        AddrM81, AddrSwitch, AddrDaq
        ConnectBtn
        
        FieldStart, FieldEnd, FieldSteps, FieldDelay, FieldRepeats
        M81Current, M81Freq, M81Mode, M81Delay
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox
        FilePathEdit
        PlotAxes
        AutoscaleBtn
        RunBtn, StopBtn
    end
    
    methods
        function app = M81SweepApp()
            % Construct the GUI[cite: 5]
            app.UIFigure = uifigure('Name', 'M81 & Field Sweep Controller', 'Position', [100, 100, 1100, 800]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});
            
            % Left Panel: Controls[cite: 5]
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            controlLayout = uigridlayout(controlPanel, [7, 1], 'RowHeight', {'fit','fit','fit','fit','fit','fit','1x'});
            
            app.createConnectionPanel(controlLayout);
            app.createFieldPanel(controlLayout);
            app.createM81Panel(controlLayout);
            app.createChannelPanel(controlLayout);
            app.createFilePanel(controlLayout);
            app.createControlButtons(controlLayout);
            
            % Right Panel: Live Plot[cite: 5]
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live Data');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {30, '1x'});
            
            % Autoscale Toggle[cite: 5]
            app.AutoscaleBtn = uibutton(plotLayout, 'state', 'Text', 'Autoscale ON', ...
                'Value', true, 'ValueChangedFcn', @(src,event) app.toggleAutoscale());
            
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'M81 Resistance vs. Magnetic Field');
            xlabel(app.PlotAxes, 'Magnetic Field (Oe)');
            ylabel(app.PlotAxes, 'Resistance (Ohms)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        %% --- UI Component Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {100, '1x'});
            
            uilabel(g, 'Text', 'M81 SSM:'); app.AddrM81 = uieditfield(g, 'text', 'Value', 'ASRL3::INSTR');
            uilabel(g, 'Text', '3706 Switch:'); app.AddrSwitch = uieditfield(g, 'text', 'Value', 'GPIB0::16::INSTR');
            uilabel(g, 'Text', '6002 DAQ Dev:'); app.AddrDaq = uieditfield(g, 'text', 'Value', 'Dev1');
            
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
        
        function createM81Panel(app, parent)
            p = uipanel(parent, 'Title', 'M81 Measurement Settings');
            g = uigridlayout(p, [2, 4]);
            
            uilabel(g, 'Text', 'Excitation (A):'); app.M81Current = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Freq (Hz):');      app.M81Freq = uieditfield(g, 'numeric', 'Value', 17.0);
            uilabel(g, 'Text', 'Mode:');           app.M81Mode = uidropdown(g, 'Items', {'AC Lock-In', 'DC Resistance'});
            uilabel(g, 'Text', 'Delay (s):');      app.M81Delay = uieditfield(g, 'numeric', 'Value', 2.0);
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
        
        function createControlButtons(app, parent)
            g = uigridlayout(parent, [1, 2]);
            app.RunBtn = uibutton(g, 'Text', 'RUN EXPERIMENT', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(src,event) app.runExperiment());
            app.StopBtn = uibutton(g, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(src,event) app.stopExperiment());
        end

        %% --- Logic & Execution ---
        function connectHardware(app)
            try
                app.ConnectBtn.Text = 'Connecting...'; drawnow;
                
                % Connect hardware[cite: 1, 2, 4]
                app.M81       = Lakeshore.LakeshoreM81(app.AddrM81.Value, 1, 1);
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
            
            % 1. Open File and Write Metadata Header[cite: 5]
            fileID = fopen(app.CurrentFile, 'w');
            
            fprintf(fileID, '%% Experiment Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% M81 Excitation Current: %e A\n', app.M81Current.Value);
            fprintf(fileID, '%% M81 Frequency: %f Hz\n', app.M81Freq.Value);
            fprintf(fileID, '%% M81 Mode: %s\n', app.M81Mode.Value);
            fprintf(fileID, '%% Measurement Delay: %f s\n', app.M81Delay.Value);
            fprintf(fileID, '%% Field Start: %f Oe | End: %f Oe | Steps: %d\n', app.FieldStart.Value, app.FieldEnd.Value, app.FieldSteps.Value);
            
            fprintf(fileID, '%% Channels Configured: ');
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                fprintf(fileID, '[+I:%d, -I:%d, +V:%d, -V:%d] ', vec(1), vec(2), vec(3), vec(4));
            end
            fprintf(fileID, '\n%%\n'); 
            
            % 2. Build and Write Column Headers[cite: 5]
            headerStr = 'SweepRepeat,Field_Oe';
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                headerStr = sprintf('%s,%d_%d_%d_%d_Ohms', headerStr, vec(1), vec(2), vec(3), vec(4));
            end
            fprintf(fileID, '%s\n', headerStr);
            
            % Setup UI State
            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            
            % Prepare Plot Lines[cite: 5]
            cla(app.PlotAxes);
            app.DataLines = {};
            colors = lines(numChannels);
            for c = 1:numChannels
                app.DataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, app.ChannelListBox.Items, 'Location', 'best');
            
            % Setup M81 Hardware Parameters
            if strcmp(app.M81Mode.Value, 'AC Lock-In')
                app.M81.setSourceMode('AC', app.M81Current.Value, 0, app.M81Freq.Value);
                app.M81.setMeasureMode('LIA');
                app.M81.configureResistanceMode('4WIRE', 'AC');
            else
                app.M81.setSourceMode('DC', app.M81Current.Value);
                app.M81.setMeasureMode('DC');
                app.M81.configureResistanceMode('4WIRE', 'DC');
            end
            
            app.M81.setSourceRange('AUTO');
            app.M81.setMeasureRange('AUTO');
            app.M81.setOutputState(true);
            
            % Generate Sweep Vector
            fields = linspace(app.FieldStart.Value, app.FieldEnd.Value, app.FieldSteps.Value);
            
            try
                % Main Experiment Loop[cite: 5]
                for rep = 1:app.FieldRepeats.Value
                    for i = 1:length(fields)
                        if ~app.IsRunning; break; end 
                        
                        currentField = fields(i);
                        app.Magnet.setField(currentField);
                        pause(app.FieldDelay.Value); 
                        
                        stepResistances = zeros(1, numChannels);
                        
                        for c = 1:numChannels
                            if ~app.IsRunning; break; end
                            
                            app.Switcher.closeChannels(app.ChannelSets{c});
                            pause(app.M81Delay.Value); % Settle time for locks/filters
                            
                            measR = app.M81.readResistance();[cite: 1]
                            stepResistances(c) = measR;
                            
                            addpoints(app.DataLines{c}, currentField, measR);
                        end
                        
                        if app.IsRunning
                            fprintf(fileID, '%d,%f', rep, currentField);
                            for c = 1:numChannels
                                fprintf(fileID, ',%e', stepResistances(c));
                            end
                            fprintf(fileID, '\n');
                        end
                        
                        drawnow limitrate; 
                    end
                end
                
                % Safe shutdown
                app.Magnet.setField(0);
                app.Switcher.openAllChannels();
                app.M81.setOutputState(false);
                
            catch ME
                app.Magnet.setField(0);
                app.Switcher.openAllChannels();
                app.M81.setOutputState(false);
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