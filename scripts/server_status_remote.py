#!/usr/bin/env python3
"""Quick server diagnostics + optional backend restart."""
import json
import os
import sys
import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
USER = os.environ.get("DEPLOY_SSH_USER", "root")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
RESTART = "--restart" in sys.argv


def run(client: paramiko.SSHClient, cmd: str, timeout: int = 90) -> tuple[int, str, str]:
    print(f"\n$ {cmd}")
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    code = stdout.channel.recv_exit_status()
    if out.strip():
        print(out.rstrip())
    if err.strip():
        print(err.rstrip(), file=sys.stderr)
    return code, out, err


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting {USER}@{HOST}...")
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)

    run(client, "systemctl is-active ollama collage-backend nginx || true")
    run(client, "free -h | head -2; uptime")
    run(client, "curl -sf http://127.0.0.1:8000/health")
    run(client, "wc -c /opt/collage-work/beck/tasks_pool.json; ls -la /opt/collage-work/beck/tasks_pool.json 2>/dev/null || true")
    run(client, "grep -E 'TASK_POOL|OLLAMA|GENERATE|WARMUP' /opt/collage-work/beck/.env 2>/dev/null | head -20")
    run(client, "journalctl -u collage-backend -n 30 --no-pager")
    run(client, "journalctl -u ollama -n 12 --no-pager")

    if RESTART:
        print("\n=== Restarting collage-backend ===")
        run(client, "systemctl restart collage-backend && sleep 4 && systemctl is-active collage-backend")
        run(client, "curl -sf http://127.0.0.1:8000/health")
        run(client, "sleep 8 && journalctl -u collage-backend -n 20 --no-pager")

    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
