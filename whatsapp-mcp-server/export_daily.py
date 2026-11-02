#!/usr/bin/env python3
"""Export recent WhatsApp chats to a Markdown file for the daily summary.

Reads the bridge's SQLite store (read-only) and writes one file per run,
e.g. ``wa-export-2026-11-02.md``, into an output folder. Point the output
folder at a Google Drive synced folder (Google Drive for desktop) or upload
it afterwards with rclone (see run_daily.sh).

Nothing is sent to WhatsApp; this script only reads.

Usage:
    python export_daily.py --out "/path/to/Google Drive/WA Summary/exports"
    python export_daily.py --days 7 --style-samples 80
"""

from __future__ import annotations

import argparse
import os
import re
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

DEFAULT_DB = Path(__file__).resolve().parent.parent / "whatsapp-bridge" / "store" / "messages.db"
WIB = timezone(timedelta(hours=7))

# go-sqlite3 stores time.Time like "2026-11-02 07:00:00.123456789+07:00"
_TS_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d+))?\s*(Z|[+-]\d{2}:?\d{2})?"
)


def parse_ts(value) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    m = _TS_RE.match(str(value).strip())
    if not m:
        return None
    date_part, time_part, frac, tz = m.groups()
    dt = datetime.fromisoformat(f"{date_part} {time_part}")
    if frac:
        dt = dt.replace(microsecond=int(frac[:6].ljust(6, "0")))
    if not tz or tz == "Z":
        return dt.replace(tzinfo=timezone.utc)
    sign = 1 if tz[0] == "+" else -1
    digits = tz[1:].replace(":", "")
    offset = timedelta(hours=int(digits[:2]), minutes=int(digits[2:4]))
    return dt.replace(tzinfo=timezone(sign * offset))


@dataclass
class Msg:
    ts: datetime
    sender: str
    from_me: bool
    text: str


@dataclass
class Chat:
    jid: str
    name: str
    is_group: bool
    messages: list[Msg] = field(default_factory=list)
    ever_replied: bool = False  # Aguro has sent at least one message in this chat, ever


def one_line(text: str) -> str:
    return " ".join((text or "").split())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=os.environ.get("WA_DB_PATH", str(DEFAULT_DB)))
    ap.add_argument("--out", default=os.environ.get("WA_EXPORT_DIR", "exports"))
    ap.add_argument("--days", type=int, default=int(os.environ.get("WA_EXPORT_DAYS", "7")))
    ap.add_argument("--style-samples", type=int, default=80,
                    help="How many of your own recent messages to include as chat-style samples")
    ap.add_argument("--exclude", action="append", default=[],
                    help="Chat name or JID to skip (repeatable)")
    args = ap.parse_args()

    if not Path(args.db).exists():
        raise SystemExit(f"Database not found: {args.db} (is the bridge running and logged in?)")

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    cur = conn.cursor()

    names = {jid: name for jid, name in cur.execute("SELECT jid, name FROM chats")}

    def sender_name(sender: str) -> str:
        if not sender:
            return "?"
        user = sender.split("@")[0]
        for jid in (sender, f"{user}@s.whatsapp.net"):
            if names.get(jid):
                return names[jid]
        return user

    replied = {row[0] for row in cur.execute("SELECT DISTINCT chat_jid FROM messages WHERE is_from_me = 1")}

    now = datetime.now(timezone.utc)
    since = now - timedelta(days=args.days)
    excluded = set(args.exclude)

    chats: dict[str, Chat] = {}
    rows = cur.execute(
        "SELECT chat_jid, sender, content, timestamp, is_from_me, media_type, filename FROM messages"
    )
    for chat_jid, sender, content, ts_raw, from_me, media_type, filename in rows:
        ts = parse_ts(ts_raw)
        if ts is None or ts < since:
            continue
        name = names.get(chat_jid) or chat_jid.split("@")[0]
        if chat_jid in excluded or name in excluded:
            continue
        chat = chats.get(chat_jid)
        if chat is None:
            chat = chats[chat_jid] = Chat(
                jid=chat_jid, name=name, is_group=chat_jid.endswith("@g.us"),
                ever_replied=chat_jid in replied,
            )
        text = one_line(content)
        if media_type:
            label = f"[{media_type}{': ' + filename if filename else ''}]"
            text = f"{label} {text}".strip()
        if not text:
            continue
        chat.messages.append(Msg(ts=ts, sender="Aguro (saya)" if from_me else sender_name(sender),
                                 from_me=bool(from_me), text=text))

    style = [
        one_line(c) for (c,) in cur.execute(
            "SELECT content FROM messages WHERE is_from_me = 1 AND content IS NOT NULL AND content != '' "
            "ORDER BY timestamp DESC LIMIT ?", (args.style_samples,)
        )
    ]
    conn.close()

    for chat in chats.values():
        chat.messages.sort(key=lambda m: m.ts)
    ordered = sorted((c for c in chats.values() if c.messages),
                     key=lambda c: c.messages[-1].ts, reverse=True)

    today = now.astimezone(WIB)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"wa-export-{today:%Y-%m-%d}.md"

    lines = [
        f"# Ekspor WhatsApp {today:%Y-%m-%d}",
        "",
        f"- Dibuat: {today:%Y-%m-%d %H:%M} WIB",
        f"- Periode: {args.days} hari terakhir (sejak {since.astimezone(WIB):%Y-%m-%d %H:%M} WIB)",
        f"- Jumlah chat aktif: {len(ordered)}",
        "",
        "Status per chat:",
        "- `MENUNGGU_BALASAN`: pesan terakhir bukan dari Aguro.",
        "- `KONTAK_BARU`: Aguro belum pernah mengirim pesan di chat ini. Jangan buat draf; tanya Aguro dulu.",
        "",
        "## Contoh gaya chat Aguro (pesan terkirim terbaru)",
        "",
    ]
    lines += [f"- {s}" for s in style] or ["- (belum ada)"]
    lines.append("")

    for chat in ordered:
        flags = []
        if not chat.messages[-1].from_me:
            flags.append("MENUNGGU_BALASAN")
        if not chat.ever_replied:
            flags.append("KONTAK_BARU")
        kind = "grup" if chat.is_group else "pribadi"
        lines.append(f"## {chat.name} ({kind})")
        lines.append("")
        lines.append(f"- JID: `{chat.jid}`")
        lines.append(f"- Status: {', '.join(flags) if flags else 'OK'}")
        lines.append(f"- Pesan dalam periode: {len(chat.messages)}")
        lines.append("")
        for m in chat.messages:
            lines.append(f"- {m.ts.astimezone(WIB):%m-%d %H:%M} **{m.sender}**: {m.text}")
        lines.append("")

    out_file.write_text("\n".join(lines), encoding="utf-8")
    print(out_file)


if __name__ == "__main__":
    main()
