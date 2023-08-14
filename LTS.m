classdef LTS < handle
    % LTS class to control Thorlabs long travel stage 
    % using the Thorlabs .Net DLLs
    %
    % Example:
    % SN = LTS.listdevices;     % list connected devices
    % lts = LTS;                % create a LTS object  
    % lts.connect(SN{1})        % connect the first device in the list of devices
    % lts.home                  % home the lts
    % lts.movetopos(10)         % move the lts to position 10mm
    % lts.movetopos(30,40)      % move the lts to position 30mm with 40mm/s
    % lts.disconnect            % disconnect device
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
       DEVICEMANAGERCLASSNAME='Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI'
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

        function connect(self,serialNo)  
            % initialize and enable the LTS based on the serial number and start polling
            %
            % example:
            % lts = LTS;        % create a object 'lts' of class 'LTS'
            % lts.connect(SN)   % connect the LTS which corresponds to the
            %                   % serial number 'SN'
            %
            % to list serial number of connected devices via USB call:'LTS.listdevices'
            %
            self.listdevices();    % Use this call to build a device list in case not invoked beforehand
            if ~self.isconnected
                switch(serialNo(1:2))
                    case '45'   % Serial number corresponds to LTS150/LTS300
                        self.deviceNET=Thorlabs.MotionControl.IntegratedStepperMotorsCLI.LongTravelStage.CreateLongTravelStage(serialNo);   
                    otherwise 
                        error('stage is not a LTS');
                end    
                self.deviceNET.Connect(serialNo);          % Connect to device via .NET interface
                try
                    if ~self.deviceNET.IsSettingsInitialized() % Wait for IsSettingsInitialized via .NET interface
                        self.deviceNET.WaitForSettingsInitialized(self.TIMEOUTSETTINGS);
                    end
                    if ~self.deviceNET.IsSettingsInitialized() % cannot initialise device
                        error(['unable to initialise device ',char(serialNo)]);
                    end
                    self.motorSettingsNET = self.deviceNET.LoadMotorConfiguration(serialNo);  % get motorSettings via .NET interface
                    self.motorSettingsNET.UpdateCurrentConfiguration();    % update the RealToDeviceUnit converter
                    MotorDeviceSettings = self.deviceNET.MotorDeviceSettings;
                    self.deviceNET.SetSettings(MotorDeviceSettings, true, false);
                    self.deviceInfoNET=self.deviceNET.GetDeviceInfo(); 
                    self.deviceNET.StartPolling(self.TPOLLING);   % start polling via .NET interface
                catch % cannot initialise device
                    error(['unable to initialise device ',char(serialNo)]);
                end
            else % Device is already connected
                error('device is already connected.')
            end
            self.deviceNET.DisableDevice;  % bigfix often init device not enabled 
            self.deviceNET.EnableDevice;
            updatestatus(self);   % Update status variables from device
        end

        function disconnect(self) 
            % disconnect the LTS and stop polling
            %
            % example:
            % lts.disconnect   % disconnect the object 'lts'
            %
            self.isconnected=self.deviceNET.IsConnected(); % Update isconnected flag via .NET interface
            if self.isconnected
                try
                    self.deviceNET.StopPolling();  % stop polling device via .NET interface
                    self.deviceNET.Disconnect();   % disconnect device via .NET interface
                catch
                    error(['unable to disconnect device',self.serialnumber]);
                end
                self.isconnected=false;  % update internal flag to say device is no longer connected
            else % Cannot disconnect because device not connected
                error('device not connected.')
            end    
        end

        function home(self)              
            % home the LTS (must be done before any movement with the LTS)
            % 
            % example
            % lts.home % homes the object 'lts'
            %
            msg = 'homing LTS';
            disp(msg);
            workDone=self.deviceNET.InitializeWaitHandler();     % Initialise Waithandler for timeout
            self.deviceNET.Home(workDone);                       % Home devce via .NET interface
            self.deviceNET.Wait(self.TIMEOUTMOVE);                  % Wait for move to finish
            updatestatus(self);            % Update status variables from device
            disp(repmat(char(8), 1, length(msg)+2));
            disp('LTS homed');
        end

        function movetopos(self,varargin)   
            % move the LTS to a specific absolute position 
            % optional with a specific velocity and accerleration
            % 
            % examples
            %
            % lts.movetopos(5)      % move the object 'lts' to position 5mm
            %
            % lts.movetopos(5,10)   % move the object 'lts' to position 5mm
            %                       % with velocity 10mm/s 
            %
            % lts.movetopos(5,10,30)% move the object 'lts' to position 5mm
            %                       % with velocity 10mm/s and acceleration
            %                       % 30mm/s^2
            switch(nargin)
                case 1
                    disp(['current position of LTS is ', num2str(self.position), 'mm'])
                case 2  % first parameter corresponds to aimed position
                    try
                        msg = ['move LTS to ', num2str(varargin{1}), 'mm'];
                        disp(msg)
                        workDone=self.deviceNET.InitializeWaitHandler(); % Initialise Waithandler for timeout
                        self.deviceNET.MoveTo(varargin{1}, workDone);       % Move devce to position via .NET interface
                        self.deviceNET.Wait(self.TIMEOUTMOVE);              % Wait for move to finish
                        updatestatus(self);        % Update status variables from device
                        disp(repmat(char(8), 1, length(msg)+2));
                        disp(['LTS moved to ', num2str(varargin{1}), 'mm'])
                    catch % Device faile to move
                        error(['unable to move LTS ',self.serialnumber,' to ',num2str(varargin{1})]);
                    end
                case 3  % If two parameter, set the velocity  
                    setvelocity(self, varargin{2})
                    movetopos(self,varargin{1})
                case 4  % if three parameter set the velocity and acceleration
                    setvelocity(self, varargin{2}, varargin{3})
                    movetopos(self,varargin{1})
            end
        end

        function setvelocity(self, varargin)  
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
            velpars=self.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
            switch(nargin)
                case 1  % If no parameters specified, set both velocity and acceleration to default values
                    velpars.MaxVelocity=self.DEFAULTVEL;
                    velpars.Acceleration=self.DEFAULTACC;
                case 2  % If just one parameter, set the velocity
                    if varargin{1} > 50
                        warning('velocity >50 mm/s outside specification')
                        varargin{1} = 50;
                    end
                    velpars.MaxVelocity=varargin{1};
                case 3  % If two parameters, set both velocitu and acceleration
                    if varargin{1} > 50
                        warning('velocity >50 mm/s outside specification')
                        varargin{1} = 50;
                    end
                    if varargin{2} > 50
                        warning('acceleration >50 mm/s^2 outside specification')
                        varargin{2} = 50;
                    end
                    velpars.MaxVelocity=varargin{1};  % Set velocity parameter via .NET interface
                    velpars.Acceleration=varargin{2}; % Set acceleration parameter via .NET interface
            end
            self.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
            updatestatus(self);        % Update status variables from device
        end

        function runsequence(self,sequence)
            % run a sequence of positions (opt. with velocity
            % and acceleration) given by a cell array
            %
            % example:
            % sequence = cell(3,1);         % create empty cell array
            % sequence{1} = 50;             % 1st position 50mm
            % sequence{2} = [70, 5]         % 2st position 70mm and 5mm/s
            % sequence{3} = [150, 30, 40]   % 3st position 150mm, 30mm/s
            %                               % and 40mm/s^2 
            % lts.runsequence(sequence)     % run sequence
            %
            if ~isa(sequence,'cell')
                error(['expected datatype is cell for sequence and not ', class(sequence)]);
            end
            
            for pstamp = 1:length(sequence)
                switch length(sequence{pstamp}) 
                    case 1  % only position given
                        movetopos(self,sequence{pstamp})   
                    case 2  % position and velocity given
                        movetopos(self,sequence{pstamp}(1),sequence{pstamp}(2))
                    case 3  % position, velocity and acceleration given
                        movetopos(self,sequence{pstamp}(1),sequence{pstamp}(2),sequence{pstamp}(3))
                end
                updatestatus(self) % update status variables from devic
            end
        end

        function updatestatus(self) 
            % update recorded device parameters in MATLAB by reading them from the lts

            self.isconnected=boolean(self.deviceNET.IsConnected());   % update isconncted flag
            self.serialnumber=char(self.deviceNET.DeviceID);          % update serial number
            self.controllername=char(self.deviceInfoNET.Name);        % update controleller name          
            self.controllerdescription=char(self.deviceInfoNET.Description);  % update controller description
            self.stagename=char(self.motorSettingsNET.DeviceSettingsName);    % update stagename
            velocityparams=self.deviceNET.GetVelocityParams();             % update velocity parameter
            self.acceleration=System.Decimal.ToDouble(velocityparams.Acceleration); % update acceleration parameter
            self.maxvelocity=System.Decimal.ToDouble(velocityparams.MaxVelocity);   % update max velocit parameter
            self.minvelocity=System.Decimal.ToDouble(velocityparams.MinVelocity);   % update Min velocity parameter
            self.position=System.Decimal.ToDouble(self.deviceNET.Position);   % Read current device position
        end

        function delete(self)
            % disconnects lts by using MATLAB fcn 'clear'

            if self.isconnected
                 self.disconnect
            end
            disp('lts destroyed')
        end
        
    end

    methods (Static)
        function serialNumbers=listdevices()  
            % list serial number(s) of connected device(s)
            % 
            % example:
            % SN = LTS.listdevices;
            LTS.loaddlls; % Load DLLs
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.BuildDeviceList();  % build device list
            serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList(); % get device list
            serialNumbers=cell(ToArray(serialNumbersNet)); % convert serial numbers to cell array
        end
        function loaddlls() % load DLLs
            if ~exist(LTS.DEVICEMANAGERCLASSNAME,'class')
                try   % load in DLLs if not already loaded
                    NET.addAssembly([LTS.MOTORPATHDEFAULT,LTS.DEVICEMANAGERDLL]);
                    NET.addAssembly([LTS.MOTORPATHDEFAULT,LTS.GENERICMOTORDLL]);
                    NET.addAssembly([LTS.MOTORPATHDEFAULT,LTS.INTEGSTEPDLL]); 
                catch % DLLs did not load
                    error('unable to load .NET assemblies')
                end
            end    
        end 
    end
end