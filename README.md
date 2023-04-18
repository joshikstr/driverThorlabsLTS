# driverThorlabsLTS
control Thorlabs long travel stages (LTS) via MATLAB by using the Thorlabs .Net DLLs from Kinesis Software

example:
a = LTS.listdevices;  % list devices
lts_1 = LTS;          % create LTS object
connect(lts_1,a{1})   % connect first device in list of devices
home(lts_1)           % home the lts
movetopos(lts_1,50)   % move the lts to the position 50 mm
disconnect(lts_1)     % disconnect the lts

(more methods to come)

note Thorlabs's Kinesis Software is required: https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control&viewtab=0
