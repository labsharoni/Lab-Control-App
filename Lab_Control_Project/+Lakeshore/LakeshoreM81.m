classdef LakeshoreM81 < handle
    % LakeshoreM81 - Object-Oriented MATLAB Wrapper for Lake Shore M81-SSM
    % Configured explicitly for systems utilizing the all-in-one SMU-10 module.
    
    properties (Access = private)
        VisaObj             
        SourceChan          
        MeasureChan         
        IsSimulated = false 
        ActiveExcitation = 'AC' % Memorize state for high-speed reading
    end
    
    methods
        %% Constructor: Initialize Connection
        function obj = LakeshoreM81(resourceString, sChan, mChan)
            if nargin < 2; sChan = 1; end
            if nargin < 3; mChan = 1; end
            
            obj.SourceChan = sChan;
            obj.MeasureChan = mChan;
            
            if strcmpi(resourceString, 'SIM')
                obj.IsSimulated = true;
                fprintf('[SIM] M81 SMU-10 initialized in simulation mode.\n');
                return;
            end
            
            try
                obj.VisaObj = visadev(resourceString);
                if contains(upper(resourceString), 'ASRL') || contains(upper(resourceString), 'COM')
                    obj.VisaObj.BaudRate = 921600;
                    obj.VisaObj.FlowControl = 'hardware';
                end
                configureTerminator(obj.VisaObj, 'LF'); 
                idn = writeread(obj.VisaObj, '*IDN?');
                fprintf('Connected to Instrument: %s\n', idn);
            catch ME
                error('Failed to open VISA connection to Lake Shore M81. Error: %s', ME.message);
            end
        end
        
        %% Destructor: Safely turn off outputs on script exit
        function delete(obj)
            if ~obj.IsSimulated && ~isempty(obj.VisaObj)
                obj.setOutputState(false); 
                clear obj.VisaObj;
                fprintf('M81 Connection closed safely.\n');
            end
        end
        
        %% --- OUTPUT / SOURCE CONTROL ---
        function setOutputState(obj, state)
            if state; strState = 'ON'; else; strState = 'OFF'; end
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('SOURce%d:STATe %s', obj.SourceChan, strState));
        end
        
        function setSourceMode(obj, modeType, amplitude, offset, freq)
            if nargin < 4; offset = 0; end
            if nargin < 5; freq = 17.0; end
            
            sourceType = 'CURRent'; 
            if obj.IsSimulated; return; end
            
            if strcmpi(modeType, 'DC')
                writeline(obj.VisaObj, sprintf('SOURce%d:FUNCtion:SHAPe DC', obj.SourceChan));
                writeline(obj.VisaObj, sprintf('SOURce%d:%s:PEAK %g', obj.SourceChan, sourceType, amplitude));
            else 
                writeline(obj.VisaObj, sprintf('SOURce%d:FUNCtion:SHAPe SINE', obj.SourceChan));
                writeline(obj.VisaObj, sprintf('SOURce%d:FREQuency %g', obj.SourceChan, freq));
                writeline(obj.VisaObj, sprintf('SOURce%d:%s:PEAK %g', obj.SourceChan, sourceType, amplitude));
                writeline(obj.VisaObj, sprintf('SOURce%d:%s:OFFSet %g', obj.SourceChan, sourceType, offset));
            end
        end
        
        function setSourceRange(obj, rangeVal)
            sourceType = 'CURRent';
            if obj.IsSimulated; return; end
            
            if strcmpi(string(rangeVal), 'AUTO')
                writeline(obj.VisaObj, sprintf('SOURce%d:%s:RANGe:AUTO 1', obj.SourceChan, sourceType));
            else
                writeline(obj.VisaObj, sprintf('SOURce%d:%s:RANGe:AUTO 0', obj.SourceChan, sourceType));
                writeline(obj.VisaObj, sprintf('SOURce%d:%s:RANGe %g', obj.SourceChan, sourceType, rangeVal));
            end
        end
        
        %% --- INPUT / MEASUREMENT CONTROL ---
        function setMeasureMode(obj, modeType)
            if obj.IsSimulated; return; end
            
            if strcmpi(modeType, 'LOCKIN') || strcmpi(modeType, 'LIA')
                writeline(obj.VisaObj, sprintf('SENSe%d:MODE LIA', obj.MeasureChan));
                writeline(obj.VisaObj, sprintf('SENSe%d:LIA:RSOurce SOURce%d', obj.MeasureChan, obj.SourceChan));
            else
                writeline(obj.VisaObj, sprintf('SENSe%d:MODE %s', obj.MeasureChan, upper(modeType)));
            end
        end
        
        function setMeasureRange(obj, rangeVal)
            measureType = 'VOLTage';
            if obj.IsSimulated; return; end
            
            if strcmpi(string(rangeVal), 'AUTO')
                writeline(obj.VisaObj, sprintf('SENSe%d:%s:RANGe:AUTO 1', obj.MeasureChan, measureType));
            else
                writeline(obj.VisaObj, sprintf('SENSe%d:%s:RANGe:AUTO 0', obj.MeasureChan, measureType));
                writeline(obj.VisaObj, sprintf('SENSe%d:%s:RANGe %g', obj.MeasureChan, measureType, rangeVal));
            end
        end
        
        function setNPLC(obj, nplcValue)
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('SENSe%d:NPLCycles %g', obj.MeasureChan, nplcValue));
        end
        
        function setTimeConstant(obj, tcSeconds)
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('SENSe%d:LIA:TIMEconstant %g', obj.MeasureChan, tcSeconds));
        end
        
        %% --- DATA EXTRACTION GETTERS ---
        function val = readDC(obj)
            if obj.IsSimulated; val = 1.234 + randn()*0.001; return; end
            val = str2double(writeread(obj.VisaObj, sprintf('FETCh:SENSe%d:DC?', obj.MeasureChan)));
        end
        
        function [X, Y, R, Theta] = readLockIn(obj)
            if obj.IsSimulated
                X = 0.5 + randn()*0.0001; Y = 0.01 + randn()*0.0001;
                R = sqrt(X^2 + Y^2); Theta = atan2d(Y,X);
                return;
            end
            
            X = str2double(writeread(obj.VisaObj, sprintf('FETCh:SENSe%d:LIA:X?', obj.MeasureChan)));
            Y = str2double(writeread(obj.VisaObj, sprintf('FETCh:SENSe%d:LIA:Y?', obj.MeasureChan)));
            R = str2double(writeread(obj.VisaObj, sprintf('FETCh:SENSe%d:LIA:R?', obj.MeasureChan)));
            Theta = str2double(writeread(obj.VisaObj, sprintf('FETCh:SENSe%d:LIA:THETa?', obj.MeasureChan)));
        end
        
        %% --- NATIVE RESISTANCE SUBSYSTEM ---
        function configureResistanceMode(obj, wireConfig, excitationType)
            if nargin < 3; excitationType = 'DC'; end
            if obj.IsSimulated; return; end
            
            % Cache the state so readResistance doesn't have to query it slowly
            obj.ActiveExcitation = upper(excitationType);
            
            writeline(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:STATe 1', obj.MeasureChan));
            writeline(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:SOURce SOURce%d', obj.MeasureChan, obj.SourceChan));
            writeline(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:ETYPe %s', obj.MeasureChan, obj.ActiveExcitation));
            
            if strcmpi(wireConfig, '4WIRE')
                writeline(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:MODE FOURwire', obj.MeasureChan));
                try writeline(obj.VisaObj, sprintf('SOURce%d:VOLTage:SMODe REMote', obj.SourceChan)); catch; end
                try writeline(obj.VisaObj, sprintf('SENSe%d:VOLTage:SMODe REMote', obj.MeasureChan)); catch; end
                try writeline(obj.VisaObj, sprintf('SENSe%d:VOLTage:SENSE REMote', obj.MeasureChan)); catch; end
            else
                writeline(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:MODE TWOWire', obj.MeasureChan));
                try writeline(obj.VisaObj, sprintf('SOURce%d:VOLTage:SMODe LOCal', obj.SourceChan)); catch; end
                try writeline(obj.VisaObj, sprintf('SENSe%d:VOLTage:SMODe LOCal', obj.MeasureChan)); catch; end
                try writeline(obj.VisaObj, sprintf('SENSe%d:VOLTage:SENSE LOCal', obj.MeasureChan)); catch; end
            end
        end
        
        function resValue = readResistance(obj)
            if obj.IsSimulated; resValue = 42.18; return; end
            
            try
                % Blazing fast single read using the cached excitation state
                %if strcmpi(obj.ActiveExcitation, 'AC')
                %    resValue = str2double(writeread(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:INPHase?', obj.MeasureChan)));
                %else
                %    resValue = str2double(writeread(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance:DC?', obj.MeasureChan)));
                %Measuring Magnitude as a diagnostic of phase misalignment
                resValue = str2double(writeread(obj.VisaObj, sprintf('CALCulate:SENSe%d:RESistance?', obj.MeasureChan)));
                %end
            catch
                resValue = NaN;
            end
            
            if isnan(resValue) || resValue >= 9.9e37
               resValue = NaN;
            end
        end
    end
end