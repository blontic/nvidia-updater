<#
    DESCRIPTION:
    a. Check the nVidia site for the latest driver version
    b. Check the locally installed driver version
    - If running the latest driver already, start Steam
    - Else if not running latest driver;
        c. Check grace period has passed
        d. Download the latest driver
        e. Disable Windows Update
        f. Install 7zip if it's missing (via Chocolatey)
        g. Install only the following components from the downloaded driver;
            i) Graphics driver
            ii) PhysX driver
        h. Cleanup downloaded files and unzipped workspace
        i. Enable Windows Update
        j. Start Steam

    SETUP:
    1. Run the following command to create a Windows Schedule Task that runs the script on every logon. Change the location in the first line to where this script will run from.

        $SchTaskAction = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass C:\scripts\nvidia-updater.ps1"
        $SchTaskPrincipal = New-ScheduledTaskPrincipal -RunLevel Highest -UserId $($env:USERNAME)
        $SchTaskTrigger = New-ScheduledTaskTrigger -AtLogon -User $($env:USERNAME)
        Register-ScheduledTask -Action $SchTaskAction -Trigger $SchTaskTrigger -TaskName "Run-nVidia-Updater-Script" -Principal $SchTaskPrincipal -Description "Run script at logon to check and install nVidia driver updates"

    2. Enter you Steam.exe location at $steamApp
#>

$steamApp = "C:\Program Files (x86)\Steam\Steam.exe"         # Location of your Steam application
$driverGracePeriod = 10                                      # How many days grace period before installing the new driver
$cleanInstall = $false                                       # Do you want to run a clean installation of the driver?
$pauseOnError = $false                                        # Do you want to pause the script on an error?

function WriteError ($errorMsg) {
    Write-Host @textColorError "Error: $errorMsg"
    if ($pauseOnError) {
        Write-Host ""
        pause
    }
    exit
}

function StartSteam {
    Write-Host @textColor1 "Starting Steam"
    try {
        Start-Process $steamApp
        Write-Host @textColor2 "Done"
    }
    catch {
        $err = $error[0]
        WriteError $err 
    }
    sleep 4
    exit
}

function CheckIsElevated {
    [Security.Principal.WindowsPrincipal] $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function GetFile ($url, $targetFile) {
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000) #15 second timeout
    $response = $request.GetResponse()

    $totalLength = [System.Math]::Floor($response.get_ContentLength() / 1024)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
    $buffer = new-object byte[] 10KB
    $count = $responseStream.Read($buffer, 0, $buffer.length)
    $downloadedBytes = $count

    while ($count -gt 0) {
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer, 0, $buffer.length)
        $downloadedBytes = $downloadedBytes + $count
        Write-Progress -activity "Downloading file '$($url.split('/') | Select-Object -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes / 1024)) / $totalLength) * 100)
    }

    Write-Progress -activity "Finished downloading file '$($url.split('/') | Select-Object -Last 1)'"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

function SetWindowsUpdateService ($state) {
    if ($state -eq "Disable") {
        $processState = "Stopped"
        $serviceState = "Disabled"
        $cmdState = "Stop"
    }
    elseif ($state -eq "Enable") {
        $processState = "Running"
        $serviceState = "Automatic"
        $cmdState = "Start"
    }
    try {
        Write-Host @textColor1 "$state Windows Update"
        Set-Service wuauserv -StartupType $serviceState 
        While ((Get-Service | Where-Object {$_.Name -eq "wuauserv"}).Status -ne $processState) {
            Invoke-Expression "${cmdState}-Service wuauserv"
        }
        Write-Host @textColor2 "Done"
    }
    catch {
        $err = $error[0]
        WriteError $err 
    }
}

function Get7zip {
    try {
        Write-Host @textColor1 "Checking if 7zip is installed"
        Start-Process 7z.exe
        Write-Host @textColor2 "Done"
    }
    catch {
        try {
            Write-Host @textColor1 "Checking if Chocolatey is installed"
            Start-Process choco.exe
            Write-Host @textColor2 "Done"
        }
        catch {
            Write-Host @textColor2 "Installing Chocolatey"
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
            Write-Host @textColor2 "Done"
        }
        Write-Host @textColor2 "Installing 7zip"
        choco.exe install 7zip -y
        Write-Host @textColor2 "Done"
    }
}

function CompareDriverVersions {
    try {
        Write-Host @textColor1 "Checking web for latest driver"
        $r = Invoke-WebRequest -Uri 'https://www.nvidia.com/Download/processFind.aspx?psid=101&pfid=816&osid=57&lid=1&whql=1&lang=en-us&ctk=0' -Method GET
        $version = $r.parsedhtml.GetElementsByClassName("gridItem")[2].innerText
        [datetime]$driverDate = $r.parsedhtml.GetElementsByClassName("gridItem")[3].innerText
        Write-Host @textColor2 "Found driver $version"

        Write-Host @textColor1 "Checking locally installed driver"
        $installed_version = (Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like "*nvidia*" -and $_.devicename -notlike "*audio*"}).DriverVersion.SubString(7).Remove(1, 1).Insert(3, ".")
        Write-Host @textColor2 "Found driver $installed_version"

        if ($version -eq $installed_version) {
            Write-Host @textColor1 "Latest driver already installed. No update required"
            StartSteam
        }
        else {
            Write-Host @textColor1 "Update available"
            if (((Get-Date) - $driverDate).Days -gt $driverGracePeriod) {
                GetDriver $version
            }
            else {
                $driverGracePeriodTimeLeft = $driverGracePeriod - ((Get-Date) - $driverDate).Days
                Write-Host @textColor2 "Driver grace period of $driverGracePeriod days has not been met. Postponing update for $driverGracePeriodTimeLeft days"
                StartSteam
            }
        }
    }
    catch {
        $err = $error[0]
        WriteError $err 
    }
}

function GetDriver ($version) {
    $dlFolder = "${env:TEMP}\nVidiaDriverTemp"
    $dlFile = "${dlFolder}\${version}.exe"
    $extractDir = "${dlFolder}\${version}"
    try {
        if (Test-Path $dlFolder) {
            Write-Host @textColor1 "Found existing driver folder, cleaning it up"
            Remove-Item "$dlFolder" -Recurse -Force
            Write-Host @textColor2 "Done"
        }
        New-Item -Path "$extractDir" -ItemType Directory | Out-Null

        $url = "https://us.download.nvidia.com/Windows/$version/$version-desktop-win10-64bit-international-whql.exe"
        Write-Host @textColor1 "Downloading driver $version from $url to $dlFile"
        GetFile $url $dlFile
        Write-Host @textColor2 "Download complete"

        SetWindowsUpdateService Disable
        Get7zip

        Write-Host @textColor1 "Extracting files"
        $args = "x -bso0 -bsp1 $dlFile Display.Driver Display.Optimus PhysX NVI2 EULA.txt ListDevices.txt setup.cfg setup.exe -o$extractDir"
        Start-Process 7z.exe -workingdirectory ${env:TEMP} -NoNewWindow -ArgumentList $args -wait
        Write-Host @textColor2 "Done"

        Write-Host @textColor1 "Installing driver $version"
        $install_args = "-passive -noreboot -noeula"
        if ($cleanInstall) {
            $install_args = $install_args + " -clean"
        }
        Start-Process -FilePath "$extractDir\setup.exe" -ArgumentList $install_args -wait
        Write-Host @textColor2 "Done"

        Write-Host @textColor1 "Cleaning up driver folder $dlFolder"
        Remove-Item "$dlFolder" -Recurse -Force
        Write-Host @textColor2 "Done"

        SetWindowsUpdateService Enable
        StartSteam
    }
    catch {
        $err = $error[0]
        WriteError $err 
    }
}

$ErrorActionPreference = "Stop"
$err = $null
$textColor1 = @{ForegroundColor = "Green"; BackgroundColor = "Black"}
$textColor2 = @{ForegroundColor = "Gray"; BackgroundColor = "Black"}
$textColorError = @{ForegroundColor = "Red"; BackgroundColor = "Black"}
$textColorMenu = @{ForegroundColor = "White"; BackgroundColor = "Black"}

Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host @textColorMenu "//////////////////////////////////////////////////////"
Write-Host @textColorMenu "//            nVidia Driver Updater                 //"
Write-Host @textColorMenu "//////////////////////////////////////////////////////"
Write-Host ""

if (CheckIsElevated) {
    CompareDriverVersions
}
else {
    WriteError "This script must be run from an elevated shell"
}