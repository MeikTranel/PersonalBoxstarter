$currentDir = Get-Location
$installScript = "$currentDir\box.ps1"
$webLauncherUrl = "http://boxstarter.org/package/nr/url?$installScript"
$edgeVersion = Get-AppxPackage -Name Microsoft.MicrosoftEdge

if ($edgeVersion)
{
    start microsoft-edge:$webLauncherUrl
}
else
{
    $IE=new-object -com internetexplorer.application
    $IE.navigate2($webLauncherUrl)
    $IE.visible=$true
}
