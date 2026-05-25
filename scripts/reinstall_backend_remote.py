#!/usr/bin/env python3
"""
Полная переустановка бэкенда на VPS (без остановки ollama / ollama-check).

  set DEPLOY_SSH_PASSWORD=...
  python scripts/reinstall_backend_remote.py

Останавливает только collage-backend, удаляет /opt/collage-work/beck,
заливает код заново, новый venv, .env из env.example + production, пустой пул.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    if not os.environ.get("DEPLOY_SSH_PASSWORD"):
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1

    host = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
    remote_beck = "/opt/collage-work/beck"

    import paramiko

    pw = os.environ["DEPLOY_SSH_PASSWORD"]
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting root@{host}...")
    client.connect(host, username="root", password=pw, timeout=30)

    wipe = f"""
set -e
echo "==> Stop collage-backend only (ollama stays up)"
systemctl stop collage-backend || true
echo "==> Remove old beck (code, venv, pool, pycache)"
rm -rf {remote_beck}
mkdir -p {remote_beck}
echo "==> Wipe done"
"""
    print(wipe)
    _, stdout, stderr = client.exec_command(wipe, timeout=120)
    print(stdout.read().decode())
    err = stderr.read().decode()
    if err.strip():
        print(err, file=sys.stderr)
    if stdout.channel.recv_exit_status() != 0:
        client.close()
        return 2
    client.close()

    print("\n==> Fresh deploy (upload + venv + restart)\n")
    env = os.environ.copy()
    r = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "deploy_remote.py")],
        env=env,
        cwd=str(ROOT),
    )
    if r.returncode != 0:
        return r.returncode

    print("\n==> Production .env + empty pool\n")
    env["CLEAR_POOL"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    r2 = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "apply_production_env_remote.py")],
        env=env,
        cwd=str(ROOT),
    )
    return r2.returncode


if __name__ == "__main__":
    raise SystemExit(main())
