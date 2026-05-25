#!/usr/bin/env python3
"""Полный отчёт по overnight_*.json (после ночного мониторинга)."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        out = Path(__file__).resolve().parents[1] / "POOL_MONITOR_OUTPUT"
        files = sorted(out.glob("overnight_*.json"), key=lambda p: p.stat().st_mtime)
        if not files:
            print(f"Usage: {sys.argv[0]} <overnight_*.json>", file=sys.stderr)
            return 1
        path = files[-1]
        print(f"Latest: {path}\n")
    else:
        path = Path(sys.argv[1])

    data = json.loads(path.read_text(encoding="utf-8"))
    samples = data.get("samples") or []
    events = data.get("refill_events") or []
    timing = data.get("timing") or {}
    fh = data.get("final_health") or {}

    print("=" * 60)
    print("REFILL OVERNIGHT REPORT")
    print("=" * 60)
    print(f"File:     {path}")
    print(f"Host:     {data.get('host')}")
    print(f"Started:  {data.get('started_utc')}")
    print(f"Ended:    {data.get('ended_utc')}")
    print(f"Status:   {data.get('note')}")
    print(f"Wall:     {data.get('wall_elapsed_s', 0)/3600:.2f} h")
    print(f"Target:   {data.get('target')}")

    if samples:
        first, last = samples[0], samples[-1]
        t0, t1 = first.get("total", 0), last.get("total", 0)
        wall = (last.get("wall_s") or data.get("wall_elapsed_s") or 1) - (first.get("wall_s") or 0)
        rate = (t1 - t0) / (wall / 3600) if wall > 0 else 0
        print(f"\nPool: {t0} → {t1}  (+{t1-t0} за {wall/60:.0f} мин, ~{rate:.1f} задач/ч)")
        print(f"Final by_level: {last.get('by_level')}")

    if fh:
        print(f"\n/health final total={fh.get('task_pool_total')} by_level={fh.get('task_pool_by_level')}")
        print(
            f"  refill_model={fh.get('ollama_refill_model')} "
            f"pool_timeout={fh.get('ollama_pool_timeout')}s"
        )

    print("\n--- Время на batch (pool_refill elapsed) ---")
    for lv, st in sorted((timing.get("by_level") or {}).items(), key=lambda x: int(x[0])):
        print(
            f"  lvl {lv}: batches={st['batches']} tasks≈{st['tasks_approx']} "
            f"avg={st['elapsed_avg']}s min={st['elapsed_min']}s max={st['elapsed_max']}s "
            f"sum={st['elapsed_sum']/60:.1f}min"
        )

    errs = timing.get("errors") or []
    if errs:
        print(f"\n--- Ошибки ({len(errs)}) ---")
        for e in errs[-15:]:
            print(f"  lvl={e['level']} {e['elapsed_s']}s: {e['error'][:100]}")

    ok = [e for e in events if e["type"] == "batch_ok"]
    if ok:
        per_task = []
        for e in ok:
            n = max(1, e.get("accepted", 1))
            per_task.append(e["elapsed_s"] / n)
        print(f"\n--- На 1 принятую задачу (elapsed/accepted) ---")
        print(f"  avg={sum(per_task)/len(per_task):.1f}s  min={min(per_task):.1f}s  max={max(per_task):.1f}s")

    adds = [e for e in events if e["type"] == "added"]
    if adds:
        print(f"\n--- Добавления в пул: {len(adds)} записей, последнее total={adds[-1]['total']} ---")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
