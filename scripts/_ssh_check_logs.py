#!/usr/bin/env python3
import os
import paramiko

p = os.environ["DEPLOY_SSH_PASSWORD"]
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("kellofff.me", username="root", password=p, timeout=30)
cmds = [
    "systemctl is-active ollama ollama-check collage-backend",
    "curl -sf --max-time 3 http://127.0.0.1:11435/api/tags | head -c 200 || echo CHECK_DOWN",
    "curl -sf --max-time 3 http://127.0.0.1:11434/api/tags | head -c 80 || echo MAIN_DOWN",
    "journalctl -u ollama-check -n 25 --no-pager",
    "journalctl -u ollama -n 15 --no-pager | grep -E '11435|check|500|error' || true",
    "grep -E 'OLLAMA_CHECK|CHECK_TASK' /opt/collage-work/beck/.env",
]
for cmd in cmds:
    print("\n$", cmd[:100])
    _, o, e = c.exec_command(cmd, timeout=45)
    print(o.read().decode())
    err = e.read().decode()
    if err.strip():
        print(err)
c.close()
