# driverThorlabsLTS
control Thorlabs long travel stages (LTS) via MATLAB by using the Thorlabs .Net DLLs from Kinesis Software

simple example:<br>
SN = LTS.listdevices;     % list connected devices <br>
lts_1 = LTS;              % create a LTS object  <br>
connect(lts_1, SN{1})     % connect the first device in the list of devices <br>
home(lts_1)               % home the lts <br>
movetopos(lts_1,45)       % move the lts to position 45 mm <br>
movetopos(lts_1,30,40)    % move the lts to position 30mm with 40mm/s <br>
disconnect(lts1)          % disconnect device


note Thorlabs's Kinesis Software is required: https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control&viewtab=0
