#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramData 'OKKRebootReminder')
)

$ErrorActionPreference = 'Stop'

$taskName = 'OKK Reboot Reminder'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed scheduled task: $taskName"
}
else {
    Write-Host "Scheduled task not found: $taskName"
}

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "Removed $InstallDir"
}
else {
    Write-Host "Install directory not found: $InstallDir"
}

Write-Host 'Already running agent processes keep working until logoff. They will not start again after uninstall.'
