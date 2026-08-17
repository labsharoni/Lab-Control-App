function KeithleyMatrixApp()
    % Initialize the instrument in Simulation Mode
    % Change 'SIM' to your VISA address (e.g., 'USB0::...::INSTR') in the lab
    try
        matrixObj = Keithley.Keithley3706('GPIB0::16::INSTR');
    catch ME
        errordlg(['Failed to connect to matrix: ', ME.message]);
        return;
    end

    % --- Main Figure Setup ---
    fig = uifigure('Name', 'Keithley 3706 Matrix Controller', 'Position', [150, 150, 650, 400]);
    
    % Main Layout: 1 Row, 2 Columns (Left for Inputs, Right for Buttons/Output)
    gl = uigridlayout(fig, [1, 2]);
    gl.ColumnWidth = {200, '1x'};
    
    % --- Left Panel: Matrix Inputs (Rows 1-6) ---
    inputPanel = uipanel(gl, 'Title', 'Row Configurations');
    
    % Increased grid rows to 8 to accommodate the new text label
    inputGrid = uigridlayout(inputPanel, [8, 2]);
    inputGrid.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
    inputGrid.ColumnWidth = {'fit', '1x'};
    
    % Create Arrays to hold UI components
    rowLabels = gobjects(6,1);
    colInputs = gobjects(6,1);
    
    for i = 1:6
        rowLabels(i) = uilabel(inputGrid, 'Text', sprintf('Row %d Connects to:', i));
        
        % Numeric input fields restricted to integers between 0 and 16
        colInputs(i) = uieditfield(inputGrid, 'numeric', ...
            'Value', 0, ...
            'Limits', [0, 16], ...
            'RoundFractionalValues', 'on');
    end
    
    % --- NEW: Explicit label explaining the '0' behavior ---
    infoLabel = uilabel(inputGrid, 'Text', '* Note: 0 means no connection');
    infoLabel.FontColor = [0.4, 0.4, 0.4]; % Dark gray
    infoLabel.FontAngle = 'italic';
    infoLabel.Layout.Row = 7;
    infoLabel.Layout.Column = [1, 2]; % Make it span across both columns
    
    % --- Right Panel: Controls and Output ---
    controlGrid = uigridlayout(gl, [5, 1]);
    controlGrid.RowHeight = {'fit', 'fit', 'fit', 'fit', '1x'};
    
    % Buttons
    btnOpenAll = uibutton(controlGrid, 'Text', 'Open All Channels', ...
        'ButtonPushedFcn', @(~,~) cbOpenAll());
    btnOpenAll.BackgroundColor = [0.85, 0.33, 0.10]; % Red-ish for open/disconnect
    btnOpenAll.FontColor = 'white';
    
    btnClose = uibutton(controlGrid, 'Text', 'Close Channels', ...
        'ButtonPushedFcn', @(~,~) cbCloseChannels());
        
    btnOpenThenClose = uibutton(controlGrid, 'Text', 'Open Then Close', ...
        'ButtonPushedFcn', @(~,~) cbOpenThenClose());
        
    btnQuery = uibutton(controlGrid, 'Text', 'Query Closed Channels', ...
        'ButtonPushedFcn', @(~,~) cbQueryChannels());
    btnQuery.BackgroundColor = [0, 0.45, 0.74]; % Blue for query
    btnQuery.FontColor = 'white';
    
    % Output Text Area
    txtOutput = uitextarea(controlGrid, 'Editable', 'off');
    txtOutput.Value = {'Matrix Initialized. Ready for commands.'};
    
    % --- Helper Function: Log Output ---
    function logMsg(msg)
        % Appends a new message to the top of the text area
        currentText = txtOutput.Value;
        timeStr = datestr(now, 'HH:MM:SS');
        newEntry = sprintf('[%s] %s', timeStr, msg);
        txtOutput.Value = [{newEntry}; currentText];
    end

    % --- Helper Function: Get Vector ---
    function vec = getRoutingVector()
        % Extracts values from the 6 edit fields into a 1x6 vector
        vec = zeros(1,6);
        for idx = 1:6
            vec(idx) = colInputs(idx).Value;
        end
    end

    % --- Callbacks ---
    
    function cbOpenAll()
        matrixObj.openAllChannels();
        logMsg('Executed: OPEN ALL CHANNELS');
    end

    function cbCloseChannels()
        vec = getRoutingVector();
        matrixObj.closeChannels(vec);
        logMsg(sprintf('Executed: CLOSE Vector [%d %d %d %d %d %d]', vec));
    end

    function cbOpenThenClose()
        logMsg('Executing: Open Then Close sequence...');
        matrixObj.openAllChannels();
        pause(0.2); % Brief pause to ensure mechanical relays settle
        vec = getRoutingVector();
        matrixObj.closeChannels(vec);
        logMsg(sprintf('Executed: CLOSE Vector [%d %d %d %d %d %d]', vec));
    end

    function cbQueryChannels()
        queryStr = matrixObj.queryClosedChannels();
        logMsg(sprintf('Raw Query Returned: %s', queryStr));
        
        % Parse the string to make it readable
        if strcmp(queryStr, 'NONE')
            logMsg('Result: All rows are currently OPEN.');
        else
            % Remove '(@' and ')'
            cleanStr = strrep(queryStr, '(@', '');
            cleanStr = strrep(cleanStr, ')', '');
            
            % Split by commas
            chList = split(cleanStr, ',');
            
            logMsg('--- ACTIVE CONNECTIONS ---');
            for idx = 1:length(chList)
                ch = strtrim(chList{idx});
                if length(ch) == 4 % Expecting format 1RCC (Slot, Row, Col, Col)
                    rowNum = str2double(ch(2));
                    colNum = str2double(ch(3:4));
                    logMsg(sprintf('  Row %d is connected to Input %d', rowNum, colNum));
                end
            end
            logMsg('--------------------------');
        end
    end

    % --- Cleanup on Close ---
    % Automatically delete the instrument object when the figure is closed
    fig.CloseRequestFcn = @(~,~) closeApp();
    function closeApp()
        delete(matrixObj);
        delete(fig);
    end
end