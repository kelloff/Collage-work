#!/usr/bin/env python3
"""Merge production pool/ollama keys into server beck/.env and restart backend."""
from __future__ import annotations

import os
import re
import sys

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
USER = os.environ.get("DEPLOY_SSH_USER", "root")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")
ENV_PATH = "/opt/collage-work/beck/.env"
POOL_PATH = "/opt/collage-work/beck/tasks_pool.json"

REMOVE_ENV_KEYS = frozenset(
    {
        "TASK_POOL_DAY_CAP_TOTAL",
        "TASK_POOL_DAY_START_HOUR",
        "TASK_POOL_DAY_END_HOUR",
        "TASK_POOL_TZ",
    }
)

PRODUCTION_LINES = {
    "GENERATE_FALLBACK_ON_MISS": "1",
    "OLLAMA_WARMUP_ENABLED": "0",
    "OLLAMA_NUM_PREDICT": "768",
    "OLLAMA_REFILL_BASE_URL": "http://127.0.0.1:11434",
    "OLLAMA_REFILL_MODEL": "qwen2.5:3b",
    "OLLAMA_REFILL_HEAVY_MODEL": "qwen2.5:3b",
    "OLLAMA_REFILL_HEAVY_FROM_LEVEL": "4",
    "OLLAMA_REFILL_HEAVY_TIMEOUT": "480",
    "TASK_POOL_REFILL_HEAVY_CHUNK": "1",
    "OLLAMA_POOL_MODEL": "qwen2.5:3b",
    "OLLAMA_POOL_NUM_PREDICT": "0",
    "OLLAMA_POOL_MIN_PREDICT": "220",
    "OLLAMA_POOL_PREDICT_PER_TASK": "110",
    "OLLAMA_POOL_TEMPERATURE": "0.1",
    "OLLAMA_POOL_SINGLE_TIMEOUT": "480",
    "OLLAMA_POOL_NUM_CTX": "2048",
    "TASK_POOL_REFILL_MAX_OLLAMA_ATTEMPTS": "2",
    "TASK_POOL_REFILL_PAUSE_SEC": "2",
    "TASK_POOL_REFILL_ZERO_ADDED_WAIT": "8",
    "OLLAMA_MULTI_NUM_PREDICT": "2400",
    "OLLAMA_SINGLE_TIMEOUT": "600",
    "OLLAMA_MULTI_TIMEOUT": "900",
    "TASK_POOL_ENABLED": "1",
    "TASK_POOL_TARGET_PER_LEVEL": "75",
    "TASK_POOL_MIN_TOTAL": "300",
    "TASK_POOL_MAX_TOTAL": "320",
    "TASK_POOL_REFILL_CHUNK": "1",
    "TASK_POOL_BATCH_MIN_ACCEPT": "1",
    "TASK_POOL_REFILL_RETRY_SEC": "12",
    "TASK_POOL_FAST_EMPTY_RETRY": "1",
    "TASK_POOL_BULK_CATALOG_SEED": "0",
    "TASK_POOL_RELAX_BELOW_TOTAL": "0",
    "OLLAMA_CHECK_WARMUP_ON_START": "0",
    "TASK_POOL_CATALOG_ON_MISS": "1",
    "TASK_POOL_REFILL_MAX_EMPTY_STREAK": "200",
    "TASK_POOL_REFILL_GAVE_UP_RESTART_SEC": "300",
    "TASK_SIMILAR_MAX_PER_GROUP": "3",
    "TASK_MULTI_ONESHOT_FIRST": "1",
    "OLLAMA_CHECK_BASE_URL": "http://127.0.0.1:11435",
    "OLLAMA_CHECK_MODEL": "qwen2.5:0.5b",
    "OLLAMA_CHECK_NUM_PREDICT": "64",
    "OLLAMA_CHECK_NUM_CTX": "1024",
    "CHECK_TASK_AI_TIMEOUT": "10",
    "CHECK_TASK_AI_MODE": "fail_only",
    "CHECK_TASK_AI_RETRY": "0",
    "CHECK_TASK_FAST_DET_OK": "1",
    "OLLAMA_PAUSE_POOL_DURING_CHECK": "1",
    "CHECK_TASK_SKIP_AI_ON_STDOUT_MISMATCH": "1",
    "CHECK_TASK_SKIP_AI_ON_DET_FAIL": "1",
}


def merge_env(content: str, updates: dict[str, str]) -> str:
    lines = content.splitlines()
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=", line)
        if m and m.group(1) in REMOVE_ENV_KEYS:
            continue
        if m and m.group(1) in updates:
            key = m.group(1)
            out.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            out.append(line)
    for key, val in updates.items():
        if key not in seen:
            out.append(f"{key}={val}")
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1
    clear_pool = os.getenv("CLEAR_POOL", "1") != "0"

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)
    sftp = client.open_sftp()
    try:
        with sftp.open(ENV_PATH, "r") as f:
            raw = f.read().decode("utf-8", errors="replace")
    except OSError:
        with sftp.open(ENV_PATH.replace(".env", "env.example"), "r") as f:
            raw = f.read().decode("utf-8", errors="replace")
    merged = merge_env(raw, PRODUCTION_LINES)
    with sftp.open(ENV_PATH, "w") as f:
        f.write(merged)
    sftp.close()

    cmds = [
        f"chown www-data:www-data {ENV_PATH} && chmod 640 {ENV_PATH}",
    ]
    if clear_pool:
        cmds.extend(
            [
                f"printf '%s' '[]' > {POOL_PATH}",
                f"chown www-data:www-data {POOL_PATH}",
            ]
        )
    cmds.extend(
        [
            "systemctl restart collage-backend && sleep 5 && systemctl is-active collage-backend",
            "curl -sf http://127.0.0.1:8000/health",
            "journalctl -u collage-backend -n 12 --no-pager | grep -iE 'task_pool|refill|seed' || true",
        ]
    )
    for cmd in cmds:
        print(f"\n$ {cmd}")
        _, stdout, stderr = client.exec_command(cmd, timeout=180)
        out = stdout.read().decode()
        err = stderr.read().decode()
        if out.strip():
            print(out.rstrip())
        if err.strip():
            print(err.rstrip(), file=sys.stderr)
    client.close()
    print("\nProduction .env applied (no day/night cap, refill chunk=4).")
    if clear_pool:
        print("tasks_pool.json cleared.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
