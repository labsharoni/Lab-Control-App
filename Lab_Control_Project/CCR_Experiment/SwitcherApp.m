classdef SwitcherApp < handle
    % SwitcherApp - A standalone manual controller for the Keithley 3706
    
    properties
        UIFigure
        Switcher
        
        AddrEdit
        ConnectBtn
        DisconnectBtn
        
        RowInputs % Array storing the 6 numeric input handles
        StatusLabel
    end
    
    methods
        function app = SwitcherApp()
            % Setup the main window
            app.UIFigure = uifigure('Name', 'Keithley 3706 Manual Override', 'Position', [300, 200, 450, 550]);
            mainLayout = uigridlayout(app.UIFigure, [4, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x'});
            
            % 1. Connection Panel
            pConn = uipanel(mainLayout, 'Title', 'Hardware Connection');
            gConn = uigridlayout(pConn, [1, 3], 'ColumnWidth', {'1x', 100, 100});
            app.AddrEdit = uieditfield(gConn, 'text', 'Value', 'GPIB0::16::INSTR'); % change to SIM if need simulation
            
            app.ConnectBtn = uibutton(gConn, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(gConn, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
            
            % 2. Matrix Row Inputs Panel
            pMat = uipanel(mainLayout, 'Title', 'Row Configurations (0 = Skip, 1-16 = Close Column)');
            gMat = uigridlayout(pMat, [6, 2], 'ColumnWidth', {'1x', 150});
            app.RowInputs = gobjects(1, 6);
            for i = 1:6
                uilabel(gMat, 'Text', sprintf('Row %d:', i), 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
                % Restrict inputs strictly to integers between 0 and 16
                app.RowInputs(i) = uieditfield(gMat, 'numeric', 'Value', 0, 'Limits', [0, 16], 'RoundFractionalValues', 'on');
            end
            
            % 3. Action Buttons Panel
            pAct = uipanel(mainLayout, 'Title', 'Relay Actions');
            gAct = uigridlayout(pAct, [3, 1]);
            
            uibutton(gAct, 'Text', 'Open All + Close Selected', 'BackgroundColor', [0.8 0.9 1], ...
                'Tooltip', 'Safely clears the board first, then closes only the numbers above.', ...
                'ButtonPushedFcn', @(s,e) app.exclusiveClose());
                
            uibutton(gAct, 'Text', 'Only Close Selected (Append)', 'BackgroundColor', [1 0.9 0.8], ...
                'Tooltip', 'Leaves currently closed relays alone, and adds the numbers above.', ...
                'ButtonPushedFcn', @(s,e) app.appendClose());
                
            uibutton(gAct, 'Text', 'Open All Channels', 'BackgroundColor', [1 0.8 0.8], ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(s,e) app.openAll());
            
            % 4. Status Panel
            pStat = uipanel(mainLayout, 'Title', 'Hardware Status Tracker');
            gStat = uigridlayout(pStat, [2, 1], 'RowHeight', {'fit', '1x'});
            uibutton(gStat, 'Text', 'Refresh Readout', 'ButtonPushedFcn', @(s,e) app.refreshStatus());
            app.StatusLabel = uitextarea(gStat, 'Value', 'Not Connected', 'Editable', 'off');
        end
        
        %% --- Hardware Connection & Disconnection Logic ---
        
        function disconnectHardware(app)
            % Safely clear any existing object to close ports properly
            try
                delete(app.Switcher); 
                app.Switcher = [];
            catch
                % Fail silently if nothing was connected
            end
            
            % Reset UI Elements
            app.ConnectBtn.Text = 'Connect';
            app.ConnectBtn.BackgroundColor = [0.96 0.96 0.96]; % Default gray
            app.ConnectBtn.Enable = 'on';
            app.DisconnectBtn.Enable = 'off';
            app.StatusLabel.Value = 'Disconnected.';
        end
        
        function connectHardware(app)
            % 1. Clean up any broken/partial connections first
            app.disconnectHardware();
            
            try
                app.ConnectBtn.Text = 'Connecting...'; 
                app.ConnectBtn.Enable = 'off'; drawnow;
                
                % 2. Instantiate the wrapper
                app.Switcher = Keithley.Keithley3706(app.AddrEdit.Value);
                
                % 3. Update UI on success
                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.ConnectBtn.Enable = 'on';
                app.DisconnectBtn.Enable = 'on';
                app.refreshStatus();
            catch ME
                % 4. If it fails, release the locked port and allow retry
                app.disconnectHardware();
                app.ConnectBtn.Text = 'Retry Connection';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                uialert(app.UIFigure, ME.message, 'Connection Error');
            end
        end
        
        %% --- Hardware Relay Logic ---
        
        function vec = getInputVector(app)
            % Pulls the current 0-16 values from the 6 UI boxes into an array
            vec = zeros(1, 6);
            for i = 1:6
                vec(i) = app.RowInputs(i).Value;
            end
        end
        
        function exclusiveClose(app)
            if isempty(app.Switcher); uialert(app.UIFigure, 'Connect to hardware first!', 'Error'); return; end
            app.Switcher.closeChannels(app.getInputVector());
            app.refreshStatus();
        end
        
        function appendClose(app)
            if isempty(app.Switcher); uialert(app.UIFigure, 'Connect to hardware first!', 'Error'); return; end
            app.Switcher.appendChannels(app.getInputVector());
            app.refreshStatus();
        end
        
        function openAll(app)
            if isempty(app.Switcher); uialert(app.UIFigure, 'Connect to hardware first!', 'Error'); return; end
            app.Switcher.openAllChannels();
            app.refreshStatus();
        end
        
        function refreshStatus(app)
            if isempty(app.Switcher); return; end
            try
                % Query the actual hardware for what is physically closed
                closed = app.Switcher.queryClosedChannels();
                app.StatusLabel.Value = sprintf('Currently Closed Relays:\n%s', closed);
            catch
                app.StatusLabel.Value = 'Error querying instrument status.';
            end
        end
    end
end