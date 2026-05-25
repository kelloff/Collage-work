#!/usr/bin/env python3
"""Monitor pool refill from ~20 tasks to target; save tasks_pool.json snapshot."""
from __future__ import annotations

import json
import os
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
POOL_PATH = "/opt/collage-work/beck/tasks_pool.json"
TARGET = int(os.environ.get("REFILL_MONITOR_TARGET", "300"))
START_AT = int(os.environ.get("REFILL_MONITOR_START_AT", "20"))
POLL_SEC = int(os.environ.get("REFILL_MONITOR_POLL_SEC", "30"))
MAX_WAIT_SEC = int(os.environ.get("REFILL_MONITOR_MAX_SEC", "21600"))
OUT_DIR = Path(__file__).resolve().parents[1] / "POOL_MONITOR_OUTPUT"


def health() -> dict:
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(f"https://{HOST}/health", timeout=25, context=ctx) as r:
        return json.loads(r.read().decode())


def fetch_pool_json() -> list | dict:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)
    sftp = client.open_sftp()
    with sftp.open(POOL_PATH, "r") as f:
        raw = f.read().decode("utf-8", errors="replace")
    client.close()
    data = json.loads(raw)
    if isinstance(data, dict) and "tasks" in data:
        return data["tasks"]
    if isinstance(data, list):
        return data
    return []


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_path = OUT_DIR / f"refill_monitor_{ts}.log"
    out_json = OUT_DIR / f"tasks_pool_{ts}.json"
    report_path = OUT_DIR / f"refill_report_{ts}.json"

    t0_wall = time.time()
    started = False
    t_start: float | None = None
    last_total = -1
    samples: list[dict] = []

    print(f"Monitor: start_at>={START_AT}, target={TARGET}, poll={POLL_SEC}s")

    with log_path.open("w", encoding="utf-8") as log:
        while time.time() - t0_wall < MAX_WAIT_SEC:
            try:
                h = health()
            except Exception as e:
                line = f"{datetime.now(timezone.utc).isoformat()} health error: {e}\n"
                log.write(line)
                print(line.strip())
                time.sleep(POLL_SEC)
                continue

            total = int(h.get("task_pool_total") or 0)
            by_level = h.get("task_pool_by_level") or {}
            paused = h.get("task_pool_check_pausing_refill")
            now = datetime.now(timezone.utc).isoformat()

            if not started and total >= START_AT:
                started = True
                t_start = time.time()
                log.write(f"{now} TIMER START total={total} by_level={by_level}\n")
                print(f"TIMER START @ total={total} {by_level}")

            sample = {
                "utc": now,
                "total": total,
                "by_level": by_level,
                "check_pausing_refill": paused,
                "elapsed_since_start_s": round(time.time() - t_start, 1) if t_start else None,
            }
            samples.append(sample)

            if total != last_total:
                line = f"{now} total={total} by_level={by_level} paused={paused}"
                if t_start:
                    line += f" elapsed={time.time()-t_start:.0f}s"
                log.write(line + "\n")
                print(line)
                last_total = total

            if started and total >= TARGET:
                elapsed = time.time() - (t_start or t0_wall)
                log.write(f"{now} TARGET REACHED total={total} elapsed_s={elapsed:.1f}\n")
                print(f"DONE: {total} tasks in {elapsed/60:.1f} min ({elapsed:.0f}s)")
                break

            time.sleep(POLL_SEC)
        else:
            elapsed = time.time() - (t_start or t0_wall)
            print(f"Timeout after {elapsed/60:.1f} min, last total={last_total}")

    tasks = fetch_pool_json()
    ai_tasks = [t for t in tasks if isinstance(t, dict) and not t.get("_from_catalog")]
    out_payload = {
        "exported_at_utc": datetime.now(timezone.utc).isoformat(),
        "host": HOST,
        "target": TARGET,
        "start_threshold": START_AT,
        "final_total": len(tasks) if isinstance(tasks, list) else 0,
        "ai_generated_count": len(ai_tasks),
        "catalog_count": (len(tasks) - len(ai_tasks)) if isinstance(tasks, list) else 0,
        "elapsed_seconds": round(time.time() - (t_start or t0_wall), 1) if started else None,
        "samples": samples,
        "tasks": tasks,
    }
    out_json.write_text(json.dumps(out_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    report = {
        k: v
        for k, v in out_payload.items()
        if k != "tasks"
    }
    report["tasks_preview"] = [
        {
            "level": t.get("level"),
            "description": (t.get("description") or "")[:120],
            "expected_output": (t.get("expected_output") or "")[:80],
        }
        for t in (tasks[:40] if isinstance(tasks, list) else [])
    ]
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\nSaved:\n  {out_json}\n  {report_path}\n  {log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
