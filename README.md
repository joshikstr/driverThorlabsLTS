# driverThorlabsLTS
control Thorlabs long travel stages (LTS) via MATLAB by using the Thorlabs .Net DLLs from Kinesis Software

simple example:

```matlab
SN = LTS.listdevices;    % list connected devices 
lts = LTS;               % create a LTS object  
lts.connect(SN{1})       % connect the first device in the list of devices 
lts.home                 % home the lts 
lts.movetopos(45)        % move the lts to position 45 mm <br>
lts.movetopos(30,40)     % move the lts to position 30mm with 40mm/s 
lts.disconnect           % disconnect device
```

note Thorlabs's Kinesis Software is required: https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control&viewtab=0
