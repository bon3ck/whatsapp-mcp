#!/usr/bin/env bash
# Daily WhatsApp export for the summary routine (macOS / Linux / VPS).
# Schedule at 07:00 WIB (or earlier); the summary task checks Drive every hour until 12:12.
#
# Settings (env vars or edit below):
#   WA_EXPORT_DIR     folder for exports. On a laptop with Google Drive for desktop, use the
#                     synced folder, e.g. "$HOME/Google Drive/My Drive/WA Summary/exports".
#   WA_RCLONE_REMOTE  optional, for a VPS without Google Drive for desktop,
#                     e.g. "gdrive:WA Summary/exports" (set up once with `rclone config`).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
: "${WA_EXPORT_DIR:=$REPO/daily-summary/exports}"
: "${WA_EXPORT_DAYS:=7}"

FILE="$(python3 "$REPO/whatsapp-mcp-server/export_daily.py" --out "$WA_EXPORT_DIR" --days "$WA_EXPORT_DAYS")"
echo "Exported: $FILE"

if [[ -n "${WA_RCLONE_REMOTE:-}" ]]; then
  rclone copy "$FILE" "$WA_RCLONE_REMOTE"
  echo "Uploaded to $WA_RCLONE_REMOTE"
fi
