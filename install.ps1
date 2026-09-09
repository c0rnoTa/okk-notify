#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [TimeSpan]$CheckInterval = '00:10:00',
    [TimeSpan]$FirstAlertAfter = '7.00:00:00',
    [TimeSpan]$RedAlertAfter = '8.00:00:00',
    [string]$InstallDir = (Join-Path $env:ProgramData 'OKKRebootReminder')
)

$ErrorActionPreference = 'Stop'

if ($CheckInterval -le [TimeSpan]::Zero) {
    throw 'CheckInterval must be greater than zero.'
}
if ($FirstAlertAfter -le [TimeSpan]::Zero) {
    throw 'FirstAlertAfter must be greater than zero.'
}
if ($RedAlertAfter -le $FirstAlertAfter) {
    throw 'RedAlertAfter must be greater than FirstAlertAfter.'
}

$taskName = 'OKK Reboot Reminder'
$sourceDir = $PSScriptRoot

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

foreach ($file in @('reboot-reminder.ps1', 'launch.vbs')) {
    $src = Join-Path $sourceDir $file
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing source file: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $file) -Force
}

$config = [ordered]@{
    CheckInterval   = $CheckInterval.ToString()
    FirstAlertAfter = $FirstAlertAfter.ToString()
    RedAlertAfter   = $RedAlertAfter.ToString()
}
$configPath = Join-Path $InstallDir 'config.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json), $utf8NoBom)

$launchPath = Join-Path $InstallDir 'launch.vbs'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //Nologo `"$launchPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
# S-1-5-32-545 = BUILTIN\Users (locale-independent)
$principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances Parallel `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Installed to $InstallDir"
Write-Host "Scheduled task: $taskName (At logon, any user, interactive session)"
Write-Host "CheckInterval=$CheckInterval FirstAlertAfter=$FirstAlertAfter RedAlertAfter=$RedAlertAfter"
Write-Host 'Already logged-on users need to log off/on or start launch.vbs once to get the agent in this session.'
