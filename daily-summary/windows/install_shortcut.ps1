# Creates the desktop shortcut "Update Ringkasan WA" that runs update_ringkasan.ps1
# (start bridge, wait for sync, export to Drive) with one double-click.
#   powershell -ExecutionPolicy Bypass -File daily-summary\windows\install_shortcut.ps1
# Add -DisableSchedule to switch off the automatic "WhatsApp Bridge" (at logon) and
# "WhatsApp Export" (daily) tasks, so the bridge only runs when you click the shortcut.
# Undo with -EnableSchedule. The "WhatsApp Send Approved" task is left alone.
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [string]$Name = "Update Ringkasan WA",
    [switch]$DisableSchedule,
    [switch]$EnableSchedule
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
