# Daily WhatsApp summary to Google Drive

Every morning at 07:00 WIB a Google Doc "Ringkasan WA <date>" appears in the Drive folder
**WA Summary**: a 7-day summary of personal and group chats, draft replies and greetings in
your own chat style, work follow-ups, and a work plan. Nothing is ever sent automatically.
For a contact you have never replied to, there is no draft: the Doc summarizes the chat and asks
you how you want to answer.

## How it works

1. **Bridge** (`whatsapp-bridge`) runs on your laptop (later a VPS) and stores messages in SQLite.
2. **06:45 WIB** `run_daily.sh` runs `export_daily.py`, which writes `wa-export-<date>.md`
   (last 7 days + samples of your own sent messages for style) into `WA Summary/exports` on Drive.
3. **07:00 WIB** a scheduled Claude routine reads the export and writes the summary Doc
   (prompt: `ROUTINE_PROMPT.md`).

## Setup on Windows (current laptop)

1. Install [Go](https://go.dev/dl/), [Python 3](https://www.python.org/downloads/) (tick "Add to PATH"),
   [Git](https://git-scm.com/download/win), and [MSYS2](https://www.msys2.org/) for the C compiler. In the
   MSYS2 UCRT64 terminal run `pacman -S mingw-w64-ucrt-x86_64-gcc`, then add `C:\msys64\ucrt64\bin` to PATH.
2. Install [Google Drive for desktop](https://www.google.com/drive/download/) and sign in with the
   account that owns the "WA Summary" folder. It usually appears as drive `G:\My Drive`.
3. Clone the repo, open PowerShell in it, and link WhatsApp once (scan the QR in WhatsApp > Linked devices):
   ```powershell
   git clone -b claude/project-thread-pghac4 https://github.com/bon3ck/whatsapp-mcp.git
   cd whatsapp-mcp\whatsapp-bridge
   go env -w CGO_ENABLED=1
   go run main.go
   ```
   After it says it is connected and has synced, stop it with Ctrl+C.
4. Register the tasks (bridge at logon, export daily 06:45, wakes the laptop):
   ```powershell
   cd ..
   powershell -ExecutionPolicy Bypass -File daily-summary\windows\setup_windows.ps1
   Start-ScheduledTask "WhatsApp Bridge"
   ```
   If your Drive is not `G:\My Drive`, add `-ExportDir "X:\My Drive\WA Summary\exports"`.
5. Test once: `powershell -ExecutionPolicy Bypass -File daily-summary\windows\run_daily.ps1`, then check
   that `wa-export-<date>.md` appears in Drive under WA Summary/exports.

### Manual mode: one desktop shortcut instead of schedules

If you prefer to update the summary yourself once a day, create the shortcut and switch off the
automatic bridge/export tasks:
```powershell
powershell -ExecutionPolicy Bypass -File daily-summary\windows\install_shortcut.ps1 -DisableSchedule
```
Double-click **Update Ringkasan WA** on the desktop. It starts the bridge (minimized), starts
Google Drive if needed, waits until the bridge is connected and new messages stop coming in
(1-5 minutes), writes `wa-export-<date>.md` to Drive and shows SELESAI or GAGAL. The bridge keeps
running afterwards so approved replies can be sent. The cloud routine picks up the export and
writes the Doc. To go back to the schedules: `install_shortcut.ps1 -EnableSchedule`.

Keep the laptop plugged in overnight. In Control Panel > Power Options > Change advanced settings,
enable "Allow wake timers" so the 06:45 task can wake it.

## Setup on macOS / Linux

1. Run the bridge once and scan the QR code (WhatsApp > Linked devices):
   `cd whatsapp-bridge && go run main.go`. Keep it running (laptop on, not sleeping, at 06:45).
2. Install [Google Drive for desktop](https://www.google.com/drive/download/) and sign in.
3. Test the export:
   ```bash
   WA_EXPORT_DIR="$HOME/Google Drive/My Drive/WA Summary/exports" ./daily-summary/run_daily.sh
   ```
4. Schedule it at 06:45 WIB.
   - macOS / Linux, `crontab -e` (adjust the path; the laptop clock must be WIB):
     ```
     45 6 * * * WA_EXPORT_DIR="$HOME/Google Drive/My Drive/WA Summary/exports" /path/to/whatsapp-mcp/daily-summary/run_daily.sh >> /tmp/wa-export.log 2>&1
     ```
   - Windows, Task Scheduler: daily 06:45, action
     `python C:\path\to\whatsapp-mcp\whatsapp-mcp-server\export_daily.py --out "G:\My Drive\WA Summary\exports"`.

## Moving to a VPS later

Run the bridge as a service (systemd), install `rclone`, run `rclone config` once to add a
Google Drive remote, then set `WA_RCLONE_REMOTE="gdrive:WA Summary/exports"` in the cron line.

## Options

`export_daily.py --days 7 --style-samples 80 --exclude "Group name"` (repeat `--exclude` to skip chats).
