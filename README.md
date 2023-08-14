# driverThorlabsLTS
control Thorlabs long travel stages (LTS) via MATLAB by using the Thorlabs .Net DLLs from Kinesis Software

simple example:

```matlab
SN = LTS.listdevices;    % list connected devices <br>
lts = LTS;               % create a LTS object  <br>
lts.connect(SN{1})       % connect the first device in the list of devices <br>
lts.home                 % home the lts <br>
lts.movetopos(45)        % move the lts to position 45 mm <br>
lts.movetopos(30,40)     % move the lts to position 30mm with 40mm/s <br>
lts.disconnect           % disconnect device
```

note Thorlabs's Kinesis Software is required: https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control&viewtab=0
