# Daily WhatsApp export (Windows). Run by the "WhatsApp Export" scheduled task, which fires
# at 07:00, at logon, on unlock and on wake from sleep. Only the first run of the day from
# $EarliestHour onwards does the export; every later trigger that day exits at once.
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [int]$Days = 7,
    [int]$SyncWaitSeconds = 180,
    [int]$EarliestHour = 5,
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$Repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Log = Join-Path $Repo "daily-summary\export.log"
$Marker = Join-Path $Repo "daily-summary\last_export_date.txt"
$Today = Get-Date -Format "yyyy-MM-dd"

function Write-Log([string]$msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $msg" | Add-Content $Log
}

if (-not $Force) {
    # Laptop switched on in the middle of the night: wait for a morning trigger.
    if ((Get-Date).Hour -lt $EarliestHour) { exit 0 }
    # Already exported today: once per day is enough.
    if ((Test-Path $Marker) -and ((Get-Content $Marker -Raw).Trim() -eq $Today)) { exit 0 }
}

try {
    Write-Log "start daily export"

    # Make sure the WhatsApp bridge is running (it may have died across sleep/wake).
    if (-not (Get-Process whatsapp-bridge -ErrorAction SilentlyContinue)) {
        Write-Log "bridge not running, starting 'WhatsApp Bridge' task"
        schtasks /Run /TN "WhatsApp Bridge" | Out-Null
    }

    # Make sure Google Drive for desktop is running and the export drive is mounted.
    $driveRoot = Split-Path -Qualifier $ExportDir
    if (-not (Test-Path $driveRoot)) {
        Write-Log "$driveRoot not mounted, starting Google Drive for desktop"
        Start-Process "C:\Program Files\Google\Drive File Stream\launch.bat" -WindowStyle Hidden
    }

    # Give the bridge a few minutes to sync messages if the laptop just woke up.
    Start-Sleep -Seconds $SyncWaitSeconds

    for ($i = 0; $i -lt 40 -and -not (Test-Path $driveRoot); $i++) { Start-Sleep -Seconds 15 }
    if (-not (Test-Path $driveRoot)) { throw "$driveRoot still not mounted after waiting" }

    # Run python via cmd so its stderr doesn't abort the script before we can log it.
    $script = Join-Path $Repo "whatsapp-mcp-server\export_daily.py"
    $out = cmd /c "py -3 `"$script`" --out `"$ExportDir`" --days $Days 2>&1" | Out-String
    if ($LASTEXITCODE -ne 0) { throw "export_daily.py exited $LASTEXITCODE`: $($out.Trim())" }
    Write-Log $out.Trim()
    Set-Content -Path $Marker -Value $Today
}
catch {
    # No marker on failure, so the next trigger today (unlock, wake, logon) tries again.
    Write-Log "ERROR $_"
    exit 1
}
