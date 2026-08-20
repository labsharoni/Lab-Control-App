classdef Lakeshore335 < handle
    % Lakeshore335 - Object-Oriented MATLAB Wrapper for Lake Shore Model 335
    % Temperature Controller with PT1000 / Platinum RTD support.
    
    properties (Access = private)
        VisaObj             
        IsSimulated = false 
        DefaultInput = 'A'   % Default sensor input ('A' or 'B')
        DefaultLoop  = 1     % Default control loop (1 or 2)
        
        % Simulation state memory
        SimSetpoint = 300.0
        SimCurrentTemp = 295.0
        SimRamping = false
        SimRampRate = 1.0
        SimHeaterRange = 0
    end
    
    methods
        %% Constructor: Initialize Connection
        function obj = Lakeshore335(resourceString, defaultInput, defaultLoop)
            if nargin < 2; defaultInput = 'A'; end
            if nargin < 3; defaultLoop = 1; end
            
            obj.DefaultInput = upper(char(defaultInput));
            obj.DefaultLoop = defaultLoop;
            
            if strcmpi(resourceString, 'SIM')
                obj.IsSimulated = true;
                fprintf('[SIM] Lake Shore 335 initialized in simulation mode.\n');
                return;
            end
            
            try
                obj.VisaObj = visadev(resourceString);
                if contains(upper(resourceString), 'ASRL') || contains(upper(resourceString), 'COM')
                    obj.VisaObj.BaudRate = 57600;
                    obj.VisaObj.DataBits = 7;
                    obj.VisaObj.Parity = 'odd';
                    obj.VisaObj.StopBits = 1;
                    obj.VisaObj.FlowControl = 'none';
                end
                configureTerminator(obj.VisaObj, 'CR/LF'); 
                
                idn = writeread(obj.VisaObj, '*IDN?');
                fprintf('Connected to Temperature Controller: %s\n', strtrim(idn));
            catch ME
                error('Failed to open VISA connection to Lake Shore 335. Error: %s', ME.message);
            end
        end
        
        %% Destructor: Turn off heaters and unlock keypad
        function delete(obj)
            if ~obj.IsSimulated && ~isempty(obj.VisaObj)
                try
                    obj.setHeaterRange(0, 1); % Turn off Loop 1 heater
                    obj.setHeaterRange(0, 2); % Turn off Loop 2 heater
                    obj.unlockKeypad();       % Remove software keypad lock
                catch
                end
                
                % Force MATLAB to release the VISA handle completely
                delete(obj.VisaObj);
                obj.VisaObj = []; 
                fprintf('Lake Shore 335 connection closed cleanly (VISA session destroyed).\n');
            end
        end

        %% --- KEYPAD LOCK / UNLOCK ---
        function unlockKeypad(obj)
            % Disable keypad lockout on the 335 front panel using default 3-digit code
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, 'LOCK 0,000');
        end
        
        function lockKeypad(obj)
            % Fully lock front panel keypad
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, 'LOCK 1,000');
        end
        
        %% --- TEMPERATURE READOUTS ---
        function tempK = readTemp(obj, inputChan)
            % Read temperature in Kelvin (KRDG?)
            if nargin < 2; inputChan = obj.DefaultInput; end
            inputChan = upper(char(inputChan));
            
            if obj.IsSimulated
                tempK = obj.SimCurrentTemp + randn()*0.02;
                return;
            end
            
            tempK = str2double(writeread(obj.VisaObj, sprintf('KRDG? %s', inputChan)));
        end
        
        function tempC = readTempCelsius(obj, inputChan)
            % Read temperature in Celsius (CRDG?)
            if nargin < 2; inputChan = obj.DefaultInput; end
            inputChan = upper(char(inputChan));
            
            if obj.IsSimulated
                tempC = (obj.SimCurrentTemp - 273.15) + randn()*0.02;
                return;
            end
            
            tempC = str2double(writeread(obj.VisaObj, sprintf('CRDG? %s', inputChan)));
        end
        
        function resVal = readSensorUnits(obj, inputChan)
            % Read raw sensor units (Ohms for PT1000, Volts for Diodes)
            if nargin < 2; inputChan = obj.DefaultInput; end
            inputChan = upper(char(inputChan));
            
            if obj.IsSimulated
                resVal = 1000.0 + (obj.SimCurrentTemp - 273.15)*3.85; % Approx PT1000 ohms
                return;
            end
            
            resVal = str2double(writeread(obj.VisaObj, sprintf('SRDG? %s', inputChan)));
        end
        
        function [tempA, tempB] = readAll(obj)
            % Read both Channel A and Channel B temperatures in Kelvin
            tempA = obj.readTemp('A');
            tempB = obj.readTemp('B');
        end
        
        %% --- PT1000 / SENSOR CONFIGURATION ---
        function configurePT1000(obj, inputChan, curveNum)
            % Configure input channel for a Platinum PT1000 RTD sensor.
            if nargin < 2; inputChan = obj.DefaultInput; end
            if nargin < 3; curveNum = 7; end % Default factory PT1000 curve
            
            inputChan = upper(char(inputChan));
            if obj.IsSimulated; return; end
            
            % INTYPE: Sensor Type 3 = Platinum RTD, Autorange = 1, Compensation = 1 (current reversal), Units = 1 (K)
            writeline(obj.VisaObj, sprintf('INTYPE %s,3,1,0,1,1', inputChan));
            
            % Assign temperature curve
            if curveNum > 0
                writeline(obj.VisaObj, sprintf('INCRV %s,%d', inputChan, curveNum));
            end
        end
        
        function setCustomCurve(obj, inputChan, curveNumber)
            if nargin < 2; inputChan = obj.DefaultInput; end
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('INCRV %s,%d', upper(char(inputChan)), curveNumber));
        end
        
        %% --- SETPOINT & RAMP CONTROL ---
        function setSetpoint(obj, targetTempK, loopNum)
            if nargin < 3; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated
                obj.SimSetpoint = targetTempK;
                return;
            end
            writeline(obj.VisaObj, sprintf('SETP %d,%g', loopNum, targetTempK));
        end
        
        function spVal = getSetpoint(obj, loopNum)
            if nargin < 2; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated; spVal = obj.SimSetpoint; return; end
            spVal = str2double(writeread(obj.VisaObj, sprintf('SETP? %d', loopNum)));
        end
        
        function setRamp(obj, enable, rateKPerMin, loopNum)
            if nargin < 4; loopNum = obj.DefaultLoop; end
            enableState = double(enable);
            if obj.IsSimulated
                obj.SimRamping = (enableState == 1);
                obj.SimRampRate = rateKPerMin;
                return;
            end
            writeline(obj.VisaObj, sprintf('RAMP %d,%d,%g', loopNum, enableState, rateKPerMin));
        end
        
        function [isEnabled, rateVal] = getRamp(obj, loopNum)
            if nargin < 2; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated
                isEnabled = obj.SimRamping;
                rateVal = obj.SimRampRate;
                return;
            end
            resp = strtrim(writeread(obj.VisaObj, sprintf('RAMP? %d', loopNum)));
            tokens = sscanf(resp, '%d,%f');
            isEnabled = logical(tokens(1));
            rateVal = tokens(2);
        end
        
        function isRampActive = isRamping(obj, loopNum)
            if nargin < 2; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated; isRampActive = obj.SimRamping; return; end
            statusVal = str2double(writeread(obj.VisaObj, sprintf('RAMPST? %d', loopNum)));
            isRampActive = (statusVal == 1);
        end
        
        %% --- HEATER & PID CONTROL ---
        function setHeaterRange(obj, rangeVal, loopNum)
            if nargin < 3; loopNum = obj.DefaultLoop; end
            if ischar(rangeVal) || isstring(rangeVal)
                switch upper(char(rangeVal))
                    case 'OFF';  rangeVal = 0;
                    case 'LOW';  rangeVal = 1;
                    case {'MED', 'MEDIUM'}; rangeVal = 2;
                    case 'HIGH'; rangeVal = 3;
                    case 'ON';   rangeVal = 1;
                    otherwise;   error('Invalid range string. Use OFF, LOW, MED, or HIGH.');
                end
            end
            
            if obj.IsSimulated
                obj.SimHeaterRange = rangeVal;
                return;
            end
            writeline(obj.VisaObj, sprintf('RANGE %d,%d', loopNum, rangeVal));
        end
        
        function rangeVal = getHeaterRange(obj, loopNum)
            if nargin < 2; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated; rangeVal = obj.SimHeaterRange; return; end
            rangeVal = str2double(writeread(obj.VisaObj, sprintf('RANGE? %d', loopNum)));
        end
        
        function htrPercent = getHeaterOutput(obj, outputNum)
            if nargin < 2; outputNum = 1; end
            if obj.IsSimulated; htrPercent = 25.4 + randn()*0.5; return; end
            htrPercent = str2double(writeread(obj.VisaObj, sprintf('HTR? %d', outputNum)));
        end
        
        function setPID(obj, P, I, D, loopNum)
            if nargin < 5; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('PID %d,%g,%g,%g', loopNum, P, I, D));
        end
        
        function [P, I, D] = getPID(obj, loopNum)
            if nargin < 2; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated; P = 50; I = 20; D = 0; return; end
            resp = strtrim(writeread(obj.VisaObj, sprintf('PID? %d', loopNum)));
            tokens = sscanf(resp, '%f,%f,%f');
            P = tokens(1); I = tokens(2); D = tokens(3);
        end
        
        function configureLoopMode(obj, loopNum, modeType, inputChan)
            if nargin < 4; inputChan = obj.DefaultInput; end
            if ischar(inputChan) || isstring(inputChan)
                if strcmpi(inputChan, 'A'); inCode = 1; else; inCode = 2; end
            else
                inCode = inputChan;
            end
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('OUTMODE %d,%d,%d,0', loopNum, modeType, inCode));
        end
        
        function setManualOutput(obj, powerPercent, loopNum)
            if nargin < 3; loopNum = obj.DefaultLoop; end
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('MOUT %d,%g', loopNum, powerPercent));
        end
    end
end