# One-click daily update, started from the "Update Ringkasan WA" desktop shortcut.
#   1. Starts the WhatsApp bridge (if it is not running yet).
#   2. Makes sure Google Drive for desktop is running (drive G:).
#   3. Waits until the bridge is connected and has finished catching up on messages.
#   4. Writes today's export to Drive, where the cloud routine turns it into the
#      "Ringkasan WA <date>" Doc.
# The bridge keeps running afterwards, so approved replies can still be sent.
# Create the shortcut with install_shortcut.ps1.
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [int]$Days = 7,
    [int]$MinSyncSeconds = 60,    # always wait at least this long after connecting
    [int]$QuietSeconds = 30,      # sync is done when the database has been quiet this long
    [int]$MaxSyncSeconds = 300,   # never wait longer than this for the sync
    [int]$ConnectTimeoutSeconds = 600,
    [switch]$NoPause
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$BridgeDir = Join-Path $Repo "whatsapp-bridge"
$BridgeExe = Join-Path $BridgeDir "whatsapp-bridge.exe"
$Store = Join-Path $BridgeDir "store"
$Log = Join-Path $Repo "daily-summary\export.log"
$Marker = Join-Path $Repo "daily-summary\last_export_date.txt"
$Host.UI.RawUI.WindowTitle = "Update Ringkasan WA"

function Write-Log([string]$msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $msg" | Add-Content $Log
}
function Say([string]$msg, [string]$color = "Gray") {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor $color
}
function Test-BridgeApi {
    # The bridge opens its REST port (8080) only after it is connected to WhatsApp.
    $c = New-Object System.Net.Sockets.TcpClient
    try { $c.ConnectAsync("127.0.0.1", 8080).Wait(1000) -and $c.Connected } catch { $false } finally { $c.Close() }
}
function Get-StoreWriteTime {
    $files = Get-ChildItem $Store -Filter "messages.db*" -ErrorAction SilentlyContinue
    if (-not $files) { return [datetime]::MinValue }
    ($files | Measure-Object LastWriteTime -Maximum).Maximum
}
function Finish([int]$code) {
    if (-not $NoPause) { Write-Host ""; Read-Host "Tekan Enter untuk menutup jendela ini" | Out-Null }
    exit $code
}

Write-Host "=== Update Ringkasan WA ($(Get-Date -Format 'dddd, dd MMM yyyy HH:mm')) ===" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Log "manual update started"

    # 1. Bridge
    if (Get-Process whatsapp-bridge -ErrorAction SilentlyContinue) {
        Say "Bridge WhatsApp sudah jalan."
    } else {
        if (-not (Test-Path $BridgeExe)) { throw "$BridgeExe tidak ada. Jalankan setup_windows.ps1 dulu untuk build bridge." }
        Say "Menyalakan bridge WhatsApp (jendelanya diminimize di taskbar)..."
        Start-Process -FilePath $BridgeExe -WorkingDirectory $BridgeDir -WindowStyle Minimized
        Write-Log "bridge started"
    }

    # 2. Google Drive for desktop
    $driveRoot = Split-Path -Qualifier $ExportDir
    if (-not (Test-Path $driveRoot)) {
        Say "Drive $driveRoot belum ada, menyalakan Google Drive for desktop..."
        $launcher = "C:\Program Files\Google\Drive File Stream\launch.bat"
        if (Test-Path $launcher) { Start-Process $launcher -WindowStyle Hidden }
    }

    # 3a. Wait for the bridge to connect
    Say "Menunggu bridge tersambung ke WhatsApp..."
    $t0 = Get-Date
    while (-not (Test-BridgeApi)) {
        if (-not (Get-Process whatsapp-bridge -ErrorAction SilentlyContinue)) {
            throw "Bridge berhenti sebelum tersambung. Buka jendela bridge / jalankan ulang. Kalau minta scan QR, scan dari WhatsApp > Perangkat tertaut."
        }
        if (((Get-Date) - $t0).TotalSeconds -gt $ConnectTimeoutSeconds) {
            throw "Bridge belum tersambung setelah $([int]($ConnectTimeoutSeconds/60)) menit. Cek internet dan jendela bridge."
        }
        Start-Sleep -Seconds 3
    }
    Say "Bridge tersambung." "Green"

    # 3b. Wait for the message sync to settle
    Say "Menunggu pesan baru selesai masuk (min $MinSyncSeconds dtk, maks $([int]($MaxSyncSeconds/60)) mnt)..."
    $t1 = Get-Date
    while ($true) {
        Start-Sleep -Seconds 5
        $elapsed = ((Get-Date) - $t1).TotalSeconds
        $quiet = ((Get-Date) - (Get-StoreWriteTime)).TotalSeconds
        Write-Host ("`r  {0,3} dtk berjalan, database diam {1,3} dtk   " -f [int]$elapsed, [int][Math]::Min($quiet, 999)) -NoNewline
        if ($elapsed -ge $MaxSyncSeconds) { break }
        if ($elapsed -ge $MinSyncSeconds -and $quiet -ge $QuietSeconds) { break }
    }
    Write-Host ""
    Say "Sinkron selesai." "Green"

    # 3c. Drive must be mounted before we write
    for ($i = 0; $i -lt 40 -and -not (Test-Path $driveRoot); $i++) {
        if ($i -eq 0) { Say "Menunggu Google Drive ($driveRoot)..." }
        Start-Sleep -Seconds 15
    }
    if (-not (Test-Path $driveRoot)) { throw "$driveRoot belum muncul setelah 10 menit. Buka Google Drive for desktop dan login." }
    if (-not (Test-Path $ExportDir)) { New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null }

    # 4. Export (python via cmd so its stderr is captured instead of aborting the script)
    Say "Membuat ekspor $Days hari ke $ExportDir ..."
    $script = Join-Path $Repo "whatsapp-mcp-server\export_daily.py"
    $out = cmd /c "py -3 `"$script`" --out `"$ExportDir`" --days $Days 2>&1" | Out-String
    if ($LASTEXITCODE -ne 0) { throw "export_daily.py gagal (exit $LASTEXITCODE): $($out.Trim())" }
    Write-Log $out.Trim()
    Set-Content -Path $Marker -Value (Get-Date -Format "yyyy-MM-dd")

    Write-Host ""
    Say $out.Trim()
    Say "SELESAI. Ekspor hari ini sudah di Google Drive." "Green"
    Say "Ringkasan WA hari ini akan dibuat Claude paling lambat dalam 1 jam (setelah Drive selesai upload)." "Green"
    Say "Bridge tetap jalan supaya balasan yang disetujui bisa terkirim. Tutup jendela bridge kalau mau mematikannya."
    Finish 0
}
catch {
    Write-Log "ERROR $_"
    Write-Host ""
    Say "GAGAL: $_" "Red"
    Say "Detail ada di $Log" "Red"
    Finish 1
}
