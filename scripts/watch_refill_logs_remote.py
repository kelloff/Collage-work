#!/usr/bin/env python3
"""
Смотреть логи refill/pool на сервере (SSH + journalctl).

  set DEPLOY_SSH_PASSWORD=...
  python scripts/watch_refill_logs_remote.py          # последние 60 строк
  python scripts/watch_refill_logs_remote.py --follow # онлайн (Ctrl+C)
"""
from __future__ import annotations

import os
import sys

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
USER = os.environ.get("DEPLOY_SSH_USER", "root")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
LINES = int(os.environ.get("LOG_LINES", "80"))
FOLLOW = "--follow" in sys.argv or "-f" in sys.argv

# PowerShell ломает grep с | — фильтруем на сервере одной строкой bash
CMD_TAIL = (
    f"journalctl -u collage-backend -n {LINES} --no-pager "
    "-o cat | grep -iE 'task_pool|pool_refill|refill|add_tasks|bulk catalog' || true"
)
CMD_FOLLOW = (
    "journalctl -u collage-backend -f -o cat "
    "| grep -iE --line-buffered 'task_pool|pool_refill|refill|add_tasks|bulk catalog'"
)


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)

    cmd = CMD_FOLLOW if FOLLOW else CMD_TAIL
    print(f"=== {HOST} ===\n$ {cmd}\n")
    _, stdout, stderr = client.exec_command(cmd, timeout=None if FOLLOW else 120)
    if FOLLOW:
        try:
            while True:
                line = stdout.readline()
                if not line:
                    break
                print(line, end="")
        except KeyboardInterrupt:
            print("\n[stopped]")
    else:
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        if out.strip():
            print(out.rstrip())
        if err.strip():
            print(err.rstrip(), file=sys.stderr)

    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
