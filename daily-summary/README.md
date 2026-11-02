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

## Setup on the laptop

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
