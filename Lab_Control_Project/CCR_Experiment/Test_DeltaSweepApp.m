%% Test_DeltaSweepApp.m
% Launches the DeltaSweepApp and provides a console guide for SIM testing

clear all; close all; clc;

fprintf('======================================================\n');
fprintf('      Launching DeltaSweepApp in SIMULATION Mode      \n');
fprintf('======================================================\n\n');

try
    % 1. Instantiate the GUI Object
    app = DeltaSweepApp();

    % 2. Print out the interactive testing guide
    fprintf('✅ GUI loaded successfully!\n\n');
    fprintf('To verify the application pipeline, follow these 4 steps in the window:\n');
    fprintf('  1. Click [Connect Instruments]\n');
    fprintf('     -> Notice the buttons turn green and the console prints the [SIM] hardware connections.\n\n');

    fprintf('  2. Click [Add Channel Set]\n');
    fprintf('     -> This adds the default routing configuration to the listbox.\n\n');

    fprintf('  3. Click [RUN EXPERIMENT]\n');
    fprintf('     -> A file browser will pop up. Name the file "SimTest.csv" and save it.\n\n');

    fprintf('  4. Watch the Live Plot!\n');
    fprintf('     -> The script will generate mock sine wave data to simulate delta mode voltages.\n');
    fprintf('     -> Try clicking the [Autoscale ON] button to toggle manual panning and zooming.\n\n');

catch ME
    fprintf('❌ Failed to launch the GUI. Ensure your +Keithley and +NI folders are in this directory.\n');
    fprintf('Error message: %s\n', ME.message);
end