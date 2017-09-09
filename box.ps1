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
    choco install googlechrome-allusers --limitoutput
    choco install vlc --limitoutput
    choco install 7zip.install --limitoutput
    choco install javaruntime --limitoutput
}

function Install-Home
{
    choco install spotify --limitoutput
    choco install steam --limitoutput
    choco install hexchat --limitoutput
    choco install discord --limitoutput
}

function Install-MiscTools
{    
    choco install procexp --limitoutput
    choco install sysinternals --limitoutput
    choco install handbrake --limitoutput
    choco install audacity --limitoutput
    choco install audacity-lame --limitoutput    
}


function Install-Dev
{
    choco install git.install -params '"/GitAndUnixToolsOnPath"' --limitoutput
    choco install jdk8 --limitoutput
    choco install putty --limitoutput
    choco install winmerge --limitoutput
    choco install p4merge --limitoutput
    choco install gitkraken --limitoutput

    Write-BoxstarterMessage "Installing Windows Dev Features"
    # Bash for windows
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All
    # hyper-v (required for windows containers)
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All    
}

function Set-BaseSettings
{
    $checkpoint = 'BaseSettings'
    $done = Get-Checkpoint -CheckpointName $Checkpoint
	Update-ExecutionPolicy -Policy Unrestricted
	Disable-BingSearch
	Disable-GameBarTips
	Enable-RemoteDesktop
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

Write-BoxstarterMessage "Installing Misc Tools"
Install-MiscTools


Write-BoxstarterMessage "Installing dev"
Install-Dev

# re-enable chocolatey default confirmation behaviour
choco feature disable --name=allowGlobalConfirmation

if (Test-PendingReboot) { Invoke-Reboot }

Clear-Checkpoints
