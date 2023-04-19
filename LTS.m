classdef LTS < handle
    % LTS class to control Thorlabs long travel stage 
    % using the Thorlabs .Net DLLs
    %
    % Example:
    % SN = LTS.listdevices;     % list connected devices
    % lts_1 = LTS;              % create a LTS object  
    % connect(lts_1, SN{1})     % connect the first device in the list of devices
    % home(lts_1)               % home the lts
    % movetopos(lts_1,10)       % move the lts to position 10mm
    % movetopos(lts_1,30,40)    % move the lts to position 30mm with 40mm/s
    % disconnect(lts1)          % disconnect device
    % 
    % by Joshua Köster 
    %
    % modified version of: 
    % https://de.mathworks.com/matlabcentral/fileexchange/66497-driver-for-thorlabs-motorized-stages
    % by Julian Fells
    % 
    % note Thorlabs's Kinesis Software is required:
    % https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control&viewtab=0

    properties (Constant, Hidden)
        % path to DLL files (edit as appropriate)
       MOTORPATHDEFAULT='C:\Program Files\Thorlabs\Kinesis\'

       % DLL files to be loaded
       DEVICEMANAGERDLL='Thorlabs.MotionControl.DeviceManagerCLI.dll';
       GENERICMOTORDLL='Thorlabs.MotionControl.GenericMotorCLI.dll';          
       INTEGSTEPDLL='Thorlabs.MotionControl.IntegratedStepperMotorsCLI.dll' 

       % Default intitial parameters 
       DEFAULTVEL=20;           % Default velocity in mm/s
       DEFAULTACC=20;           % Default acceleration in mm/s^2
       TPOLLING=250;            % Default polling time
       TIMEOUTSETTINGS=7000;    % Default timeout time for settings change
       TIMEOUTMOVE=100000;      % Default time out time for motor move
    end
    properties 
       % These properties are within Matlab wrapper 
       isconnected=false;           % Flag set if device connected
       serialnumber;                % Device serial number
       controllername;              % Controller Name
       controllerdescription        % Controller Description
       stagename;                   % Stage Name
       position;                    % Position
       acceleration;                % Acceleration
       maxvelocity;                 % Maximum velocity limit
       minvelocity;                 % Minimum velocity limit
    end
    properties (Hidden)
       % These are properties within the .NET environment. 
       deviceNET;                   % Device object within .NET
       motorSettingsNET;            % motorSettings within .NET
       currentDeviceSettingsNET;    % currentDeviceSetings within .NET
       deviceInfoNET;               % deviceInfo within .NET
    end

    methods
        function h=LTS()  
            % constructor
            LTS.loaddlls; % load DLLs (if not already loaded)
        end

        function connect(h,serialNo)  
            % 'connect()' initializes the LTS based on the serial number and starts polling
            %
            % example:
            % lts = LTS;        % create a object 'lts' of class 'LTS'
            % connect(lts, SN)  % connect the LTS which corresponds to the
            %                   % serial number 'SN'
            %
            % to list serial number of connected devices via USB call:'LTS.listdevices'
            %
            h.listdevices();    % Use this call to build a device list in case not invoked beforehand
            if ~h.isconnected
                switch(serialNo(1:2))
                    case '45'   % Serial number corresponds to LTS150/LTS300
                        h.deviceNET=Thorlabs.MotionControl.IntegratedStepperMotorsCLI.LongTravelStage.CreateLongTravelStage(serialNo);   
                    otherwise 
                        error('stage is not a LTS');
                end    
                h.deviceNET.Connect(serialNo);          % Connect to device via .NET interface
                try
                    if ~h.deviceNET.IsSettingsInitialized() % Wait for IsSettingsInitialized via .NET interface
                        h.deviceNET.WaitForSettingsInitialized(h.TIMEOUTSETTINGS);
                    end
                    if ~h.deviceNET.IsSettingsInitialized() % cannot initialise device
                        error(['unable to initialise device ',char(serialNo)]);
                    end
                    h.motorSettingsNET = h.deviceNET.LoadMotorConfiguration(serialNo);  % get motorSettings via .NET interface
                    h.motorSettingsNET.UpdateCurrentConfiguration();    % update the RealToDeviceUnit converter
                    MotorDeviceSettings = h.deviceNET.MotorDeviceSettings;
                    h.deviceNET.SetSettings(MotorDeviceSettings, true, false);
                    h.deviceInfoNET=h.deviceNET.GetDeviceInfo(); 
                    h.deviceNET.StartPolling(h.TPOLLING);   % start polling via .NET interface
                catch % cannot initialise device
                    error(['unable to initialise device ',char(serialNo)]);
                end
            else % Device is already connected
                error('device is already connected.')
            end
            updatestatus(h);   % Update status variables from device
        end

        function disconnect(h) 
            % 'disconnect()' disconnects the LTS and stops polling
            %
            % example:
            % disconnect(lts)   % disconnect the object 'lts'
            %
            h.isconnected=h.deviceNET.IsConnected(); % Update isconnected flag via .NET interface
            if h.isconnected
                try
                    h.deviceNET.StopPolling();  % stop polling device via .NET interface
                    h.deviceNET.Disconnect();   % disconnect device via .NET interface
                catch
                    error(['unable to disconnect device',h.serialnumber]);
                end
                h.isconnected=false;  % update internal flag to say device is no longer connected
            else % Cannot disconnect because device not connected
                error('device not connected.')
            end    
        end

        function home(h)              
            % 'home()' homes the LTS (must be done before any movement with the LTS)
            % 
            % example
            % home(lts) % homes the object 'lts'
            %
            msg = 'homing LTS';
            disp(msg);
            workDone=h.deviceNET.InitializeWaitHandler();     % Initialise Waithandler for timeout
            h.deviceNET.Home(workDone);                       % Home devce via .NET interface
            h.deviceNET.Wait(h.TIMEOUTMOVE);                  % Wait for move to finish
            updatestatus(h);            % Update status variables from device
            disp(repmat(char(8), 1, length(msg)+2));
            disp('LTS homed');
        end

        function movetopos(h,varargin)   
            % 'movetopos()' moves the LTS to a specific absolute position 
            % optional with a specific velocity and accerleration
            % 
            % examples
            %
            % movetopos(lts,5)      % move the object 'lts' to position 5mm
            %
            % movetopos(lts,5,10)   % move the object 'lts' to position 5mm
            %                       % with velocity 10mm/s 
            %
            % movetopos(lts,5,10,30)% move the object 'lts' to position 5mm
            %                       % with velocity 10mm/s and acceleration
            %                       % 30mm/s^2
            switch(nargin)
                case 1
                    disp(['current position of LTS is ', num2str(h.position), 'mm'])
                case 2  % first parameter corresponds to aimed position
                    try
                        msg = ['move LTS to ', num2str(varargin{1}), 'mm'];
                        disp(msg)
                        workDone=h.deviceNET.InitializeWaitHandler(); % Initialise Waithandler for timeout
                        h.deviceNET.MoveTo(varargin{1}, workDone);       % Move devce to position via .NET interface
                        h.deviceNET.Wait(h.TIMEOUTMOVE);              % Wait for move to finish
                        updatestatus(h);        % Update status variables from device
                        disp(repmat(char(8), 1, length(msg)+2));
                        disp(['LTS moved to ', num2str(varargin{1}), 'mm'])
                    catch % Device faile to move
                        error(['unable to move LTS ',h.serialnumber,' to ',num2str(varargin{1})]);
                    end
                case 3  % If two parameter, set the velocity  
                    setvelocity(h, varargin{2})
                    movetopos(h,varargin{1})
                case 4  % if three parameter set the velocity and acceleration
                    setvelocity(h, varargin{2}, varargin{3})
                    movetopos(h,varargin{1})
            end
        end

        function setvelocity(h, varargin)  
            % 'setvelocity()' sets velocity and optional acceleration
            % parameters of the LTS
            %
            % examples
            %
            % setvelocity(lts,30)   % sets the velocity ob the object 'lts'
            %                       % to 30 mm/s
            %
            % setvelocity(lts,30,40)% sets the velocity ob the object 'lts'
            %                       % to 30 mm/s and the acceleration to
            %                       % 40 mm/s^2
            %
            velpars=h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
            switch(nargin)
                case 1  % If no parameters specified, set both velocity and acceleration to default values
                    velpars.MaxVelocity=h.DEFAULTVEL;
                    velpars.Acceleration=h.DEFAULTACC;
                case 2  % If just one parameter, set the velocity  
                    velpars.MaxVelocity=varargin{1};
                case 3  % If two parameters, set both velocitu and acceleration
                    velpars.MaxVelocity=varargin{1};  % Set velocity parameter via .NET interface
                    velpars.Acceleration=varargin{2}; % Set acceleration parameter via .NET interface
            end
            if System.Decimal.ToDouble(velpars.MaxVelocity)>50  % Allow velocity to be outside range, but issue warning
                warning('velocity >50 mm/s outside specification')
            end
            if System.Decimal.ToDouble(velpars.Acceleration)>50 % Allow acceleration to be outside range, but issue warning
                warning('acceleration >50 mm/s^2 outside specification')
            end
            h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
            updatestatus(h);        % Update status variables from device
        end

        function updatestatus(h) 
            % 'updatestatus()' updates recorded device parameters in MATLAB by reading them from the lts

            h.isconnected=boolean(h.deviceNET.IsConnected());   % update isconncted flag
            h.serialnumber=char(h.deviceNET.DeviceID);          % update serial number
            h.controllername=char(h.deviceInfoNET.Name);        % update controleller name          
            h.controllerdescription=char(h.deviceInfoNET.Description);  % update controller description
            h.stagename=char(h.motorSettingsNET.DeviceSettingsName);    % update stagename
            velocityparams=h.deviceNET.GetVelocityParams();             % update velocity parameter
            h.acceleration=System.Decimal.ToDouble(velocityparams.Acceleration); % update acceleration parameter
            h.maxvelocity=System.Decimal.ToDouble(velocityparams.MaxVelocity);   % update max velocit parameter
            h.minvelocity=System.Decimal.ToDouble(velocityparams.MinVelocity);   % update Min velocity parameter
            h.position=System.Decimal.ToDouble(h.deviceNET.Position);   % Read current device position
        end
        
    end

    methods (Static)
        function serialNumbers=listdevices()  
            % 'listdevices()' lists serial number(s) of connected device(s)
            % 
            % example:
            % SN = LTS.listdevices;
            motor.loaddlls; % Load DLLs
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.BuildDeviceList();  % build device list
            serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList(); % get device list
            serialNumbers=cell(ToArray(serialNumbersNet)); % convert serial numbers to cell array
        end
        function loaddlls() % load DLLs
            if ~exist(motor.DEVICEMANAGERCLASSNAME,'class')
                try   % load in DLLs if not already loaded
                    NET.addAssembly([motor.MOTORPATHDEFAULT,motor.DEVICEMANAGERDLL]);
                    NET.addAssembly([motor.MOTORPATHDEFAULT,motor.GENERICMOTORDLL]);
                    NET.addAssembly([motor.MOTORPATHDEFAULT,motor.INTEGSTEPDLL]); 
                catch % DLLs did not load
                    error('unable to load .NET assemblies')
                end
            end    
        end 
    end
end