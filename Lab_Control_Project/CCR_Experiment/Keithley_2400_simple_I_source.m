    close all;
    imaqreset;
    instrreset; 

    import CAM.* 
    import Keithley.*

    gpib_board = 0;       % Your NI-GPIB Board Index (usually 0)
    gpib_address = 23;    % Your Keithley 2400 GPIB address
    smu = Keithley.Keithley_2400_init(gpib_board, gpib_address);        
    % 2. Set to Voltage Source mode
    Keithley.Keithley_2400_set_I_source(smu);        
    % Turn on the output

    Keithley.Keithley_2400_set_I(smu, 0.004);
    Keithley.Keithley_2400_enable(smu);

    [v_measured,i_measured,r_measured] = Keithley.Keithley_2400_read(smu);
    fprintf('V: %.3f I: %.6e R: %.6e\n', v_measured, i_measured, r_measured);
   
    Keithley.Keithley_2400_disable(smu);