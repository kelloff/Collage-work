#!/usr/bin/env python3
import json
import os
import ssl
import sys
import time
import urllib.request
from pathlib import Path

import paramiko

OUT = Path(__file__).resolve().parents[1] / "POOL_MONITOR_OUTPUT"
OUT.mkdir(exist_ok=True)
HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
PASSWORD = os.environ["DEPLOY_SSH_PASSWORD"]
POOL_PATH = "/opt/collage-work/beck/tasks_pool.json"


def health():
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(f"https://{HOST}/health", timeout=25, context=ctx) as r:
        return json.loads(r.read().decode())


def fetch_tasks():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASSWORD, timeout=30)
    with c.open_sftp().open(POOL_PATH, "r") as f:
        data = json.loads(f.read().decode())
    c.close()
    return data if isinstance(data, list) else data.get("tasks", [])


def main():
    t0 = time.time()
    start = 20
    while time.time() - t0 < 900:
        h = health()
        total = int(h["task_pool_total"])
        print(f"{int(time.time()-t0)}s total={total} {h.get('task_pool_by_level')}")
        if total > start:
            break
        time.sleep(45)
    tasks = fetch_tasks()
    out = OUT / "tasks_pool_snapshot.json"
    payload = {
        "exported_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "wait_seconds": int(time.time() - t0),
        "total": len(tasks),
        "tasks": tasks,
    }
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
