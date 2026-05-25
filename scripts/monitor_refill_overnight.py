#!/usr/bin/env python3
"""
Ночной мониторинг refill: health + journalctl → POOL_MONITOR_OUTPUT/.

  set DEPLOY_SSH_PASSWORD=...
  python scripts/monitor_refill_overnight.py

Остановка: Ctrl+C или достижение REFILL_MONITOR_TARGET (300).
После остановки: scripts/summarize_refill_monitor.py <report.json>
"""
from __future__ import annotations

import json
import os
import re
import ssl
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
USER = os.environ.get("DEPLOY_SSH_USER", "root")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
TARGET = int(os.environ.get("REFILL_MONITOR_TARGET", "300"))
POLL_SEC = int(os.environ.get("REFILL_MONITOR_POLL_SEC", "60"))
JOURNAL_POLL_SEC = int(os.environ.get("REFILL_MONITOR_JOURNAL_SEC", "120"))
MAX_WAIT_SEC = int(os.environ.get("REFILL_MONITOR_MAX_SEC", "50400"))  # ~14 h
OUT_DIR = Path(__file__).resolve().parents[1] / "POOL_MONITOR_OUTPUT"

RE_BATCH_OK = re.compile(
    r"pool_refill: lvl=(\d+) batch attempt=(\d+) "
    r"parsed=(\d+) accepted=(\d+)/(\d+) elapsed=([\d.]+)s predict=(\d+)"
)
RE_BATCH_ERR = re.compile(
    r"pool_refill: lvl=(\d+) batch attempt=(\d+) error after ([\d.]+)s: (.+)"
)
RE_REFILL_START = re.compile(
    r"task_pool: refill lvl=(\d+) ask=(\d+).*?(?:model=([\w.:]+))?"
)
RE_ADDED = re.compile(r"task_pool: refill \+(\d+) added \(batch=(\d+)\), total=(\d+)")
RE_EMPTY = re.compile(r"task_pool: empty batch #(\d+)")


def health() -> dict:
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(f"https://{HOST}/health", timeout=30, context=ctx) as r:
        return json.loads(r.read().decode())


def journal_since(client: paramiko.SSHClient, since_iso: str) -> str:
    cmd = (
        f"journalctl -u collage-backend --since '{since_iso}' --no-pager -o cat "
        "| grep -iE 'pool_refill:|task_pool: refill|empty batch|from catalog|paused|error after'"
    )
    _, stdout, _ = client.exec_command(cmd, timeout=180)
    return stdout.read().decode("utf-8", errors="replace")


def parse_journal(text: str, seen: set[str]) -> list[dict]:
    events: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line in seen:
            continue
        m = RE_BATCH_OK.search(line)
        if m:
            seen.add(line)
            events.append(
                {
                    "type": "batch_ok",
                    "level": int(m.group(1)),
                    "attempt": int(m.group(2)),
                    "parsed": int(m.group(3)),
                    "accepted": int(m.group(4)),
                    "asked": int(m.group(5)),
                    "elapsed_s": float(m.group(6)),
                    "predict": int(m.group(7)),
                    "raw": line,
                }
            )
            continue
        m = RE_BATCH_ERR.search(line)
        if m:
            seen.add(line)
            events.append(
                {
                    "type": "batch_error",
                    "level": int(m.group(1)),
                    "attempt": int(m.group(2)),
                    "elapsed_s": float(m.group(3)),
                    "error": m.group(4).strip(),
                    "raw": line,
                }
            )
            continue
        m = RE_REFILL_START.search(line)
        if m:
            seen.add(line)
            events.append(
                {
                    "type": "refill_start",
                    "level": int(m.group(1)),
                    "ask": int(m.group(2)),
                    "model": (m.group(3) or "").strip() or None,
                    "raw": line,
                }
            )
            continue
        m = RE_ADDED.search(line)
        if m:
            seen.add(line)
            events.append(
                {
                    "type": "added",
                    "added": int(m.group(1)),
                    "batch": int(m.group(2)),
                    "total": int(m.group(3)),
                    "raw": line,
                }
            )
            continue
        m = RE_EMPTY.search(line)
        if m:
            seen.add(line)
            events.append({"type": "empty_batch", "streak": int(m.group(1)), "raw": line})
    return events


def aggregate_timing(events: list[dict]) -> dict:
    by_level: dict[int, list[float]] = {}
    errors: list[dict] = []
    for e in events:
        if e["type"] == "batch_ok":
            by_level.setdefault(e["level"], []).append(e["elapsed_s"])
        elif e["type"] == "batch_error":
            errors.append(e)
    stats = {}
    for lv, times in sorted(by_level.items()):
        stats[str(lv)] = {
            "batches": len(times),
            "tasks_approx": sum(
                ev.get("accepted", 0)
                for ev in events
                if ev["type"] == "batch_ok" and ev["level"] == lv
            ),
            "elapsed_min": round(min(times), 1),
            "elapsed_max": round(max(times), 1),
            "elapsed_avg": round(sum(times) / len(times), 1),
            "elapsed_sum": round(sum(times), 1),
        }
    return {"by_level": stats, "errors": errors}


def save_report(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    report_path = OUT_DIR / f"overnight_{run_id}.json"
    log_path = OUT_DIR / f"overnight_{run_id}.log"

    since_iso = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    t0 = time.time()
    last_journal = 0.0
    seen_lines: set[str] = set()
    all_events: list[dict] = []
    samples: list[dict] = []

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)

    print(f"Overnight monitor → {report_path}")
    print(f"target={TARGET} poll={POLL_SEC}s max={MAX_WAIT_SEC/3600:.1f}h since={since_iso}")

    def flush_report(note: str) -> None:
        payload = {
            "run_id": run_id,
            "host": HOST,
            "note": note,
            "started_utc": since_iso,
            "ended_utc": datetime.now(timezone.utc).isoformat(),
            "wall_elapsed_s": round(time.time() - t0, 1),
            "target": TARGET,
            "samples": samples,
            "refill_events": all_events,
            "timing": aggregate_timing(all_events),
        }
        try:
            payload["final_health"] = health()
        except Exception as e:
            payload["final_health_error"] = str(e)
        save_report(report_path, payload)

    try:
        with log_path.open("w", encoding="utf-8") as log:
            log.write(f"start {since_iso} target={TARGET}\n")
            while time.time() - t0 < MAX_WAIT_SEC:
                now = datetime.now(timezone.utc).isoformat()
                try:
                    h = health()
                except Exception as e:
                    msg = f"{now} health_error {e}\n"
                    log.write(msg)
                    print(msg.strip())
                    time.sleep(POLL_SEC)
                    continue

                total = int(h.get("task_pool_total") or 0)
                by_level = h.get("task_pool_by_level") or {}
                paused = h.get("task_pool_check_pausing_refill")
                sample = {
                    "utc": now,
                    "wall_s": round(time.time() - t0, 1),
                    "total": total,
                    "by_level": by_level,
                    "check_pausing_refill": paused,
                }
                samples.append(sample)

                line = f"{now} total={total} by_level={by_level} paused={paused}"
                log.write(line + "\n")
                print(line)

                if time.time() - last_journal >= JOURNAL_POLL_SEC:
                    last_journal = time.time()
                    try:
                        jtext = journal_since(client, since_iso)
                        new_ev = parse_journal(jtext, seen_lines)
                        if new_ev:
                            all_events.extend(new_ev)
                            for e in new_ev:
                                if e["type"] == "batch_ok":
                                    print(
                                        f"  → lvl={e['level']} +{e['accepted']}/{e['asked']} "
                                        f"in {e['elapsed_s']:.1f}s"
                                    )
                                elif e["type"] == "batch_error":
                                    print(
                                        f"  → lvl={e['level']} ERROR {e['elapsed_s']:.1f}s "
                                        f"{e['error'][:60]}"
                                    )
                        flush_report("running")
                    except Exception as e:
                        log.write(f"{now} journal_error {e}\n")
                        print(f"journal_error: {e}")

                if total >= TARGET:
                    flush_report("target_reached")
                    print(f"DONE: {total} >= {TARGET}")
                    return 0

                time.sleep(POLL_SEC)

        flush_report("max_wait_timeout")
        print(f"Stopped: max wait {MAX_WAIT_SEC/3600:.1f}h")
        return 0
    except KeyboardInterrupt:
        flush_report("keyboard_interrupt")
        print("\nStopped by user (partial report saved)")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
