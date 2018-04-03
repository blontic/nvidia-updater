# nvidia-updater.ps1 #

This is a unnecessarily over complicated script based off https://github.com/lord-carlos/nvidia-update

This script will do the following;  

1. Check the nVidia site for the latest driver version  
1. Check the locally installed driver version  
1. If running the latest driver already, start Steam  
1. Else if not running latest driver;  
    1. Check grace period has passed  
    1. Download the latest driver  
    1. Disable Windows Update  
    1. Install 7zip if it's missing (via Chocolatey)  
    1. Install only the following components from the downloaded driver;  
        * Graphics driver  
        * PhysX driver  
    1. Cleanup downloaded files and unzipped workspace  
    1. Enable Windows Update  
    1. Start Steam  

### 1. Set the following variables to your perference ###

```
$steamApp = "E:\Steam\Steam.exe"         # Location of your Steam application
$cleanInstall = $false                   # Do you want to run a clean installation of the driver?
$pauseOnError = $true                    # Do you want to pause the script on an error?
$driverGracePeriod = 10                  # How many days grace period before installing the new driver
```

### 2. Create a Windows Scheduled Task to run the script at each logon ###

Run the following command to create a Windows Schedule Task that runs the script on every logon. Change the location in the first line to where this script will run from.
```
$SchTaskAction = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass C:\nvidia-updater.ps1"
$SchTaskPrincipal = New-ScheduledTaskPrincipal -RunLevel Highest -UserId $($env:USERNAME)
$SchTaskTrigger = New-ScheduledTaskTrigger -AtLogon -User $($env:USERNAME)
Register-ScheduledTask -Action $SchTaskAction -Trigger $SchTaskTrigger -TaskName "Run-nVidia-Updater-Script" -Principal $SchTaskPrincipal -Description "Run script at logon to check and install nVidia driver updates"
```