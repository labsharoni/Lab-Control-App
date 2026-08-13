classdef PPMSTamarController < handle
    % PPMSTamarController - Queue-based runner for PPMS experiments.
    % Left panel: hardware connection, experiment queue, run/stop.
    % Right panel: live plot (top) and run log (bottom).
    %
    % NOTE: The "New Experiment" editor GUI (for defining what an
    % experiment file actually does) and the real per-experiment
    % execution logic are not implemented yet - only the outer
    % shell (queue management, connection, shutdown) is built here.

    properties
        UIFigure
        GridLayout

        % Hardware Objects
        PPMS
        M81
        Switcher

        % Queue State
        ExperimentQueue = {}   % cell array of experiment file paths / definitions
        IsRunning = false
    end

    properties (Access = private)
        % Connection UI
        AddrPPMS, AddrM81, AddrSwitch
        ConnectBtn, DisconnectBtn

        % Notification UI
        EmailEdit
        GmailLogin = ''      % session-only, not persisted to disk
        GmailPassword = ''   % session-only, not persisted to disk

        % Output UI
        OutputFolderEdit

        % Queue UI
        ExperimentListBox
        AddExperimentBtn, LoadExperimentBtn, RemoveExperimentBtn, MoveUpBtn, MoveDownBtn
        RenameExperimentBtn, DuplicateExperimentBtn
        ShutdownCheckbox

        % Run UI
        HeliumThresholdEdit
        RunBtn, StopBtn

        % Helium watchdog (runs while hardware is connected)
        HeliumTimer

        % Right panel
        PlotAxes
        LogTextArea
    end

    methods
        function app = PPMSTamarController()
            % Construct the GUI
            app.UIFigure = uifigure('Name', 'PPMS Tamar Controller', 'Position', [100, 100, 1150, 650], ...
                'CloseRequestFcn', @(s,e) app.onAppClose());
            movegui(app.UIFigure, 'center');
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});

            % Left Panel: Connection / Queue / Run
            leftPanel = uipanel(app.GridLayout, 'Title', 'Controller');
            leftLayout = uigridlayout(leftPanel, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', 280, 'fit'}, 'Scrollable', 'on');

            app.createConnectionPanel(leftLayout);
            app.createNotificationPanel(leftLayout);
            app.createOutputFolderPanel(leftLayout);
            app.createQueuePanel(leftLayout);
            app.createRunPanel(leftLayout);

            % Right Panel: Live Plot + Log
            rightPanel = uipanel(app.GridLayout, 'Title', 'Live Data & Log');
            rightLayout = uigridlayout(rightPanel, [2, 1], 'RowHeight', {'1x', '1x'});

            plotContainer = uipanel(rightLayout, 'Title', 'Live Data');
            plotLayout = uigridlayout(plotContainer, [1, 1]);
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'Live Data');
            grid(app.PlotAxes, 'on');
            enableDefaultInteractivity(app.PlotAxes);

            logContainer = uipanel(rightLayout, 'Title', 'Log');
            logLayout = uigridlayout(logContainer, [1, 1]);
            app.LogTextArea = uitextarea(logLayout, 'Editable', 'off');

            app.loadGmailCredentials();
        end

        %% --- UI Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', '1x'});

            uilabel(g, 'Text', 'PPMS DLL Path:'); app.AddrPPMS = uieditfield(g, 'text', 'Value', 'C:\MATLAB\Lab_Control_Project\Drivers\QDInstrument.dll');
            uilabel(g, 'Text', 'M81 Address:');  app.AddrM81 = uieditfield(g, 'text', 'Value', 'GPIB1::12::INSTR');
            uilabel(g, 'Text', '3706 Switch:');   app.AddrSwitch = uieditfield(g, 'text', 'Value', 'GPIB1::16::INSTR');

            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end

        function createNotificationPanel(app, parent)
            p = uipanel(parent, 'Title', 'Email Notifications');
            g = uigridlayout(p, [2, 1], 'RowHeight', {'fit', 'fit'});

            addrRow = uigridlayout(g, [1, 2], 'ColumnWidth', {'fit', '1x'});
            uilabel(addrRow, 'Text', 'Send updates to:');
            app.EmailEdit = uieditfield(addrRow, 'text', 'Placeholder', 'name@example.com');

            btnRow = uigridlayout(g, [1, 2]);
            uibutton(btnRow, 'Text', 'Send Test Email', 'ButtonPushedFcn', @(s,e) app.sendTestEmail());
            uibutton(btnRow, 'Text', 'Forget Saved Login', 'ButtonPushedFcn', @(s,e) app.forgetGmailCredentials());
        end

        function sendTestEmail(app)
            recipient = strtrim(app.EmailEdit.Value);
            if isempty(recipient)
                uialert(app.UIFigure, 'Enter a recipient email address first.', 'Missing Address');
                return;
            end

            if ~app.ensureGmailCredentials()
                app.logMessage('Test email skipped (no credentials provided).');
                return;
            end

            app.sendNotification('PPMS: Test Email', 'This is a test email from PPMS Tamar Controller.');
        end

        function createOutputFolderPanel(app, parent)
            p = uipanel(parent, 'Title', 'Output Folder');
            g = uigridlayout(p, [1, 2], 'ColumnWidth', {'1x', 70});
            app.OutputFolderEdit = uieditfield(g, 'text', 'Placeholder', 'Base folder for all experiment data...');
            uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(s,e) app.browseOutputFolder());
        end

        function browseOutputFolder(app)
            folder = uigetdir(app.OutputFolderEdit.Value, 'Select Base Output Folder');
            if ~isequal(folder, 0)
                app.OutputFolderEdit.Value = folder;
            end
        end

        function createQueuePanel(app, parent)
            p = uipanel(parent, 'Title', 'Experiment Queue');
            g = uigridlayout(p, [5, 1], 'RowHeight', {'fit', '1x', 'fit', 'fit', 'fit'});

            addRow = uigridlayout(g, [1, 2]);
            app.AddExperimentBtn = uibutton(addRow, 'Text', 'New Experiment...', 'ButtonPushedFcn', @(s,e) app.openExperimentEditor());
            app.LoadExperimentBtn = uibutton(addRow, 'Text', 'Load Experiment...', 'ButtonPushedFcn', @(s,e) app.loadExperiment());

            app.ExperimentListBox = uilistbox(g, 'Items', {}, 'DoubleClickedFcn', @(s,e) app.editSelectedExperiment());

            moveRow = uigridlayout(g, [1, 2]);
            app.MoveUpBtn = uibutton(moveRow, 'Text', 'Up', 'ButtonPushedFcn', @(s,e) app.moveExperimentUp());
            app.MoveDownBtn = uibutton(moveRow, 'Text', 'Down', 'ButtonPushedFcn', @(s,e) app.moveExperimentDown());

            editRow = uigridlayout(g, [1, 3]);
            app.RenameExperimentBtn = uibutton(editRow, 'Text', 'Rename', 'ButtonPushedFcn', @(s,e) app.renameExperiment());
            app.DuplicateExperimentBtn = uibutton(editRow, 'Text', 'Duplicate', 'ButtonPushedFcn', @(s,e) app.duplicateExperiment());
            app.RemoveExperimentBtn = uibutton(editRow, 'Text', 'Remove', 'ButtonPushedFcn', @(s,e) app.removeExperiment());

            app.ShutdownCheckbox = uicheckbox(g, 'Text', 'Shutdown after running all', 'Value', false);
        end

        function createRunPanel(app, parent)
            g = uigridlayout(parent, [2, 1], 'RowHeight', {'fit', 'fit'});

            thresholdRow = uigridlayout(g, [1, 2], 'ColumnWidth', {'1x', 80});
            uilabel(thresholdRow, 'Text', 'Helium Shutdown Threshold (%):');
            app.HeliumThresholdEdit = uieditfield(thresholdRow, 'numeric', 'Value', 60, 'Limits', [0 100]);

            btnRow = uigridlayout(g, [1, 2]);
            app.RunBtn = uibutton(btnRow, 'Text', 'RUN QUEUE', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.runQueue());
            app.StopBtn = uibutton(btnRow, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.stopQueue());
        end

        %% --- Hardware Connection ---
        function disconnectHardware(app)
            try delete(app.PPMS); app.PPMS = []; catch; end
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
                app.ConnectBtn.Text = 'Connecting...';
                app.ConnectBtn.Enable = 'off'; drawnow;

                app.PPMS     = QuantumDesign.QDPPMS(app.AddrPPMS.Value);
                app.M81      = Lakeshore.LakeshoreM81(app.AddrM81.Value);
                app.Switcher = Keithley.Keithley3706(app.AddrSwitch.Value);

                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.ConnectBtn.Enable = 'off';
                app.DisconnectBtn.Enable = 'on';
                app.RunBtn.Enable = 'on';
                app.logMessage('Hardware connected.');
            catch ME
                app.disconnectHardware();
                app.ConnectBtn.Text = 'Retry Connection';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                app.logMessage(sprintf('Connection error: %s', ME.message));
                uialert(app.UIFigure, ME.message, 'Connection Error');
            end
        end

        %% --- Queue Management ---
        function openExperimentEditor(app)
            def = PPMSExperimentEditor.run();
            if isempty(def); return; end
            app.addExperimentToQueue(def);
        end

        function editSelectedExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end

            def = PPMSExperimentEditor.run(app.ExperimentQueue{idx});
            if isempty(def); return; end

            app.ExperimentQueue{idx} = def;
            app.ExperimentListBox.Items{idx} = app.formatQueueLabel(def);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx};
        end

        function addExperimentToQueue(app, definition)
            label = app.formatQueueLabel(definition);
            app.ExperimentQueue{end+1} = definition;
            app.ExperimentListBox.Items{end+1} = label;
            app.ExperimentListBox.Value = label;
        end

        function label = formatQueueLabel(~, definition)
            label = sprintf('%s [%s]', definition.Name, definition.Type);
        end

        function loadExperiment(app)
            [file, path] = uigetfile('*.mat', 'Load Experiment Definition');
            if isequal(file, 0); return; end

            try
                data = load(fullfile(path, file), 'experiment');
                def = data.experiment;
                def.DefinitionFile = fullfile(path, file);
                app.addExperimentToQueue(def);
            catch ME
                uialert(app.UIFigure, sprintf('Failed to load experiment file: %s', ME.message), 'Load Error');
            end
        end

        function renameExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end

            def = app.ExperimentQueue{idx};
            answer = inputdlg('New name:', 'Rename Experiment', [1 50], {def.Name});
            if isempty(answer); return; end

            newName = strtrim(answer{1});
            if isempty(newName); return; end

            def.Name = newName;
            def = app.renameDefinitionFile(def);

            app.ExperimentQueue{idx} = def;
            app.ExperimentListBox.Items{idx} = app.formatQueueLabel(def);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx};
        end

        function duplicateExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end

            def = app.ExperimentQueue{idx};
            def.Name = [def.Name ' (Copy)'];

            if isfield(def, 'DefinitionFile') && ~isempty(def.DefinitionFile)
                def.DefinitionFile = app.resolveDuplicateFilename(def.DefinitionFile);
                app.resaveDefinitionFile(def);
            end

            label = app.formatQueueLabel(def);
            app.ExperimentQueue = [app.ExperimentQueue(1:idx), {def}, app.ExperimentQueue(idx+1:end)];
            app.ExperimentListBox.Items = [app.ExperimentListBox.Items(1:idx), {label}, app.ExperimentListBox.Items(idx+1:end)];
            app.ExperimentListBox.Value = label;
        end

        function resaveDefinitionFile(app, def)
            if ~isfield(def, 'DefinitionFile') || isempty(def.DefinitionFile); return; end
            try
                experiment = def; %#ok<NASGU>
                save(def.DefinitionFile, 'experiment');
            catch ME
                app.logMessage(sprintf('Could not update saved experiment file: %s', ME.message));
            end
        end

        function def = renameDefinitionFile(app, def)
            % Renames the saved .mat file on disk to match the new
            % experiment name, then resaves the (renamed) definition.
            if ~isfield(def, 'DefinitionFile') || isempty(def.DefinitionFile)
                return;
            end

            [filepath, ~, ext] = fileparts(def.DefinitionFile);
            safeName = regexprep(def.Name, '[^\w\- ]', '');
            if isempty(safeName); safeName = 'Experiment'; end
            desiredFile = fullfile(filepath, [safeName ext]);
            newFile = app.resolveUniqueFilename(desiredFile, def.DefinitionFile);

            try
                if ~strcmp(newFile, def.DefinitionFile) && isfile(def.DefinitionFile)
                    movefile(def.DefinitionFile, newFile);
                end
                def.DefinitionFile = newFile;
                app.resaveDefinitionFile(def);
            catch ME
                app.logMessage(sprintf('Could not rename saved experiment file: %s', ME.message));
            end
        end

        function candidate = resolveUniqueFilename(~, desiredFile, currentFile)
            % Like resolveDuplicateFilename, but allows desiredFile to
            % equal currentFile (no-op rename) instead of always bumping.
            if strcmp(desiredFile, currentFile)
                candidate = desiredFile;
                return;
            end
            [filepath, name, ext] = fileparts(desiredFile);
            candidate = desiredFile;
            counter = 1;
            while isfile(candidate) && ~strcmp(candidate, currentFile)
                counter = counter + 1;
                candidate = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
            end
        end

        function candidate = resolveDuplicateFilename(~, baseFile)
            [filepath, name, ext] = fileparts(baseFile);
            candidate = fullfile(filepath, [name '_copy' ext]);
            counter = 1;
            while isfile(candidate)
                counter = counter + 1;
                candidate = fullfile(filepath, sprintf('%s_copy%d%s', name, counter, ext));
            end
        end

        function removeExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end
            app.ExperimentQueue(idx) = [];
            app.ExperimentListBox.Items(idx) = [];
            if ~isempty(app.ExperimentListBox.Items)
                app.ExperimentListBox.Value = app.ExperimentListBox.Items{min(idx, end)};
            end
        end

        function moveExperimentUp(app)
            idx = app.selectedQueueIndex();
            if isempty(idx) || idx == 1; return; end
            app.swapQueueItems(idx, idx - 1);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx - 1};
        end

        function moveExperimentDown(app)
            idx = app.selectedQueueIndex();
            if isempty(idx) || idx == numel(app.ExperimentListBox.Items); return; end
            app.swapQueueItems(idx, idx + 1);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx + 1};
        end

        function idx = selectedQueueIndex(app)
            idx = find(strcmp(app.ExperimentListBox.Items, app.ExperimentListBox.Value));
        end

        function swapQueueItems(app, i, j)
            app.ExperimentQueue([i j]) = app.ExperimentQueue([j i]);
            app.ExperimentListBox.Items([i j]) = app.ExperimentListBox.Items([j i]);
        end

        %% --- Run / Stop ---
        function stopQueue(app)
            app.IsRunning = false;
            app.logMessage('Stop requested by user.');
        end

        function runQueue(app)
            if isempty(app.ExperimentQueue)
                uialert(app.UIFigure, 'Add at least one experiment to the queue.', 'Queue Empty');
                return;
            end

            if isempty(strtrim(app.OutputFolderEdit.Value))
                uialert(app.UIFigure, 'Set a base output folder before running the queue.', 'Output Folder Missing');
                return;
            end

            if ~isempty(strtrim(app.EmailEdit.Value)) && ~app.ensureGmailCredentials()
                app.logMessage('Email notifications skipped (no credentials provided).');
            end

            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            app.logMessage(sprintf('Starting queue: %d experiment(s).', numel(app.ExperimentQueue)));

            app.startHeliumWatchdog();
            watchdogCleanup = onCleanup(@() app.stopHeliumWatchdog()); %#ok<NASGU>

            try
                for i = 1:numel(app.ExperimentQueue)
                    if ~app.IsRunning; break; end
                    def = app.ExperimentQueue{i};
                    name = app.ExperimentListBox.Items{i};
                    app.logMessage(sprintf('Running experiment %d/%d: %s', i, numel(app.ExperimentQueue), name));

                    switch def.Type
                        case 'FieldSweep'
                            app.runFieldSweepExperiment(def);
                        otherwise
                            app.logMessage(sprintf('Experiment type "%s" is not implemented yet - skipping.', def.Type));
                    end

                    if ~app.IsRunning; break; end

                    app.sendNotification(sprintf('PPMS: Experiment Finished - %s', name), ...
                        sprintf('Experiment %d/%d "%s" has finished.', i, numel(app.ExperimentQueue), name));
                end

                if app.IsRunning
                    app.sendNotification('PPMS: Queue Finished', ...
                        sprintf('The experiment queue completed all %d experiment(s).', numel(app.ExperimentQueue)));
                else
                    app.sendNotification('PPMS: Queue Stopped', ...
                        sprintf('The experiment queue was stopped by the user (%d experiment(s) in the list).', numel(app.ExperimentQueue)));
                end

                if app.IsRunning && app.ShutdownCheckbox.Value
                    app.performShutdown();
                end

                app.logMessage('Queue finished.');
            catch ME
                if strcmp(ME.identifier, 'App:UserStop')
                    app.logMessage('Queue stopped by user during experiment execution.');
                    app.sendNotification('PPMS: Queue Stopped', ...
                        sprintf('The experiment queue was stopped by the user (%d experiment(s) in the list).', numel(app.ExperimentQueue)));
                else
                    app.logMessage(sprintf('Queue aborted: %s', ME.message));
                    app.sendNotification('PPMS: Queue Error', sprintf('The experiment queue aborted with an error: %s', ME.message));
                    uialert(app.UIFigure, ME.message, 'Queue Error');
                end
            end

            app.IsRunning = false;
            app.RunBtn.Enable = 'on';
            app.StopBtn.Enable = 'off';
        end

        %% --- Experiment Execution: Field Sweep ---
        function runFieldSweepExperiment(app, def)
            if isempty(app.PPMS) || isempty(app.M81) || isempty(app.Switcher)
                error('Hardware is not connected.');
            end

            numChannels = length(def.ChannelSets);
            if numChannels == 0
                error('Experiment "%s" has no channel sets configured.', def.Name);
            end

            dataFile = app.resolveExperimentDataFile(def);
            fileID = fopen(dataFile, 'w');
            if fileID < 0
                error('Could not open data file: %s', dataFile);
            end
            fileCleanup = onCleanup(@() app.safeCloseFile(fileID)); %#ok<NASGU>
            hwCleanup = onCleanup(@() app.safeStopMeasurement()); %#ok<NASGU>

            p = def.Params;
            lockIn = def.LockIn;
            staticTemp = def.Static.Temperature;
            staticAngle = def.Static.Angle;

            fprintf(fileID, '%% Experiment: %s\n', def.Name);
            fprintf(fileID, '%% Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Lock-In Current: %e A | Freq: %f Hz | TC: %f s\n', lockIn.Current, lockIn.Freq, lockIn.TC);
            fprintf(fileID, '%% Static Temperature: %f K\n', staticTemp);
            fprintf(fileID, '%% Static Angle: %f deg\n', staticAngle);
            fprintf(fileID, '%% PPMS Sweep: %f Oe to %f Oe at %f Oe/sec\n', p.StartField, p.EndField, p.Rate);
            fprintf(fileID, '%% Repetitions: %d | Back-and-forth: %d\n', def.Repeat.Repetitions, def.Repeat.BackAndForth);

            % Each channel gets its own Field/Resistance column pair
            % rather than sharing one Field value per row - the channels
            % in a row are measured sequentially (each taking ~1.7s+ with
            % settle time), so the field can drift noticeably between the
            % first and last channel of a row while the field is actively
            % sweeping. A shared field value would silently mis-tag the
            % later channels' readings.
            headerParts = {};
            for c = 1:numChannels
                vec = def.ChannelSets{c};
                chanLabel = sprintf('%d_%d_%d_%d', vec(1), vec(2), vec(3), vec(4));
                headerParts{end+1} = sprintf('Field_Oe_%s', chanLabel); %#ok<AGROW>
                headerParts{end+1} = sprintf('R_Ohm_%s', chanLabel); %#ok<AGROW>
            end
            fprintf(fileID, '%s\n', strjoin(headerParts, ','));

            cla(app.PlotAxes);
            title(app.PlotAxes, sprintf('%s - Resistance vs. Magnetic Field', def.Name));
            xlabel(app.PlotAxes, 'Magnetic Field (Oe)');
            ylabel(app.PlotAxes, 'Resistance (\Omega)');
            grid(app.PlotAxes, 'on');
            dataLines = cell(1, numChannels);
            colors = lines(numChannels);
            for c = 1:numChannels
                dataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, def.ChannelItems, 'Location', 'best');

            % Hold temperature static for the duration of the field sweep,
            % and wait for it to stabilize before doing anything else.
            app.logMessage(sprintf('Setting static temperature to %.2f K...', staticTemp));
            app.PPMS.setTemperature(staticTemp, 10.0, 'FastSettle');
            while app.IsRunning
                if app.PPMS.waitConditionReached(true, false, false, false)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end
            app.logMessage(sprintf('Temperature stabilized at %.2f K.', staticTemp));

            % Hold rotator angle static. getRotatorAngle()'s own status
            % flag isn't a live motion indicator, but the MOVE? query has
            % a dedicated position status (see getMovePosition). Use that
            % as the primary "stopped" signal, with the position
            % tolerance kept as a fallback in case the assumed status
            % code (1 = "stopped at target") turns out to be wrong.
            app.logMessage(sprintf('Setting static angle to %.2f deg...', staticAngle));
            app.PPMS.setRotatorAngle(staticAngle, 5.0);
            loggedMoveStatus = false;
            while app.IsRunning
                [currentAngle, moveStatus, ~] = app.PPMS.getMovePosition();
                if ~loggedMoveStatus && ~isnan(moveStatus)
                    app.logMessage(sprintf(['Rotator MOVE? status code observed: %g ', ...
                        '(expected 1 = "stopped at target" per GPIB manual - confirm this).'], moveStatus));
                    loggedMoveStatus = true;
                end

                stoppedByStatus = ~isnan(moveStatus) && moveStatus == 1;
                stoppedByTolerance = ~isnan(currentAngle) && abs(currentAngle - staticAngle) < 1.0;
                if stoppedByTolerance && ~stoppedByStatus
                    app.logMessage(sprintf(['Angle within tolerance but MOVE? status code was %g, not 1 - ', ...
                        'the status-based check did not trip, only the tolerance fallback did.'], moveStatus));
                end
                if stoppedByStatus || stoppedByTolerance
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end
            app.logMessage(sprintf('Angle stabilized at %.2f deg.', staticAngle));

            % Configure M81 lock-in.
            app.M81.setSourceMode('AC', lockIn.Current, 0.0, lockIn.Freq);
            app.M81.setSourceRange('AUTO');
            app.M81.setMeasureMode('LIA');
            app.M81.setMeasureRange('AUTO');
            app.M81.setTimeConstant(lockIn.TC);
            app.M81.configureResistanceMode('4WIRE', 'AC');
            app.M81.setOutputState(false);

            % Single-channel experiments: connect once now and leave
            % current on the sample for the entire run, rather than
            % cycling the relay/output on every measurement. Multi-
            % channel experiments still cold-swap per channel as before.
            if numChannels == 1
                app.logMessage('Single channel configured - connecting once and keeping current on for the whole run.');
                app.Switcher.closeChannels(def.ChannelSets{1});
                pause(0.2);
                app.M81.setOutputState(true);
                pause(max(lockIn.TC * 5, 1.5));
                app.LastClosedChannel = def.ChannelSets{1};
            end

            % Ramp to start field and wait for it to stabilize.
            app.logMessage(sprintf('Ramping to start field (%.1f Oe)...', p.StartField));
            app.PPMS.setMagneticField(p.StartField, 100.0, 'Linear', 'Driven');
            pause(10);
            while app.IsRunning
                if app.PPMS.waitConditionReached(false, true, false, false)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            % Sweep from Start to End, optionally back to Start, repeated.
            totalReps = def.Repeat.Repetitions;
            backForth = def.Repeat.BackAndForth;

            for rep = 1:totalReps
                if ~app.IsRunning; break; end

                legLabel = sprintf('Rep %d/%d (forward)', rep, totalReps);
                app.runFieldSweepLeg(fileID, dataLines, def, p.EndField, p.Rate, p.Interval, legLabel);

                if backForth
                    if ~app.IsRunning; break; end
                    legLabel = sprintf('Rep %d/%d (reverse)', rep, totalReps);
                    app.runFieldSweepLeg(fileID, dataLines, def, p.StartField, p.Rate, p.Interval, legLabel);
                end
            end

            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            if backForth
                backForthNote = ' back-and-forth';
            else
                backForthNote = '';
            end
            app.logMessage(sprintf('Field sweep "%s" complete (%d repetition(s)%s). Data saved to %s', ...
                def.Name, totalReps, backForthNote, dataFile));
        end

        function runFieldSweepLeg(app, fileID, dataLines, def, targetField, rate, interval, legLabel)
            % Sweeps from wherever the field currently is to targetField,
            % multiplexing through the channel sets and logging a CSV row
            % once per interval. Assumes the field is already stable at
            % the leg's starting point (guaranteed by the caller: either
            % the initial start-field ramp, or the previous leg ending
            % there).
            numChannels = length(def.ChannelSets);
            lockIn = def.LockIn;

            app.logMessage(sprintf('%s: sweeping to %.1f Oe...', legLabel, targetField));
            app.PPMS.setMagneticField(targetField, rate, 'Linear', 'Driven');

            overrunCount = 0;
            worstOverrun = 0;

            while app.IsRunning
                loopTimer = tic;
                stepFields = NaN(1, numChannels);
                stepValues = NaN(1, numChannels);

                for c = 1:numChannels
                    if ~app.IsRunning; break; end

                    channelTimer = tic;

                    thisChannel = def.ChannelSets{c};
                    skipSwap = (numChannels == 1) && ~isempty(app.LastClosedChannel);

                    if skipSwap
                        % Only one channel in this experiment and it's
                        % already connected (either from setup, or from a
                        % previous read) - output was never turned off,
                        % so skip the relay cycle and settle pause.
                        settleTime = 0;
                    else
                        app.M81.setOutputState(false);
                        app.Switcher.closeChannels(thisChannel);
                        pause(0.2);
                        app.M81.setOutputState(true);
                        settleTime = max(lockIn.TC * 5, 1.5);
                        pause(settleTime);
                        app.LastClosedChannel = thisChannel;
                    end
                    swapTime = toc(channelTimer);

                    % Read field immediately before this channel's
                    % resistance measurement, since the field keeps
                    % moving while other channels are being measured -
                    % each channel needs its own field value, not one
                    % shared per row.
                    [chanField, ~] = app.PPMS.getCurrentField();

                    readTimer = tic;
                    rVal = NaN;
                    attemptsUsed = 0;
                    for attempt = 1:4
                        attemptsUsed = attempt;
                        try
                            rVal = app.M81.readResistance();
                            %[~, ~, rVal, ~] = app.M81.readLockIn();
                            if isnan(rVal)
                                %[~, ~, R_mag, ~] = app.M81.readLockIn();
                                %rVal = R_mag / lockIn.Current;
                                [V_real, ~, ~, ~] = app.M81.readLockIn();
                                rVal = V_real / lockIn.Current;
                            end
                            if ~isnan(rVal) && abs(rVal) < 1e6
                                break;
                            end
                        catch ME_Read
                            if attempt == 4; rethrow(ME_Read); end
                            pause(0.5);
                        end
                    end
                    readTime = toc(readTimer);
                    totalChannelTime = toc(channelTimer);

                    app.logMessage(sprintf(['Ch %d timing: swap=%.2fs settle=%.2fs read=%.2fs ', ...
                        '(attempts=%d) total=%.2fs'], c, swapTime, settleTime, readTime, attemptsUsed, totalChannelTime));

                    stepFields(c) = chanField;
                    stepValues(c) = rVal;
                    if abs(rVal) < 1e6
                        addpoints(dataLines{c}, chanField, rVal);
                    end
                    drawnow limitrate;
                end

                if app.IsRunning
                    rowParts = cell(1, numChannels * 2);
                    for c = 1:numChannels
                        rowParts{2*c - 1} = sprintf('%f', stepFields(c));
                        rowParts{2*c} = sprintf('%e', stepValues(c));
                    end
                    fprintf(fileID, '%s\n', strjoin(rowParts, ','));
                end

                if app.PPMS.waitConditionReached(false, true, false, false)
                    break;
                end

                timeTaken = toc(loopTimer);
                remainingWait = interval - timeTaken;
                if remainingWait > 0
                    pause(remainingWait);
                else
                    overrunCount = overrunCount + 1;
                    worstOverrun = max(worstOverrun, -remainingWait);
                    drawnow;
                end
            end

            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            if overrunCount > 0
                app.logMessage(sprintf(['%s: %d interval(s) ran over the %.1fs budget ', ...
                    '(worst overrun: %.1fs). Measurement is taking longer than the configured interval.'], ...
                    legLabel, overrunCount, interval, worstOverrun));
            end

            app.logMessage(sprintf('%s complete.', legLabel));
        end

        function safeCloseFile(~, fileID)
            try
                fclose(fileID);
            catch
            end
        end

        function safeStopMeasurement(app)
            try app.M81.setOutputState(false); catch; end
            try app.Switcher.openAllChannels(); catch; end
        end

        function safeFile = resolveUniqueDataFilename(~, baseFile)
            [filepath, name, ext] = fileparts(baseFile);
            safeFile = baseFile;
            counter = 1;
            while isfile(safeFile)
                safeFile = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
                counter = counter + 1;
            end
        end

        function dataFile = resolveExperimentDataFile(app, def)
            % All experiment data lives under a single base folder
            % (app.OutputFolderEdit), organized into one subfolder per
            % experiment name - no per-experiment path configuration
            % needed in the editor.
            baseFolder = strtrim(app.OutputFolderEdit.Value);
            safeName = regexprep(def.Name, '[^\w\- ]', '');
            if isempty(safeName); safeName = 'Experiment'; end

            expFolder = fullfile(baseFolder, safeName);
            if ~isfolder(expFolder)
                mkdir(expFolder);
            end

            dataFile = app.resolveUniqueDataFilename(fullfile(expFolder, [safeName '.csv']));
        end

        function performShutdown(app)
            app.logMessage('Beginning shutdown sequence...');
            try
                % Zero the M81 excitation current.
                app.M81.setOutputState(false);
                app.logMessage('M81 output disabled.');

                % Ramp the magnetic field back to zero and wait for it to settle.
                app.PPMS.setMagneticField(0.0, 100.0, 'Linear', 'Driven');
                while true
                    if app.PPMS.waitConditionReached(false, true, false, false); break; end
                    pause(1);
                end
                app.logMessage('Magnetic field ramped to 0 Oe.');

                try
                    app.PPMS.shutdownTemperatureController();
                    app.logMessage('Temperature controller placed in standby.');
                catch ME_Temp
                    app.logMessage(sprintf('Could not set temperature standby: %s', ME_Temp.message));
                end

                app.disconnectHardware();
                app.logMessage('Shutdown complete - hardware disconnected.');
                app.sendNotification('PPMS: Shutdown Complete', 'The post-queue shutdown sequence has finished; hardware disconnected.');
            catch ME
                app.logMessage(sprintf('Shutdown error: %s', ME.message));
                app.sendNotification('PPMS: CRITICAL ERROR! Shutdown Failed', ...
                    sprintf('The shutdown sequence encountered an error and may not have completed safely: %s\n\nCheck the PPMS, M81, and switcher state manually as soon as possible.', ME.message));
            end
        end

        %% --- Logging & Notifications ---
        function logMessage(app, msg)
            timestamp = datestr(now, 'HH:MM:SS');
            line = sprintf('[%s] %s', timestamp, msg);
            app.LogTextArea.Value = [app.LogTextArea.Value; {line}];
            scroll(app.LogTextArea, 'bottom');
        end

        function sendNotification(app, subject, content)
            recipient = strtrim(app.EmailEdit.Value);
            if isempty(recipient); return; end
            if isempty(app.GmailLogin) || isempty(app.GmailPassword); return; end

            timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            body = sprintf('[%s]\n\n%s', timestamp, content);

            try
                SendGmail(app.GmailLogin, app.GmailPassword, recipient, subject, body);
                app.logMessage(sprintf('Email sent to %s: %s', recipient, subject));
            catch ME
                app.logMessage(sprintf('Failed to send email: %s', ME.message));
                % Drop the cached credentials so the next run re-prompts
                % instead of silently repeating the same failed login.
                app.GmailLogin = '';
                app.GmailPassword = '';
            end
        end

        function ok = ensureGmailCredentials(app)
            % Prompts for the sending Gmail account's address and App
            % Password if not already cached in memory or loaded from an
            % encrypted on-disk file (see loadGmailCredentials).
            if ~isempty(app.GmailLogin) && ~isempty(app.GmailPassword)
                ok = true;
                return;
            end

            answer = inputdlg({'Sending Gmail address:', 'Gmail App Password:'}, ...
                'Email Notification Credentials', [1 50; 1 50]);
            if isempty(answer) || isempty(strtrim(answer{1})) || isempty(answer{2})
                ok = false;
                return;
            end

            app.GmailLogin = strtrim(answer{1});
            app.GmailPassword = answer{2};
            ok = true;

            choice = uiconfirm(app.UIFigure, ...
                'Remember this login securely on this PC for future sessions?', ...
                'Save Credentials', 'Options', {'Yes', 'No'}, 'DefaultOption', 2, 'CancelOption', 2);
            if strcmp(choice, 'Yes')
                app.saveGmailCredentials();
            end
        end

        %% --- Gmail Credential Persistence (Windows DPAPI, per-user encrypted) ---
        function filePath = gmailCredentialFile(~)
            folder = fullfile(getenv('LOCALAPPDATA'), 'PPMSTamarController');
            if ~isfolder(folder)
                mkdir(folder);
            end
            filePath = fullfile(folder, 'gmail_credentials.dat');
        end

        function entropy = gmailCredentialEntropy(~)
            entropy = uint8(System.Text.Encoding.UTF8.GetBytes('PPMSTamarController.GmailCred.v1'));
        end

        function saveGmailCredentials(app)
            try
                NET.addAssembly('System.Security');
                plainText = sprintf('%s\n%s', app.GmailLogin, app.GmailPassword);
                plainBytes = uint8(System.Text.Encoding.UTF8.GetBytes(plainText));
                entropy = app.gmailCredentialEntropy();
                scope = System.Security.Cryptography.DataProtectionScope.CurrentUser;
                encrypted = System.Security.Cryptography.ProtectedData.Protect(plainBytes, entropy, scope);

                fid = fopen(app.gmailCredentialFile(), 'w');
                fwrite(fid, uint8(encrypted), 'uint8');
                fclose(fid);
                app.logMessage('Gmail credentials saved (encrypted, this PC/user only).');
            catch ME
                app.logMessage(sprintf('Could not save Gmail credentials: %s', ME.message));
            end
        end

        function loadGmailCredentials(app)
            filePath = app.gmailCredentialFile();
            if ~isfile(filePath)
                return;
            end

            try
                NET.addAssembly('System.Security');
                fid = fopen(filePath, 'r');
                encrypted = fread(fid, Inf, 'uint8=>uint8')';
                fclose(fid);

                entropy = app.gmailCredentialEntropy();
                scope = System.Security.Cryptography.DataProtectionScope.CurrentUser;
                decrypted = System.Security.Cryptography.ProtectedData.Unprotect(encrypted, entropy, scope);
                plainText = char(System.Text.Encoding.UTF8.GetString(decrypted));

                parts = strsplit(plainText, newline, 'CollapseDelimiters', false);
                if numel(parts) >= 2
                    app.GmailLogin = parts{1};
                    app.GmailPassword = parts{2};
                    app.logMessage('Loaded saved Gmail credentials for this PC/user.');
                end
            catch ME
                app.logMessage(sprintf('Could not load saved Gmail credentials: %s', ME.message));
            end
        end

        function forgetGmailCredentials(app)
            app.GmailLogin = '';
            app.GmailPassword = '';
            filePath = app.gmailCredentialFile();
            if isfile(filePath)
                try
                    delete(filePath);
                catch ME
                    app.logMessage(sprintf('Could not delete saved credentials file: %s', ME.message));
                    return;
                end
            end
            app.logMessage('Saved Gmail credentials forgotten.');
        end

        %% --- Helium Watchdog ---
        % Uses LEVELON OpCode 0 (one-shot: turn on, read, auto-off) rather
        % than continuous mode - each poll is self-contained, so there's
        % no 60s keep-alive window to race against, and it matches the
        % manual's own guidance to minimize cryogen consumption. The
        % trade-off is a ~10s wait per check for the reading to be ready.
        function startHeliumWatchdog(app)
            app.stopHeliumWatchdog();
            app.HeliumTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 60, ...
                'TimerFcn', @(~,~) app.checkHeliumLevel());
            start(app.HeliumTimer);
            app.logMessage(sprintf('Helium watchdog started (threshold %.1f%%).', app.HeliumThresholdEdit.Value));
        end

        function stopHeliumWatchdog(app)
            if ~isempty(app.HeliumTimer) && isvalid(app.HeliumTimer)
                stop(app.HeliumTimer);
                delete(app.HeliumTimer);
            end
            app.HeliumTimer = [];
        end

        function checkHeliumLevel(app)
            if isempty(app.PPMS); return; end

            try
                app.PPMS.setHeliumLevelMeter(0);  % trigger a fresh one-shot read
                pause(10);                        % reading isn't ready until ~10s later
                [level, ~] = app.PPMS.getHeliumLevel();
            catch ME
                app.logMessage(sprintf('Helium level check failed: %s', ME.message));
                return;
            end

            if isnan(level); return; end

            threshold = app.HeliumThresholdEdit.Value;
            app.logMessage(sprintf('Helium level: %.1f%% (threshold %.1f%%)', level, threshold));

            if level < threshold
                app.logMessage(sprintf('CRITICAL: Helium level %.1f%% below threshold %.1f%% - forcing shutdown.', level, threshold));
                app.sendNotification('PPMS: EMERGENCY - Low Helium Level', ...
                    sprintf('Helium level dropped to %.1f%% (threshold %.1f%%). Forcing an emergency shutdown.', level, threshold));
                app.IsRunning = false;
                app.performShutdown();
            end
        end

        function onAppClose(app)
            app.stopHeliumWatchdog();
            app.disconnectHardware();
            delete(app.UIFigure);
        end
    end
end
