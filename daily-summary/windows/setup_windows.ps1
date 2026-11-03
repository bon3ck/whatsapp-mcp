# One-time setup on Windows: builds the bridge and registers two scheduled tasks.
#   1. "WhatsApp Bridge"  - starts the bridge when you log in and keeps it running.
#   2. "WhatsApp Export"  - every day 06:45, writes the 7-day export to Google Drive
#                           (wakes the laptop from sleep if needed).
#   3. "WhatsApp Send Approved" - every 5 minutes, sends only replies Aguro approved
#                           (files in "WA Summary\outbox\approved"), 30-60s apart.
# Run in PowerShell from the repo folder:
#   powershell -ExecutionPolicy Bypass -File daily-summary\windows\setup_windows.ps1
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [string]$ExportTime = "06:45",
    [string]$OutboxDir = ""
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$BridgeDir = Join-Path $Repo "whatsapp-bridge"

Write-Host "Building the bridge (needs Go + a C compiler, see README)..."
Push-Location $BridgeDir
go env -w CGO_ENABLED=1
go build -o whatsapp-bridge.exe .
Pop-Location

if (-not (Test-Path $ExportDir)) {
    Write-Warning "$ExportDir not found. Is Google Drive for desktop installed and signed in? Creating it anyway."
    New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
}

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries

$bridge = New-ScheduledTaskAction -Execute (Join-Path $BridgeDir "whatsapp-bridge.exe") -WorkingDirectory $BridgeDir
# Start 1 minute after logon so the network is up. The bridge exits with a
# non-zero code if it cannot connect, so RestartCount/RestartInterval above
# bring it back.
$bridgeTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$bridgeTrigger.Delay = "PT1M"
Register-ScheduledTask -TaskName "WhatsApp Bridge" -Action $bridge `
    -Trigger $bridgeTrigger -Settings $settings -Force | Out-Null

$exportArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$Repo\daily-summary\windows\run_daily.ps1`" -ExportDir `"$ExportDir`""
$export = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $exportArgs -WorkingDirectory $Repo
$exportSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "WhatsApp Export" -Action $export `
    -Trigger (New-ScheduledTaskTrigger -Daily -At $ExportTime) -Settings $exportSettings -Force | Out-Null

if (-not $OutboxDir) { $OutboxDir = Join-Path (Split-Path $ExportDir -Parent) "outbox" }
$sendArgs = "-3 `"$Repo\whatsapp-mcp-server\send_approved.py`" --outbox `"$OutboxDir`""
$send = New-ScheduledTaskAction -Execute "py.exe" -Argument $sendArgs -WorkingDirectory $Repo
$sendTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5)
$sendSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "WhatsApp Send Approved" -Action $send -Trigger $sendTrigger -Settings $sendSettings -Force | Out-Null

Write-Host "Done. Tasks 'WhatsApp Bridge' (at logon) and 'WhatsApp Export' (daily $ExportTime) registered, plus 'WhatsApp Send Approved' (every 5 min, outbox: $OutboxDir)."
Write-Host "Start the bridge now with: Start-ScheduledTask 'WhatsApp Bridge'"
