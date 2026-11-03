# Registers (or replaces) the "WhatsApp Export" scheduled task. It fires:
#   - every day at $ExportTime (default 07:00, wakes the laptop from sleep),
#   - when you log on, when you unlock the laptop, and when it wakes from sleep.
# run_daily.ps1 makes sure only the first of these each morning does the export.
# Safe to run again; it does not touch the bridge or the sender tasks.
#   powershell -ExecutionPolicy Bypass -File daily-summary\windows\register_export_task.ps1
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [string]$ExportTime = "07:00"
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ns = "Root/Microsoft/Windows/TaskScheduler"

$daily = New-ScheduledTaskTrigger -Daily -At $ExportTime

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$logon.Delay = "PT2M"

$unlock = New-CimInstance -CimClass (Get-CimClass -Namespace $ns -ClassName MSFT_TaskSessionStateChangeTrigger) -ClientOnly
$unlock.StateChange = 8   # TASK_SESSION_UNLOCK
$unlock.UserId = "$env:USERDOMAIN\$env:USERNAME"
$unlock.Delay = "PT1M"
$unlock.Enabled = $true

$wake = New-CimInstance -CimClass (Get-CimClass -Namespace $ns -ClassName MSFT_TaskEventTrigger) -ClientOnly
$wake.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">' +
    "*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]" +
    '</Select></Query></QueryList>'
$wake.Delay = "PT2M"
$wake.Enabled = $true

$exportArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Repo\daily-summary\windows\run_daily.ps1`" -ExportDir `"$ExportDir`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $exportArgs -WorkingDirectory $Repo
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Register-ScheduledTask -TaskName "WhatsApp Export" -Action $action `
    -Trigger @($daily, $logon, $unlock, $wake) -Settings $settings -Force | Out-Null

Write-Host "Task 'WhatsApp Export' registered: daily $ExportTime + at logon, unlock and wake (once per day)."
