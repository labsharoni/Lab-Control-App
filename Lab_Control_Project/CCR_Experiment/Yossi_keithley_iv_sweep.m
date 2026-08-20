
function keithley_iv_sweep()
import Keithley.*
close all
instrreset

    % --- Configuration ---
    gpib_board = 0;       % Your NI-GPIB Board Index (usually 0)
    gpib_address = 23;    % Your Keithley 2400 GPIB address
    
    v_start = 6;          % V1: Start voltage (V)
    v_stop = 12;           % V2: Stop voltage (V)
    num_points = 21;      % Number of points in the sweep
    
    % Generate voltage sweep array
    v_sweep = linspace(v_start, v_stop, num_points);
    v_measured = zeros(size(v_sweep));
    i_measured = zeros(size(v_sweep));
    r_measured = zeros(size(v_sweep));
    
    % --- Main Execution ---
    try
        % 1. Initialize the instrument using the National Instruments layer
        smu = Keithley_2400_init(gpib_board, gpib_address);
        
        % 2. Set to Voltage Source mode
        Keithley_2400_set_v_source(smu);
        
        % Turn on the output
        Keithley_2400_enable(smu);
        
        % 3. Loop through voltages and measure current
        fprintf('Starting IV Sweep using NI Driver...\n');
        for k = 1:num_points
            Keithley_2400_set_v(smu, v_sweep(k));
            
            % Allow a brief moment for settling (e.g., 50ms)
            pause(0.05); 
            
            [v_measured(k),i_measured(k),r_measured(k)] = Keithley_2400_read(smu);

            fprintf('V: %.3f I: %.6e R: %.6e A\n', v_sweep(k), i_measured(k), r_measured(k));
        end
        
        % Turn off the output safely
        Keithley_2400_disable(smu);
        
        % 4. Close the connection
        Keithley_2400_close(smu);
        
        % --- Plotting Results ---
        figure;
        plot(v_sweep, r_measured, '-or', 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
        grid on;
        xlabel('Voltage (V)');
        ylabel('R (ohm)');
        title('Keithley 2400 R-V Sweep via NI-GPIB');
        
    catch ME
        % Error handling to ensure the instrument is closed if something fails
        fprintf('\nAn error occurred: %s\n', ME.message);
        if exist('smu', 'var') && isvalid(smu)
            fprintf(smu, ':OUTP OFF');
            Keithley_2400_close(smu);
        end
    end
end

% =========================================================================
% INTERNAL FUNCTIONS (EXPLICIT FOR NATIONAL INSTRUMENTS LAYER)
% =========================================================================



function Keithley_2400_set_v(smu, voltage)
% Sets the source voltage level
    fprintf(smu, sprintf(':SOUR:VOLT:LEV %.4f', voltage));
end
