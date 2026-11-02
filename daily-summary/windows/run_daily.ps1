# Daily WhatsApp export (Windows). Run by the "WhatsApp Export" scheduled task at 06:45.
param(
    [string]$ExportDir = "G:\My Drive\WA Summary\exports",
    [int]$Days = 7
)
$ErrorActionPreference = "Stop"
$Repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Log = Join-Path $Repo "daily-summary\export.log"

# Give the bridge a few minutes to sync messages if the laptop just woke up.
Start-Sleep -Seconds 180

$out = & py -3 (Join-Path $Repo "whatsapp-mcp-server\export_daily.py") --out $ExportDir --days $Days 2>&1
"$(Get-Date -Format 'yyyy-MM-dd HH:mm') $out" | Add-Content $Log
