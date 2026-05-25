#!/usr/bin/env python3
"""
Deploy beck/ to VPS over SSH/SFTP.

  set DEPLOY_SSH_PASSWORD=your_password   # Windows PowerShell
  python scripts/deploy_remote.py

Optional: DEPLOY_SSH_HOST, DEPLOY_SSH_USER, DEPLOY_REMOTE_APP
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
USER = os.environ.get("DEPLOY_SSH_USER", "root")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
LOCAL_ROOT = Path(__file__).resolve().parents[1]
REMOTE_APP = os.environ.get("DEPLOY_REMOTE_APP", "/opt/collage-work")
REMOTE_BECK = f"{REMOTE_APP}/beck"
SKIP_DIRS = {"env", "__pycache__", ".git", "tasks_pool.json"}


def _run(client: paramiko.SSHClient, cmd: str, timeout: int = 180) -> int:
    print(f"\n$ {cmd}")
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    code = stdout.channel.recv_exit_status()
    if out.strip():
        print(out.rstrip())
    if err.strip():
        print(err.rstrip(), file=sys.stderr)
    return code


def _upload_tree(sftp: paramiko.SFTPClient, local: Path, remote: str) -> None:
    try:
        sftp.stat(remote)
    except OSError:
        sftp.mkdir(remote)
    for item in local.iterdir():
        if item.name in SKIP_DIRS or item.suffix == ".pyc":
            continue
        remote_path = f"{remote}/{item.name}"
        if item.is_dir():
            _upload_tree(sftp, item, remote_path)
        else:
            sftp.put(str(item), remote_path)


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD (do not commit passwords).", file=sys.stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting {USER}@{HOST}...")
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)

    sftp = client.open_sftp()
    _upload_tree(sftp, LOCAL_ROOT / "beck", REMOTE_BECK)
    for rel in (
        "deploy/deploy_backend.sh",
        "deploy/collage-backend.service",
        "deploy/ollama-check.service",
        "deploy/ollama_runner_killer.sh",
        "deploy/ollama-runner-watchdog.service",
        "deploy/ollama-runner-watchdog.timer",
        "deploy/ollama-runner-watchdog.env.example",
    ):
        src = LOCAL_ROOT / rel
        if src.is_file():
            dst = f"{REMOTE_APP}/{rel}"
            try:
                sftp.stat(str(Path(dst).parent).replace("\\", "/"))
            except OSError:
                pass
            sftp.put(str(src), dst.replace("\\", "/"))
    sftp.put(str(LOCAL_ROOT / "beck" / "env.example"), f"{REMOTE_BECK}/env.example")
    sftp.close()

    code = _run(
        client,
        f"""
set -e
mkdir -p {REMOTE_APP}/deploy
test -f {REMOTE_BECK}/.env || cp {REMOTE_BECK}/env.example {REMOTE_BECK}/.env
test -x {REMOTE_BECK}/env/bin/python || python3 -m venv {REMOTE_BECK}/env
{REMOTE_BECK}/env/bin/pip install -q -r {REMOTE_BECK}/requirements.txt
chown -R www-data:www-data {REMOTE_BECK}
chmod 640 {REMOTE_BECK}/.env
install -m 644 {REMOTE_APP}/deploy/collage-backend.service /etc/systemd/system/collage-backend.service
chmod +x {REMOTE_APP}/deploy/ollama_runner_killer.sh
install -m 644 {REMOTE_APP}/deploy/ollama-runner-watchdog.service /etc/systemd/system/ollama-runner-watchdog.service
install -m 644 {REMOTE_APP}/deploy/ollama-runner-watchdog.timer /etc/systemd/system/ollama-runner-watchdog.timer
test -f /etc/default/ollama-runner-watchdog || install -m 644 {REMOTE_APP}/deploy/ollama-runner-watchdog.env.example /etc/default/ollama-runner-watchdog
systemctl enable ollama-runner-watchdog.timer 2>/dev/null || true
systemctl restart ollama-runner-watchdog.timer 2>/dev/null || true
systemctl daemon-reload
systemctl enable collage-backend
systemctl restart collage-backend
sleep 2
curl -sf http://127.0.0.1:8000/health
""",
    )
    client.close()
    return 0 if code == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
