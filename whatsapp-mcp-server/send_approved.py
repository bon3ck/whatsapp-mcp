#!/usr/bin/env python3
"""Send WhatsApp replies that Aguro has approved.

Only messages listed in approval files (``outbox/approved/*.json`` in the
"WA Summary" Google Drive folder) are sent. Nothing is drafted or sent on
its own: a file lands in ``approved/`` only after Aguro approves the drafts.

Order: urgent+important first, then urgent, then important, then the rest.
Between two sends the script waits a random 30-60 seconds.

Each item is sent at most once: sent ids are kept in a local ledger, so a
file that syncs twice or is re-run never sends a message twice.

Approval file format::

    {
      "approved_by": "Aguro",
      "approved_at": "2026-11-02T08:00:00+07:00",
      "items": [
        {"id": "2026-11-02-03", "recipient": "6281234567890@s.whatsapp.net",
         "chat_name": "Budi", "priority": "urgent_important",
         "message": "siap bro, jam 10 ya"}
      ]
    }

priority is one of: urgent_important, urgent, important, normal.

Usage:
    python send_approved.py --outbox "G:\\My Drive\\WA Summary\\outbox"
    python send_approved.py --outbox ... --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

API_URL = os.environ.get("WA_API_URL", "http://localhost:8080/api/send")
LEDGER = Path(__file__).resolve().parent.parent / "whatsapp-bridge" / "store" / "sent-ledger.json"
PRIORITY_ORDER = {"urgent_important": 0, "urgent": 1, "important": 2, "normal": 3}
WIB = timezone(timedelta(hours=7))
MIN_GAP, MAX_GAP = 30, 60


def now() -> str:
    return datetime.now(WIB).isoformat(timespec="seconds")


def load_ledger() -> dict:
    try:
        return json.loads(LEDGER.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_ledger(ledger: dict) -> None:
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    tmp = LEDGER.with_suffix(".tmp")
    tmp.write_text(json.dumps(ledger, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(LEDGER)


def send(recipient: str, message: str) -> tuple[bool, str]:
    data = json.dumps({"recipient": recipient, "message": message}).encode("utf-8")
    req = urllib.request.Request(API_URL, data=data, method="POST",
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.loads(resp.read().decode("utf-8") or "{}")
            return bool(body.get("success")), str(body.get("message", ""))
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:300]}"
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        return False, f"{type(e).__name__}: {e}"


def valid_item(item) -> str | None:
    if not isinstance(item, dict):
        return "item is not an object"
    for key in ("id", "recipient", "message"):
        if not isinstance(item.get(key), str) or not item[key].strip():
            return f"missing {key}"
    if "@" not in item["recipient"]:
        return "recipient must be a WhatsApp JID"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outbox", default=os.environ.get("WA_OUTBOX_DIR", "outbox"))
    ap.add_argument("--dry-run", action="store_true", help="Show what would be sent, send nothing")
    args = ap.parse_args()

    outbox = Path(args.outbox)
    approved_dir, done_dir, result_dir = outbox / "approved", outbox / "done", outbox / "sent"
    for d in (approved_dir, done_dir, result_dir):
        d.mkdir(parents=True, exist_ok=True)

    lock = LEDGER.with_name("send.lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        if time.time() - lock.stat().st_mtime < 3 * 3600:
            print("Another send run is in progress; exiting.")
            return 0
        lock.unlink(missing_ok=True)  # stale lock from a crashed run
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    os.close(fd)

    try:
        ledger = load_ledger()
        files = sorted(approved_dir.glob("*.json"))
        # Gather every approved item across files, then send in priority order.
        queue = []
        for f in files:
            try:
                batch = json.loads(f.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError, OSError) as e:
                print(f"Skipping {f.name} for now (not readable yet: {e})")
                continue
            items = batch.get("items") if isinstance(batch, dict) else None
            if not isinstance(items, list):
                print(f"Skipping {f.name}: no items list")
                continue
            for item in items:
                queue.append((f, item))

        queue.sort(key=lambda fi: PRIORITY_ORDER.get(fi[1].get("priority", "normal") if isinstance(fi[1], dict) else "normal", 3))

        results: dict[Path, list] = {f: [] for f, _ in queue}
        sent_any = False
        for f, item in queue:
            problem = valid_item(item)
            if problem:
                results[f].append({"item": item, "status": "invalid", "detail": problem})
                continue
            if item["id"] in ledger:
                results[f].append({"id": item["id"], "status": "already_sent", "at": ledger[item["id"]]["at"]})
                continue
            if sent_any and not args.dry_run:
                gap = random.randint(MIN_GAP, MAX_GAP)
                print(f"Waiting {gap}s...")
                time.sleep(gap)
            label = f"[{item.get('priority', 'normal')}] {item.get('chat_name', item['recipient'])}"
            if args.dry_run:
                print(f"DRY RUN would send {label}: {item['message'][:80]}")
                results[f].append({"id": item["id"], "status": "dry_run"})
                continue
            ok, detail = send(item["recipient"], item["message"])
            sent_any = True
            print(f"{'SENT' if ok else 'FAILED'} {label}: {detail}")
            status = "sent" if ok else "failed"
            results[f].append({"id": item["id"], "chat_name": item.get("chat_name"), "status": status,
                               "detail": detail, "at": now()})
            if ok:
                ledger[item["id"]] = {"at": now(), "recipient": item["recipient"]}
                save_ledger(ledger)

        if args.dry_run:
            return 0
        for f, res in results.items():
            failed = [r for r in res if r["status"] == "failed"]
            (result_dir / f"{f.stem}.result.json").write_text(
                json.dumps({"file": f.name, "finished_at": now(), "results": res}, ensure_ascii=False, indent=1),
                encoding="utf-8")
            # Failed items stay in approved/ for the next run; the ledger stops resends of the rest.
            if not failed:
                shutil.move(str(f), str(done_dir / f.name))
        return 0
    finally:
        lock.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
