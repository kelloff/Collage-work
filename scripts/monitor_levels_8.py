#!/usr/bin/env python3
"""Ждём >=8 задач на каждом уровне 0–3, пишем статистику."""
from __future__ import annotations

import json
import os
import ssl
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HOST = os.environ.get("DEPLOY_SSH_HOST", "kellofff.me")
TARGET_PER_LEVEL = int(os.environ.get("MONITOR_MIN_PER_LEVEL", "8"))
LEVELS = (0, 1, 2, 3)
POLL_SEC = int(os.environ.get("MONITOR_POLL_SEC", "20"))
def _env_int(name: str, default: int) -> int:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


MAX_WAIT_SEC = max(300, _env_int("MONITOR_MAX_SEC", 14400))
OUT_DIR = Path(__file__).resolve().parents[1] / "POOL_MONITOR_OUTPUT"


def health() -> dict:
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(f"https://{HOST}/health", timeout=30, context=ctx) as r:
        return json.loads(r.read().decode())


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    out_path = OUT_DIR / f"levels_ge{TARGET_PER_LEVEL}_{ts}.json"
    log_path = OUT_DIR / f"levels_ge{TARGET_PER_LEVEL}_{ts}.log"

    t0_wall = time.time()
    t0 = time.monotonic()
    reached: dict[int, float | None] = {lv: None for lv in LEVELS}
    samples: list[dict] = []
    last_printed: dict[str, int] | None = None

    print(
        f"Monitor: wait until each level>={TARGET_PER_LEVEL} "
        f"(poll {POLL_SEC}s, max {MAX_WAIT_SEC // 60} min)"
    )

    with log_path.open("w", encoding="utf-8") as log:
        while time.monotonic() - t0 < MAX_WAIT_SEC:
            try:
                h = health()
            except Exception as e:
                line = f"{datetime.now(timezone.utc).isoformat()} health_err={e}\n"
                log.write(line)
                print(line.strip())
                time.sleep(POLL_SEC)
                continue

            by_raw = h.get("task_pool_by_level") or {}
            by_level = {int(k): int(v) for k, v in by_raw.items()}
            total = int(h.get("task_pool_total") or 0)
            elapsed = time.monotonic() - t0
            now = datetime.now(timezone.utc).isoformat()

            for lv in LEVELS:
                cnt = by_level.get(lv, 0)
                if reached[lv] is None and cnt >= TARGET_PER_LEVEL:
                    reached[lv] = elapsed
                    msg = f"{now} LEVEL {lv} reached {cnt}>={TARGET_PER_LEVEL} at {elapsed:.0f}s ({elapsed/60:.1f} min)"
                    log.write(msg + "\n")
                    print(msg)

            sample = {
                "utc": now,
                "elapsed_s": round(elapsed, 1),
                "total": total,
                "by_level": {str(k): by_level.get(k, 0) for k in LEVELS},
                "paused": h.get("task_pool_check_pausing_refill"),
            }
            samples.append(sample)

            all_ok = all(reached[lv] is not None for lv in LEVELS)
            if all_ok:
                break

            if sample["by_level"] != last_printed:
                print(
                    f"  {elapsed/60:5.1f} min  total={total}  "
                    + " ".join(f"L{lv}={by_level.get(lv,0)}" for lv in LEVELS)
                )
                last_printed = dict(sample["by_level"])

            time.sleep(POLL_SEC)

    elapsed_total = time.monotonic() - t0
    final_h = health()
    by_final = {
        int(k): int(v) for k, v in (final_h.get("task_pool_by_level") or {}).items()
    }

    report = {
        "host": HOST,
        "target_per_level": TARGET_PER_LEVEL,
        "started_utc": datetime.fromtimestamp(t0_wall, tz=timezone.utc).isoformat(),
        "finished_utc": datetime.now(timezone.utc).isoformat(),
        "elapsed_total_s": round(elapsed_total, 1),
        "elapsed_total_min": round(elapsed_total / 60, 2),
        "all_levels_reached": all(reached[lv] is not None for lv in LEVELS),
        "time_to_reach_s": {str(lv): reached[lv] for lv in LEVELS},
        "time_to_reach_min": {
            str(lv): round(reached[lv] / 60, 2) if reached[lv] is not None else None
            for lv in LEVELS
        },
        "order_reached": sorted(
            [(lv, reached[lv]) for lv in LEVELS if reached[lv] is not None],
            key=lambda x: x[1],
        ),
        "final_total": int(final_h.get("task_pool_total") or 0),
        "final_by_level": {str(lv): by_final.get(lv, 0) for lv in LEVELS},
        "ollama_pool_num_predict": final_h.get("ollama_pool_num_predict"),
        "ollama_pool_timeout": final_h.get("ollama_pool_timeout"),
        "samples_count": len(samples),
        "samples": samples[-80:],
    }

    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("\n=== SUMMARY ===")
    print(f"Total time: {elapsed_total/60:.1f} min")
    for lv in LEVELS:
        t = reached[lv]
        status = f"{t/60:.1f} min" if t is not None else "not yet"
        print(f"  Level {lv} >= {TARGET_PER_LEVEL}: {status} (now {by_final.get(lv,0)})")
    print(f"Report: {out_path}")
    return 0 if report["all_levels_reached"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
