$Boxstarter.RebootOk=$true
$Boxstarter.NoPassword=$true
$Boxstarter.AutoLogin=$true

$checkpointPrefix = 'BoxStarter:Checkpoint:'
function Get-CheckpointName
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $CheckpointName
    )
    return "$checkpointPrefix$CheckpointName"
}

function Set-Checkpoint
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $CheckpointName,

        [Parameter(Mandatory=$true)]
        [string]
        $CheckpointValue
    )

    $key = Get-CheckpointName $CheckpointName
    [Environment]::SetEnvironmentVariable($key, $CheckpointValue, "Machine") # for reboots
	  [Environment]::SetEnvironmentVariable($key, $CheckpointValue, "Process") # for right now
}

function Get-Checkpoint
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $CheckpointName
    )

    $key = Get-CheckpointName $CheckpointName
	[Environment]::GetEnvironmentVariable($key, "Process")
}

function Clear-Checkpoints
{
    $checkpointMarkers = Get-ChildItem Env: | where { $_.name -like "$checkpointPrefix*" } | Select -ExpandProperty name
    foreach ($checkpointMarker in $checkpointMarkers) {
	    [Environment]::SetEnvironmentVariable($checkpointMarker, '', "Machine")
	    [Environment]::SetEnvironmentVariable($checkpointMarker, '', "Process")
    }
}

function Install-WindowsUpdate
{
    if (Test-Path env:\BoxStarter:SkipWindowsUpdate)
    {
        return
    }

	Enable-MicrosoftUpdate
	Install-WindowsUpdate -AcceptEula
	#if (Test-PendingReboot) { Invoke-Reboot }
}

function Install-WebPackage
{
    param(
        $packageName,
        [ValidateSet('exe', 'msi')]
        $fileType,
        $installParameters,
        $downloadFolder,
        $url,
        $filename
    )

    $done = Get-Checkpoint -CheckpointName $packageName

    if ($done) {
        Write-BoxstarterMessage "$packageName already installed"
        return
    }


    if ([String]::IsNullOrEmpty($filename))
    {
        $filename = Split-Path $url -Leaf
    }

    $fullFilename = Join-Path $downloadFolder $filename

    if (test-path $fullFilename) {
        Write-BoxstarterMessage "$fullFilename already exists"
        return
    }

    Get-ChocolateyWebFile $packageName $fullFilename $url
    Install-ChocolateyInstallPackage $packageName $fileType $installParameters $fullFilename

    Set-Checkpoint -CheckpointName $packageName -CheckpointValue 1
}

function Install-CoreApps
{
    choco install googlechrome-allusers     --limitoutput
    choco install vlc --limitoutput
    choco install notepadplusplus.install   --limitoutput
    choco install 7zip.install              --limitoutput
}

function Install-Home
{
    choco install spotify --limitoutput
    choco install steam --limitoutput
    choco install speccy --limitoutput
    choco install cpu-z --limitoutput
    choco install handbrake --limitoutput
    choco install hexchat --limitoutput
}

function Install-Dev
{
    choco install git.install -params '"/GitAndUnixToolsOnPath"' --limitoutput
    choco install sourcetree 	            --limitoutput
    choco install nodejs                    --limitoutput
    choco install python		    --limitoutput
    choco install jdk8		        	    --limitoutput
    choco install putty               	    --limitoutput
    choco install fiddler4               	--limitoutput
    choco install winscp              	    --limitoutput
    choco install diffmerge				    --limitoutput
    choco install atom                      --limitoutput

    Write-BoxstarterMessage "Installing VS 2015 Community"
    # install visual studio 2015 community and extensions
    choco install visualstudio2015community #--limitoutput # -packageParameters "--AdminFile https://raw.githubusercontent.com/JonCubed/boxstarter/master/config/AdminDeployment.xml"

    $VSCheckpoint = 'VSExtensions'
    $VSDone = Get-Checkpoint -CheckpointName $VSCheckpoint

    if (-not $VSDone)
    {
        #Install-ChocolateyVsixPackage 'PowerShell Tools for Visual Studio 2015' https://visualstudiogallery.msdn.microsoft.com/c9eb3ba8-0c59-4944-9a62-6eee37294597/file/199313/1/PowerShellTools.14.0.vsix
        Install-WebPackage '.NET Core Visual Studio Extension' 'exe' '/quiet' $tempInstallFolder https://go.microsoft.com/fwlink/?LinkID=827546 'DotNetCore.1.0.1-VS2015Tools.Preview2.0.3.exe' # for visual studio
        Set-Checkpoint -CheckpointName $VSCheckpoint -CheckpointValue 1
    }
    Write-BoxstarterMessage "Installing Windows Dev Features"
    # Bash for windows
    $features = choco list --source windowsfeatures
    if ($features | Where-Object {$_ -like "*Linux*"})
    {
        choco install Microsoft-Windows-Subsystem-Linux           --source windowsfeatures --limitoutput
    }
    # hyper-v (required for windows containers)
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
}

function Set-BaseSettings
{
    $checkpoint = 'BaseSettings'
    $done = Get-Checkpoint -CheckpointName $Checkpoint

    if ($done) {
        Write-BoxstarterMessage "Base settings are already configured"
        choco install explorer-show-all-folders         --limitoutput
        choco install explorer-expand-to-current-folder --limitoutput
        return
    }

	  Update-ExecutionPolicy -Policy Unrestricted

  	Set-Volume -DriveLetter $systemDriveLetter -NewFileSystemLabel "System"
  	Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -DisableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar

    Set-Checkpoint -CheckpointName $checkpoint -CheckpointValue 1
}

function Move-WindowsLibrary
{
    param(
        $libraryName,
        $newPath
    )

    if(-not (Test-Path $newPath))  #idempotent
	{
        Move-LibraryDirectory -libraryName $libraryName -newPath $newPath
    }
}

function Set-RegionalSettings
{
    $checkpoint = 'RegionalSettings'
    $done = Get-Checkpoint -CheckpointName $checkpoint

    if ($done) {
        Write-BoxstarterMessage "Regional settings are already configured"
        return
    }

	#http://stackoverflow.com/questions/4235243/how-to-set-timezone-using-powershell
	&"$env:windir\system32\tzutil.exe" /s "W. Europe Standard Time"

	Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortDate -Value 'dd MMM yy'
	Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sCountry -Value Germany
	Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortTime -Value 'hh:mm tt'
	Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sTimeFormat -Value 'hh:mm:ss tt'
	Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sLanguage -Value ENU

  Set-Checkpoint -CheckpointName $checkpoint -CheckpointValue 1
}

function New-InstallCache
{
    param
    (
        [String]
        $InstallDrive
    )

    $tempInstallFolder = Join-Path $InstallDrive "temp\install-cache"

    if(-not (Test-Path $tempInstallFolder)) {
        New-Item $tempInstallFolder -ItemType Directory
    }

    return $tempInstallFolder
}

function Set-Libraries
{
  $checkpoint = 'MoveLibraries'
  $done = Get-Checkpoint -CheckpointName $checkpoint

  if ($done) {
    Write-BoxstarterMessage "Libraries are already configured"
    return
  }

  Write-BoxstarterMessage "Configuring $dataDrive\"

  Set-Volume -DriveLetter $dataDriveLetter -NewFileSystemLabel "Data"

  $dataPath = "$dataDrive\"
  $mediaPath = "$dataDrive\Media"

  Move-WindowsLibrary -libraryName "Downloads"   -newPath (Join-Path $dataPath "Downloads")
  Move-WindowsLibrary -libraryName "Personal"    -newPath (Join-Path $dataPath "Documents")
  Move-WindowsLibrary -libraryName "My Video"    -newPath (Join-Path $mediaPath "Videos")
  Move-WindowsLibrary -libraryName "My Music"    -newPath (Join-Path $mediaPath "Music")
  Move-WindowsLibrary -libraryName "My Pictures" -newPath (Join-Path $mediaPath "Pictures")

  Set-Checkpoint -CheckpointName $checkpoint -CheckpointValue 1
}





# Settings
$systemDriveLetter = "C"
$dataDriveLetter = "D"
$systemDrive = "$systemDriveLetter`:"
$dataDrive = "$dataDriveLetter`:"
$tempInstallFolder = New-InstallCache -InstallDrive $systemDrive



#Execution

# disable chocolatey default confirmation behaviour (no need for --yes)
choco feature enable --name=allowGlobalConfirmation

Set-RegionalSettings
Set-BaseSettings
Set-Libraries

Write-BoxstarterMessage "Installing Core Apps"
Install-CoreApps

Write-BoxstarterMessage "Installing Home Apps"
Install-Home

Write-BoxstarterMessage "Installing dev"
Install-Dev

# re-enable chocolatey default confirmation behaviour
choco feature disable --name=allowGlobalConfirmation

if (Test-PendingReboot) { Invoke-Reboot }

# rerun windows update after we have installed everything
Write-BoxstarterMessage "Windows update..."
Install-WindowsUpdate

Clear-Checkpoints
