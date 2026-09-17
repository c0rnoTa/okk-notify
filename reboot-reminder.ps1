#Requires -Version 5.1
<#
.SYNOPSIS
  Фоновый агент: напоминает о перезагрузке ПК по аптайму.
#>
[CmdletBinding()]
param(
    [TimeSpan]$CheckInterval,
    [TimeSpan]$FirstAlertAfter,
    [TimeSpan]$RedAlertAfter
)

$ErrorActionPreference = 'Stop'

function Read-AgentConfig {
    $defaults = @{
        CheckInterval   = [TimeSpan]'00:10:00'
        FirstAlertAfter = [TimeSpan]'7.00:00:00'
        RedAlertAfter   = [TimeSpan]'8.00:00:00'
    }

    $configPath = Join-Path $PSScriptRoot 'config.json'
    $file = @{}
    if (Test-Path -LiteralPath $configPath) {
        $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.CheckInterval) { $file.CheckInterval = [TimeSpan]$raw.CheckInterval }
        if ($raw.FirstAlertAfter) { $file.FirstAlertAfter = [TimeSpan]$raw.FirstAlertAfter }
        if ($raw.RedAlertAfter) { $file.RedAlertAfter = [TimeSpan]$raw.RedAlertAfter }
    }

    $check = if ($PSBoundParameters.ContainsKey('CheckInterval')) { $CheckInterval } elseif ($file.CheckInterval) { $file.CheckInterval } else { $defaults.CheckInterval }
    $first = if ($PSBoundParameters.ContainsKey('FirstAlertAfter')) { $FirstAlertAfter } elseif ($file.FirstAlertAfter) { $file.FirstAlertAfter } else { $defaults.FirstAlertAfter }
    $red = if ($PSBoundParameters.ContainsKey('RedAlertAfter')) { $RedAlertAfter } elseif ($file.RedAlertAfter) { $file.RedAlertAfter } else { $defaults.RedAlertAfter }

    if ($check -le [TimeSpan]::Zero) {
        throw 'CheckInterval must be greater than zero.'
    }
    if ($first -le [TimeSpan]::Zero) {
        throw 'FirstAlertAfter must be greater than zero.'
    }
    if ($red -le $first) {
        throw 'RedAlertAfter must be greater than FirstAlertAfter.'
    }

    [pscustomobject]@{
        CheckInterval   = $check
        FirstAlertAfter = $first
        RedAlertAfter   = $red
    }
}

function Get-SystemUptime {
    $boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    (Get-Date) - $boot
}

function Get-DayWord([int]$Days) {
    $n10 = $Days % 10
    $n100 = $Days % 100
    if ($n10 -eq 1 -and $n100 -ne 11) { return 'день' }
    if ($n10 -ge 2 -and $n10 -le 4 -and ($n100 -lt 12 -or $n100 -gt 14)) { return 'дня' }
    return 'дней'
}

function Show-RebootAlert {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Normal', 'Yellow', 'Red')]
        [string]$Level,
        [Parameter(Mandatory)]
        [TimeSpan]$Uptime
    )

    $days = [Math]::Max(0, [int][Math]::Floor($Uptime.TotalDays))
    $dayWord = Get-DayWord $days

    switch ($Level) {
        'Normal' {
            $title = 'Требуется перезагрузка'
            $text = "Компьютер не перезагружался более $days $dayWord, перезагрузите его!"
            $back = [System.Drawing.Color]::FromArgb(245, 245, 245)
            $fore = [System.Drawing.Color]::FromArgb(30, 30, 30)
            $fontSize = 14
        }
        'Yellow' {
            $title = 'Перезагрузка отложена'
            $text = 'Вы недавно отложили перезагрузку, перезагрузите компьютер!'
            $back = [System.Drawing.Color]::FromArgb(255, 220, 60)
            $fore = [System.Drawing.Color]::FromArgb(40, 30, 0)
            $fontSize = 14
        }
        'Red' {
            $title = 'СРОЧНО: перезагрузите компьютер'
            $text = "СРОЧНО! Компьютер не перезагружался более $days $dayWord!`nПерезагрузите его немедленно!"
            $back = [System.Drawing.Color]::FromArgb(176, 16, 16)
            $fore = [System.Drawing.Color]::White
            $fontSize = 18
        }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $form.BackColor = $back
    $form.ClientSize = New-Object System.Drawing.Size 560, 240
    $form.KeyPreview = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.ForeColor = $fore
    $label.BackColor = $back
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold)
    $label.AutoSize = $false
    $label.TextAlign = 'MiddleCenter'
    $label.Location = New-Object System.Drawing.Point 20, 20
    $label.Size = New-Object System.Drawing.Size 520, 140

    $button = New-Object System.Windows.Forms.Button
    $button.Text = 'ОК'
    $button.Font = New-Object System.Drawing.Font 'Segoe UI', 12
    $button.Size = New-Object System.Drawing.Size 120, 36
    $button.Location = New-Object System.Drawing.Point 220, 180
    $button.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $button.FlatStyle = 'System'

    $form.AcceptButton = $button
    $form.Controls.Add($label)
    $form.Controls.Add($button)

    $form.Add_FormClosing({
        param($sender, $e)
        if ($e.CloseReason -ne [System.Windows.Forms.CloseReason]::None) {
            $sender.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
    })

    [void]$form.ShowDialog()
    $form.Dispose()
}

if ([System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
    throw 'Agent must run in an interactive user session, not Session 0.'
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $argList = @(
        '-NoProfile'
        '-STA'
        '-WindowStyle', 'Hidden'
        '-ExecutionPolicy', 'Bypass'
        '-File', $PSCommandPath
    )
    foreach ($name in @('CheckInterval', 'FirstAlertAfter', 'RedAlertAfter')) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $argList += "-$name"
            $argList += $PSBoundParameters[$name].ToString()
        }
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden | Out-Null
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$mutex = New-Object System.Threading.Mutex($false, 'Local\OKKRebootReminder')
if (-not $mutex.WaitOne(0)) {
    return
}

try {
    $config = Read-AgentConfig
    $dismissedFirst = $false

    while ($true) {
        $uptime = Get-SystemUptime

        if ($uptime -ge $config.RedAlertAfter) {
            Show-RebootAlert -Level Red -Uptime $uptime
        }
        elseif ($uptime -ge $config.FirstAlertAfter) {
            if (-not $dismissedFirst) {
                Show-RebootAlert -Level Normal -Uptime $uptime
                $dismissedFirst = $true
            }
            else {
                Show-RebootAlert -Level Yellow -Uptime $uptime
            }
        }

        Start-Sleep -Seconds ([Math]::Max(1, [int]$config.CheckInterval.TotalSeconds))
    }
}
finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
