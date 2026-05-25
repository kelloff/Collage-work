#!/usr/bin/env python3
"""Parse pool_refill timings from production journal."""
from __future__ import annotations

import json
import os
import re
from collections import defaultdict

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
SINCE = os.environ.get("JOURNAL_SINCE", "2026-05-24 18:00:00")

RE_OK = re.compile(
    r"pool_refill: lvl=(\d+) batch attempt=(\d+) "
    r"parsed=(\d+) accepted=(\d+)/(\d+) elapsed=([\d.]+)s predict=(\d+)"
)
RE_ERR = re.compile(
    r"pool_refill: lvl=(\d+) batch attempt=(\d+) error after ([\d.]+)s: (.+)"
)


def stats(arr: list[float]) -> dict | None:
    if not arr:
        return None
    return {
        "n": len(arr),
        "min_s": round(min(arr), 1),
        "max_s": round(max(arr), 1),
        "avg_s": round(sum(arr) / len(arr), 1),
        "sum_min": round(sum(arr) / 60, 1),
    }


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=__import__("sys").stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username="root", password=PASSWORD, timeout=30)
    cmd = (
        f"journalctl -u collage-backend --since '{SINCE}' --no-pager -o cat "
        "| grep -E 'pool_refill:|task_pool: refill'"
    )
    _, stdout, _ = client.exec_command(cmd, timeout=300)
    lines = [
        ln.strip()
        for ln in stdout.read().decode("utf-8", errors="replace").splitlines()
        if ln.strip()
    ]
    client.close()

    by_lvl: dict[int, list[float]] = defaultdict(list)
    per_task: list[float] = []
    errors: list[dict] = []
    timeouts = 0
    added_total = 0

    for line in lines:
        if "refill +" in line and "added" in line:
            m = re.search(r"refill \+(\d+) added", line)
            if m:
                added_total += int(m.group(1))
        m = RE_OK.search(line)
        if m:
            lv = int(m.group(1))
            el = float(m.group(6))
            acc = int(m.group(4))
            by_lvl[lv].append(el)
            if acc:
                per_task.append(el / max(1, acc))
            continue
        m = RE_ERR.search(line)
        if m:
            err = m.group(4).strip()
            errors.append(
                {
                    "lvl": int(m.group(1)),
                    "elapsed_s": float(m.group(3)),
                    "error": err[:160],
                }
            )
            if "timed out" in err.lower():
                timeouts += 1

    out = {
        "since": SINCE,
        "journal_lines": len(lines),
        "timeouts": timeouts,
        "tasks_added_logged": added_total,
        "batch_by_level": {f"lvl{k}": stats(v) for k, v in sorted(by_lvl.items())},
        "per_accepted_task": stats(per_task),
        "errors_count": len(errors),
        "errors_last": errors[-12:],
    }
    gave_up = [ln for ln in lines if "gave up" in ln or "refill worker start" in ln]
    out["worker_events"] = gave_up[-15:]
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
