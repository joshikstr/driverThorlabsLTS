# driverThorlabsLTS
control Thorlabs long travel stages (LTS) via MATLAB by using the Thorlabs .Net DLLs from Kinesis Software

example:
% list devices
a = LTS.listdevices;
% create LTS object
lts_1 = LTS;
% connect first device in list of devices
connect(lts_1,a{1})
% home the lts
home(lts_1)
% move the lts to the position 50 mm
movetopos(lts_1,50)
% disconnect the lts
disconnect(lts_1)

(more methods to come)

note Thorlabs's Kinesis Software is required: https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control&viewtab=0
