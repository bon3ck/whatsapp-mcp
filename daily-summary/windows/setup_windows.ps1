# One-time setup on Windows: builds the bridge and registers two scheduled tasks.
#   1. "WhatsApp Bridge"  - starts the bridge when you log in and keeps it running.
#   2. "WhatsApp Export"  - once per day, the first of: laptop on in the morning
#                           (logon, unlock, wake) or 07:00, writes the 7-day export
#                           to Google Drive (see register_export_task.ps1).
# Run in PowerShell from the repo folder:
#   powershell -ExecutionPolicy Bypass -File daily-summary\windows\setup_windows.ps1
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [string]$ExportTime = "07:00"
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

& (Join-Path $PSScriptRoot "register_export_task.ps1") -ExportDir $ExportDir -ExportTime $ExportTime

Write-Host "Done. Tasks 'WhatsApp Bridge' (at logon) and 'WhatsApp Export' (morning logon/unlock/wake or $ExportTime, once a day) registered."
Write-Host "Start the bridge now with: Start-ScheduledTask 'WhatsApp Bridge'"
