# Daily WhatsApp export (Windows). Run by the "WhatsApp Export" scheduled task at 06:45.
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [int]$Days = 7,
    [int]$SyncWaitSeconds = 180
)
$ErrorActionPreference = "Stop"
$Repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Log = Join-Path $Repo "daily-summary\export.log"

function Write-Log([string]$msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $msg" | Add-Content $Log
}

try {
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
}
catch {
    Write-Log "ERROR $_"
    exit 1
}
