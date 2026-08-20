classdef Lakeshore335 < handle
    % Lakeshore335 - Object-Oriented MATLAB Wrapper for Lake Shore 335
    % Designed for PT1000 sensor integration and temperature sweeping.
    
    properties (Access = private)
        VisaObj             
        IsSimulated = false 
    end
    
    methods
        %% Constructor: Initialize Connection
        function obj = Lakeshore335(resourceString)
            % Initialize connection with an option for simulated mode
            if strcmpi(resourceString, 'SIM')
                obj.IsSimulated = true;
                fprintf('[SIM] Lake Shore 335 initialized in simulation mode.\n');
                return;
            end
            
            try
                obj.VisaObj = visadev(resourceString);
                configureTerminator(obj.VisaObj, 'LF'); 
                idn = writeread(obj.VisaObj, '*IDN?');
                fprintf('Connected to Instrument: %s\n', idn);
            catch ME
                error('Failed to open VISA connection to Lake Shore 335. Error: %s', ME.message);
            end
        end
        
        %% Destructor: Safely turn off outputs on script exit
        function delete(obj)
            % Ensure safe shutdown of hardware connections[cite: 1]
            if ~obj.IsSimulated && ~isempty(obj.VisaObj)
                % Turn off heaters safely (Loop 1 and Loop 2)
                obj.setHeaterRange(1, 0); 
                obj.setHeaterRange(2, 0); 
                clear obj.VisaObj;
                fprintf('Lake Shore 335 Connection closed safely.\n');
            end
        end
        
        %% --- SENSOR CONFIGURATION ---
        function configurePT1000(obj, channel)
            % Configures the specified input channel (e.g., 'A' or 'B') for a PT1000 RTD.
            % INTYPE params: <input>, <sensor_type>(3=Platinum), <autorange>(1=on),
            % <range>(0), <compensation>(1=on), <units>(1=Kelvin)
            if obj.IsSimulated; return; end
            
            chanStr = upper(channel);
            command = sprintf('INTYPE %s, 3, 1, 0, 1, 1', chanStr);
            writeline(obj.VisaObj, command);
            fprintf('Channel %s configured for PT1000 sensor.\n', chanStr);
        end
        
        %% --- TEMPERATURE CONTROL ---
        function setRampRate(obj, loop, enable, rate)
            % Sets the ramp rate for a specific control loop (1 or 2).
            % enable: true (1) or false (0)
            % rate: Kelvin per minute (0.1 to 100)
            if obj.IsSimulated; return; end
            
            state = double(enable);
            command = sprintf('RAMP %d, %d, %g', loop, state, rate);
            writeline(obj.VisaObj, command);
        end
        
        function setTargetTemperature(obj, loop, targetTemp)
            % Sets the setpoint temperature for the specified loop.
            if obj.IsSimulated; return; end
            
            command = sprintf('SETP %d, %g', loop, targetTemp);
            writeline(obj.VisaObj, command);
        end
        
        function setHeaterRange(obj, loop, rangeVal)
            % Range: 0=Off, 1=Low, 2=Medium, 3=High
            if obj.IsSimulated; return; end
            
            command = sprintf('RANGE %d, %d', loop, rangeVal);
            writeline(obj.VisaObj, command);
        end
        
        %% --- MEASUREMENT & POLLING ---
        function currentTemp = readTemperature(obj, channel)
            % Reads the current temperature of the specified channel ('A' or 'B').
            if obj.IsSimulated
                currentTemp = 295.0 + randn()*0.05; % Return simulated room temp
                return;
            end
            
            chanStr = upper(channel);
            command = sprintf('KRDG? %s', chanStr);
            currentTemp = str2double(writeread(obj.VisaObj, command));
        end
        
        function isReached = checkTemperatureReached(obj, channel, targetTemp, tolerance)
            % Helper method to check if the temperature is within an acceptable tolerance.
            % Default tolerance is 0.1K if not specified.
            if nargin < 4
                tolerance = 0.1;
            end
            
            currentTemp = obj.readTemperature(channel);
            isReached = abs(currentTemp - targetTemp) <= tolerance;
        end
        
        function waitForTemperature(obj, channel, targetTemp, tolerance, timeoutSeconds)
            % Blocks execution until the temperature is reached or timeout occurs.
            if nargin < 4; tolerance = 0.1; end
            if nargin < 5; timeoutSeconds = 600; end % Default 10 minute timeout
            
            fprintf('Waiting for temperature to reach %.2f K...\n', targetTemp);
            
            tic;
            while toc < timeoutSeconds
                current = obj.readTemperature(channel);
                if abs(current - targetTemp) <= tolerance
                    fprintf('Target temperature reached: %.2f K\n', current);
                    return;
                end
                pause(1.0); % Poll every 1 second
            end
            
            warning('Timeout reached before target temperature was achieved.');
        end
    end
end