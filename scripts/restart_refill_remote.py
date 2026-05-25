#!/usr/bin/env python3
"""Restart backend to relaunch refill worker (pool not cleared)."""
import os
import sys

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASSWORD, timeout=30)
    for cmd in (
        "systemctl restart collage-backend",
        "sleep 3",
        "systemctl is-active collage-backend",
        "curl -sf http://127.0.0.1:8000/health | python3 -c \"import sys,json; h=json.load(sys.stdin); print('total',h.get('task_pool_total'),h.get('task_pool_by_level'))\"",
        "journalctl -u collage-backend -n 8 --no-pager | grep -i refill || true",
    ):
        print(f"$ {cmd}")
        _, o, e = c.exec_command(cmd, timeout=60)
        print(o.read().decode().strip())
        err = e.read().decode().strip()
        if err:
            print(err, file=sys.stderr)
    c.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
