#!/usr/bin/env python3
"""Clear tasks_pool.json, restart services, optionally follow backend logs."""
import os
import sys
import time

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
USER = os.environ.get("DEPLOY_SSH_USER", "root")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
POOL = "/opt/collage-work/beck/tasks_pool.json"
FOLLOW = "--follow" in sys.argv
BACKEND_ONLY = "--backend-only" in sys.argv


def run(client: paramiko.SSHClient, cmd: str, timeout: int = 120) -> str:
    print(f"\n$ {cmd}")
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    if out.strip():
        print(out.rstrip())
    if err.strip():
        print(err.rstrip(), file=sys.stderr)
    return out


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting {USER}@{HOST}...")
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)

    run(client, f"printf '%s' '[]' > {POOL}")
    run(client, f"chown www-data:www-data {POOL}")
    if not BACKEND_ONLY:
        run(client, "systemctl restart ollama && sleep 2 && systemctl is-active ollama")
    run(client, "systemctl restart collage-backend && sleep 4 && systemctl is-active collage-backend")
    run(client, "curl -sf http://127.0.0.1:8000/health")
    run(client, f"wc -c {POOL}; cat {POOL}")

    print("\n--- journalctl -u collage-backend (last 20) ---")
    run(client, "journalctl -u collage-backend -n 20 --no-pager")

    if not FOLLOW:
        client.close()
        print("\nDone. Run with --follow to stream logs (Ctrl+C to stop).")
        return 0

    print("\n=== Following collage-backend logs (task_pool / refill / generate) ===\n")
    transport = client.get_transport()
    channel = transport.open_session()
    channel.exec_command(
        "journalctl -u collage-backend -f --no-pager -n 0 "
        "| grep -E --line-buffered 'task_pool|refill|generate_tasks|ollama|ERROR|error|empty|\\+' "
        "|| journalctl -u collage-backend -f --no-pager"
    )
    channel.settimeout(0.5)
    try:
        while True:
            if channel.recv_ready():
                data = channel.recv(4096).decode("utf-8", errors="replace")
                if data:
                    print(data, end="", flush=True)
            if channel.exit_status_ready():
                break
            time.sleep(0.3)
    except KeyboardInterrupt:
        print("\n[stopped]")
    finally:
        channel.close()
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
