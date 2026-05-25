#!/usr/bin/env python3
"""Measure one pool-level Ollama generation on server (via SSH)."""
from __future__ import annotations

import os
import sys

import paramiko

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
PASSWORD = os.environ.get("DEPLOY_SSH_PASSWORD", "")

REMOTE = r"""
import json, time, urllib.request
payload=json.dumps({
  "model":"qwen2.5:0.5b","stream":False,"format":"json",
  "messages":[
    {"role":"system","content":"JSON tasks only {\"tasks\":[...]}"},
    {"role":"user","content":"Сгенерируй РОВНО 3 задач уровня 0. JSON tasks."}
  ],
  "options":{"num_predict":200,"num_ctx":2048,"temperature":0.1}
})
t0=time.time()
req=urllib.request.Request(
  "http://127.0.0.1:11434/api/chat",
  data=payload.encode(),
  headers={"Content-Type":"application/json"},
)
try:
  r=urllib.request.urlopen(req, timeout=130)
  body=r.read().decode("utf-8","replace")
  print("OK", round(time.time()-t0,1), "bytes", len(body))
  print(body[:300])
except Exception as e:
  print("ERR", round(time.time()-t0,1), e)
"""


def main() -> int:
    if not PASSWORD:
        print("Set DEPLOY_SSH_PASSWORD", file=sys.stderr)
        return 1
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASSWORD, timeout=30)
    sftp = c.open_sftp()
    path = "/tmp/test_pool_refill.py"
    with sftp.open(path, "w") as f:
        f.write(REMOTE)
    sftp.close()
    _, stdout, stderr = c.exec_command(f"python3 {path}", timeout=150)
    print(stdout.read().decode())
    err = stderr.read().decode()
    if err:
        print(err, file=sys.stderr)
    c.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
