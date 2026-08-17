function KeithleySweepApp()
    % Create the main UI Figure
    fig = uifigure('Name', 'Keithley 2400 Sweep Controller', 'Position', [100, 100, 800, 500]);
    
    % Create a Grid Layout (1 row, 2 columns: Left for controls, Right for plot)
    gl = uigridlayout(fig, [1, 2]);
    gl.ColumnWidth = {250, '1x'};
    
    % --- Left Panel: Controls ---
    controlPanel = uipanel(gl, 'Title', 'Measurement Settings');
    cgl = uigridlayout(controlPanel, [10, 2]);
    cgl.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','1x'};
    
    % Source Dropdown
    uilabel(cgl, 'Text', 'Source:');
    ddSource = uidropdown(cgl, 'Items', {'Voltage (V)', 'Current (A)'});
    
    % Measure Dropdown
    uilabel(cgl, 'Text', 'Measure:');
    ddMeasure = uidropdown(cgl, 'Items', {'Current (A)', 'Voltage (V)'});
    
    % Sweep Parameters (Start, End, Step)
    uilabel(cgl, 'Text', 'Start:');
    editStart = uieditfield(cgl, 'numeric', 'Value', -1);
    
    uilabel(cgl, 'Text', 'End:');
    editEnd = uieditfield(cgl, 'numeric', 'Value', 1);
    
    uilabel(cgl, 'Text', 'Step:');
    editStep = uieditfield(cgl, 'numeric', 'Value', 0.1);
    
    % Timing and Settings
    uilabel(cgl, 'Text', 'Dwell Time (s):');
    editDwell = uieditfield(cgl, 'numeric', 'Value', 0.1);
    
    uilabel(cgl, 'Text', 'Compliance:');
    editComp = uieditfield(cgl, 'numeric', 'Value', 0.01);
    
    uilabel(cgl, 'Text', 'NPLC:');
    editNPLC = uieditfield(cgl, 'numeric', 'Value', 1.0);
    
    % Start/Stop Buttons
    btnStart = uibutton(cgl, 'Text', 'Start Sweep', 'ButtonPushedFcn', @runSweep);
    btnStart.BackgroundColor = [0.47, 0.67, 0.19]; % Green
    btnStart.FontColor = 'white';
    
    btnStop = uibutton(cgl, 'Text', 'Stop / Abort', 'Enable', 'off');
    btnStop.BackgroundColor = [0.85, 0.33, 0.10]; % Red
    btnStop.FontColor = 'white';
    
    % --- Right Panel: Plot ---
    ax = uiaxes(gl);
    title(ax, 'Live Measurement Data');
    grid(ax, 'on');
    
    % State variable to handle stopping
    stopRequested = false;
    
    % --- Callback: Run Sweep ---
    function runSweep(~, ~)
        % Lock UI
        btnStart.Enable = 'off';
        btnStop.Enable = 'on';
        stopRequested = false;
        btnStop.ButtonPushedFcn = @(~,~) assignin('caller', 'stopRequested', true);
        
        % Read UI Values
        isSourceV = strcmp(ddSource.Value, 'Voltage (V)');
        isMeasureV = strcmp(ddMeasure.Value, 'Voltage (V)');
        
        startVal = editStart.Value;
        endVal = editEnd.Value;
        stepVal = editStep.Value;
        dwell = editDwell.Value;
        comp = editComp.Value;
        nplc = editNPLC.Value;
        
        % Create sweep array (handles both positive and negative steps safely)
        if startVal <= endVal
            sweepVals = startVal:abs(stepVal):endVal;
        else
            sweepVals = startVal:-abs(stepVal):endVal;
        end
        
        % Set up the live plot
        cla(ax);
        if isSourceV
            xlabel(ax, 'Source Voltage (V)');
        else
            xlabel(ax, 'Source Current (A)');
        end
        
        if isMeasureV
            ylabel(ax, 'Measured Voltage (V)');
        else
            ylabel(ax, 'Measured Current (A)');
        end
        
        lineObj = animatedline(ax, 'Marker', 'o', 'Color', 'b', 'LineWidth', 1.5);
        
        % --- Instrument Setup ---
        try
            % USING 'SIM' FOR TESTING. CHANGE TO REAL ADDRESS FOR LAB USE.
            smu = Keithley.Keithley2400('SIM'); 
            
            smu.setNPLC(nplc);
            
            if isSourceV
                smu.setVoltageSource(comp);
            else
                smu.setCurrentSource(comp);
            end
            
            smu.setOutput('ON');
            
            % --- Measurement Loop ---
            for i = 1:length(sweepVals)
                if stopRequested
                    disp('Sweep aborted by user.');
                    break;
                end
                
                % Set Source
                currentSetPoint = sweepVals(i);
                if isSourceV
                    smu.setVoltage(currentSetPoint);
                else
                    smu.setCurrent(currentSetPoint);
                end
                
                % Dwell
                pause(dwell);
                
                % Read
                [measV, measI, ~] = smu.readData();
                
                % Update Plot
                if isSourceV && isMeasureV
                    addpoints(lineObj, currentSetPoint, measV);
                elseif isSourceV && ~isMeasureV
                    addpoints(lineObj, currentSetPoint, measI);
                elseif ~isSourceV && isMeasureV
                    addpoints(lineObj, currentSetPoint, measV);
                else
                    addpoints(lineObj, currentSetPoint, measI);
                end
                
                drawnow; % Force UI to update immediately
            end
            
            % Cleanup
            smu.setOutput('OFF');
            delete(smu); % Close connection
            
        catch ME
            uialert(fig, ME.message, 'Instrument Error');
        end
        
        % Unlock UI
        btnStart.Enable = 'on';
        btnStop.Enable = 'off';
    end
end