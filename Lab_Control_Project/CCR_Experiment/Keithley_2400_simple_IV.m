% Define the VISA address for your USB-to-GPIB connection 
% (You can find the exact string using the visadevlist command in MATLAB)
% gpib_address = 'GPIB0::24::INSTR'; 
gpib_address = 'sim'; 

% 1. Instantiate the instrument
smu = Keithley.Keithley2400(gpib_address);

% 2. Setup the measurement
compliance_I = 1e-3; % 1 mA compliance to protect the sample
smu.setVoltageSource(compliance_I);
smu.setOutput('ON');

% 3. Run a quick sweep
voltages_to_source = linspace(-1, 1, 21); % -1V to 1V, 21 points
measured_currents = zeros(size(voltages_to_source));

for i = 1:length(voltages_to_source)
    smu.setVoltage(voltages_to_source(i));
    pause(0.1); % Give the instrument/sample time to settle

    [V, I, R] = smu.readData();
    measured_currents(i) = I;
end

% 4. Turn off output (Safety first!)
smu.setOutput('OFF');

% 5. Plot
plot(voltages_to_source, measured_currents, 'o-');
xlabel('Voltage (V)');
ylabel('Current (A)');
title('Keithley 2400 IV Sweep');