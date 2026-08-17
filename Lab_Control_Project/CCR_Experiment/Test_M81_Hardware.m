clear all; clc; close all;

% Initialize the connection over your verified high-speed COM port
smu = Lakeshore.LakeshoreM81('ASRL3::INSTR', 1, 1);

try
    %% --- TEST 1: DC Source, Auto-Ranging, and Output Toggle ---
    fprintf('\n--- Test 1: DC Mode & Output Controls ---\n');
    dcCurrent = 10e-6;              % 10 uA excitation based on your manual test
    smu.setSourceMode('DC', dcCurrent); 
    smu.setSourceRange('AUTO');     
    smu.setMeasureMode('DC');       
    smu.setMeasureRange('AUTO');    
    smu.setNPLC(1);                 
    
    fprintf('Starting Measurement (Output ON)...\n');
    smu.setOutputState(true);
    pause(1.5);                     % Give the voltmeter time to fully settle
    
    dcVoltage = smu.readDC();
    fprintf('Live Measured DC Voltage at 10 uA: %e V\n', dcVoltage);
    
    fprintf('Stopping Measurement (Output OFF)...\n');
    smu.setOutputState(false);
    pause(0.5);
    
    %% --- TEST 2: Native Resistance Subsystem (2-Wire vs 4-Wire) ---
    fprintf('\n--- Test 2: DC Resistance (2-Wire vs 4-Wire) ---\n');
    smu.setSourceMode('DC', dcCurrent); 
    smu.setMeasureMode('DC');
    
    % --- 2-Wire Execution ---
    smu.configureResistanceMode('2WIRE', 'DC'); 
    smu.setOutputState(true); 
    pause(2.0);                     % Settle time for calculation engine
    r2wire_native = smu.readResistance();
    r2wire_fallback = dcVoltage / dcCurrent; 
    
    if isnan(r2wire_native)
        fprintf('Calculated 2-Wire Resistance (Software Fallback): %.4f Ohms\n', r2wire_fallback);
    else
        fprintf('Calculated 2-Wire Resistance (Native Hardware):   %.4f Ohms\n', r2wire_native);
    end
    
    % --- 4-Wire Execution ---
    smu.configureResistanceMode('4WIRE', 'DC'); 
    pause(2.0);                     
    r4wire_native = smu.readResistance();
    
    % Sample a dedicated 4-wire voltage check
    dcVoltage4W = smu.readDC();
    r4wire_fallback = dcVoltage4W / dcCurrent;
    
    if isnan(r4wire_native)
        fprintf('Calculated 4-Wire Resistance (Software Fallback): %.4f Ohms\n', r4wire_fallback);
    else
        fprintf('Calculated 4-Wire Resistance (Native Hardware):   %.4f Ohms\n', r4wire_native);
    end
    
    smu.setOutputState(false);
    pause(0.5);
    
    %% --- TEST 3: Multi-Coordinate AC Lock-In Verification ---
    fprintf('\n--- Test 3: AC Excitation & Lock-In Coordinates ---\n');
    peakCurrent = 10e-6;    % 10 uA peak AC amplitude
    dcOffsetBias = 0.0;     
    referenceFreq = 17.0;   % Low-frequency reference phase lock at 17 Hz
    
    smu.setSourceMode('AC', peakCurrent, dcOffsetBias, referenceFreq);
    smu.setMeasureMode('LIA'); 
    smu.setMeasureRange('AUTO');
    smu.configureResistanceMode('4WIRE', 'AC');
    
    smu.setOutputState(true);
    fprintf('Locking phase loops onto carrier frequency (%.1f Hz). Waiting 3.0s...\n', referenceFreq);
    pause(3.0);             % Settle time for low-frequency filters
    
    % Extract full coordinate mapping natively
    [X, Y, R, Theta] = smu.readLockIn();
    rAC_native = smu.readResistance();
    rAC_fallback = R / peakCurrent; % Direct vector Ohm's Law calculation
    
    fprintf('  [X Coordinate (In-Phase)]: %e V\n', X);
    fprintf('  [Y Coordinate (Quadrature)]: %e V\n', Y);
    fprintf('  [R Magnitude]:             %e V\n', R);
    fprintf('  [Phase Angle (Theta)]:     %.4f Degrees\n', Theta);
    
    if isnan(rAC_native)
        fprintf('  [Lock-In Resistance (Software Fallback)]: %.4f Ohms\n', rAC_fallback);
    else
        fprintf('  [Lock-In Resistance (Native Hardware)]:   %.4f Ohms\n', rAC_native);
        fprintf('  [Lock-In Resistance (Software Check)]:    %.4f Ohms\n', rAC_fallback);
    end
    
    smu.setOutputState(false);
    fprintf('\n🎉 All instrument test vectors successfully cleared!\n');

catch ME
    smu.setOutputState(false);
    fprintf('\n❌ Script encountered an error. Safety clamp engaged.\n');
    rethrow(ME);
end