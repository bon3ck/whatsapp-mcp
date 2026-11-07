# Creates the desktop shortcut "Update Ringkasan WA" that runs update_ringkasan.ps1
# (start bridge, wait for sync, export to Drive) with one double-click.
#   powershell -ExecutionPolicy Bypass -File daily-summary\windows\install_shortcut.ps1
# Add -DisableSchedule to switch off the automatic "WhatsApp Bridge" (at logon) and
# "WhatsApp Export" (daily) tasks, so the bridge only runs when you click the shortcut.
# Undo with -EnableSchedule. The "WhatsApp Send Approved" task is left alone.
# Add -InstallSender to register "WhatsApp Send Approved": every 5 minutes it sends the
# replies Aguro approved (WA Summary\outbox\approved). It runs hidden and does nothing
# while the bridge is off, so approved replies go out once the shortcut has started it.
# Everything at once:
#   powershell -ExecutionPolicy Bypass -File daily-summary\windows\install_shortcut.ps1 -DisableSchedule -InstallSender
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [string]$OutboxDir = "",
    [string]$Name = "Update Ringkasan WA",
    [switch]$DisableSchedule,
    [switch]$EnableSchedule,
    [switch]$InstallSender
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Script = Join-Path $Repo "daily-summary\windows\update_ringkasan.ps1"

$desktop = [Environment]::GetFolderPath("Desktop")   # follows OneDrive desktop redirection
$lnkPath = Join-Path $desktop "$Name.lnk"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" -ExportDir `"$ExportDir`""
$lnk.WorkingDirectory = $Repo
$lnk.IconLocation = (Join-Path $env:SystemRoot "System32\shell32.dll") + ",238"
$lnk.Description = "Nyalakan bridge WhatsApp dan perbarui ringkasan WA harian"
$lnk.Save()
Write-Host "Shortcut dibuat: $lnkPath"

$tasks = "WhatsApp Bridge", "WhatsApp Export"
foreach ($t in $tasks) {
    $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if (-not $task) { continue }
    if ($DisableSchedule) { Disable-ScheduledTask -TaskName $t | Out-Null; Write-Host "Jadwal '$t' dimatikan." }
    elseif ($EnableSchedule) { Enable-ScheduledTask -TaskName $t | Out-Null; Write-Host "Jadwal '$t' dinyalakan lagi." }
    else { Write-Host "Jadwal '$t' masih $($task.State). Tambah -DisableSchedule untuk mematikannya." }
}

if ($InstallSender) {
    if (-not $OutboxDir) { $OutboxDir = Join-Path (Split-Path $ExportDir -Parent) "outbox" }
    $sendScript = Join-Path $Repo "whatsapp-mcp-server\send_approved.py"
    # Task Scheduler cannot start the Microsoft Store "py"/"pyw" aliases (WindowsApps),
    # so ask Python where it really lives and use pythonw.exe (no window) next to it.
    $python = (cmd /c "py -3 -c `"import sys; print(sys.executable)`" 2>nul" | Select-Object -Last 1)
    if (-not $python) { $python = (cmd /c "python -c `"import sys; print(sys.executable)`" 2>nul" | Select-Object -Last 1) }
    if (-not $python -or -not (Test-Path $python)) { throw "Python tidak ditemukan. Install Python 3 dulu." }
    $pythonw = Join-Path (Split-Path $python -Parent) "pythonw.exe"
    if (-not (Test-Path $pythonw)) { $pythonw = $python }
    $send = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$sendScript`" --outbox `"$OutboxDir`"" -WorkingDirectory $Repo
    $sendTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5)
    $sendSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "WhatsApp Send Approved" -Action $send -Trigger $sendTrigger -Settings $sendSettings -Force | Out-Null
    Write-Host "Pengirim 'WhatsApp Send Approved' dipasang (tiap 5 menit, $pythonw, outbox: $OutboxDir)."
}
