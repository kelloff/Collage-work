#!/usr/bin/env python3
"""
Тест /check_task для уровня 2: время ответа production.

  python scripts/test_check_task_timing.py
  COLLAGE_BACKEND_URL=https://kellofff.me python scripts/test_check_task_timing.py
  python scripts/test_check_task_timing.py --runs 5
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from pathlib import Path

import requests

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
DEFAULT_FIXTURE = FIXTURES_DIR / "check_task_lvl2_sum_loop.json"
DEFAULT_URL = os.getenv("COLLAGE_BACKEND_URL", "https://kellofff.me").rstrip("/")


def one_check(base_url: str, payload: dict, timeout: float) -> dict:
    url = f"{base_url}/check_task"
    t0 = time.perf_counter()
    try:
        r = requests.post(url, json=payload, timeout=timeout)
        elapsed = time.perf_counter() - t0
    except requests.RequestException as e:
        return {
            "ok": False,
            "elapsed_s": time.perf_counter() - t0,
            "error": str(e),
        }
    body: dict = {}
    try:
        body = r.json()
    except Exception:
        body = {"raw": r.text[:500]}
    return {
        "ok": r.status_code == 200,
        "status": r.status_code,
        "elapsed_s": elapsed,
        "success": body.get("success"),
        "feedback": (body.get("feedback") or "")[:200],
        "stdout": (body.get("stdout") or "")[:80],
        "error": None,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument("--fixture", default=str(DEFAULT_FIXTURE))
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=15.0)
    ap.add_argument("--max-s", type=float, default=10.0, help="warn if elapsed > this")
    ap.add_argument("--expect-ai", action="store_true", help="feedback must not be only det fallback")
    args = ap.parse_args()

    fixture_path = Path(args.fixture)
    if not fixture_path.is_file():
        print(f"Fixture not found: {fixture_path}", file=sys.stderr)
        return 1

    def load_payload() -> dict:
        with open(fixture_path, encoding="utf-8") as f:
            return json.load(f)

    payload = load_payload()
    print(f"URL: {args.url}/check_task")
    print(f"Fixture: {fixture_path.name}")
    print(f"level={payload['level']} expected_output={payload['expected_output']!r}")
    print("user_code:")
    print(payload["user_code"])
    print(f"\nRuns: {args.runs} (timeout {args.timeout}s each)\n")

    results: list[dict] = []
    for i in range(args.runs):
        res = one_check(args.url, payload, args.timeout)
        results.append(res)
        if res.get("error"):
            print(f"  #{i+1}: FAIL {res['elapsed_s']:.2f}s — {res['error']}")
        else:
            print(
                f"  #{i+1}: {res['elapsed_s']:.2f}s "
                f"HTTP {res['status']} success={res['success']} "
                f"feedback={res['feedback']!r}"
            )
        if i < args.runs - 1:
            time.sleep(1.0)

    ok = [r for r in results if r.get("ok") and not r.get("error")]
    times = [r["elapsed_s"] for r in ok]
    print()
    if not times:
        print("Нет успешных ответов.")
        return 1
    print(f"Успешных: {len(times)}/{args.runs}")
    print(f"Мин:    {min(times):.2f} s")
    print(f"Макс:   {max(times):.2f} s")
    print(f"Среднее: {statistics.mean(times):.2f} s")
    if len(times) > 1:
        print(f"Медиана: {statistics.median(times):.2f} s")
    over = [t for t in times if t > args.max_s]
    if over:
        print(f"ВНИМАНИЕ: {len(over)} ответ(ов) дольше {args.max_s}s (цель ≤10s)")
    if args.expect_ai:
        fb_all = " ".join((r.get("feedback") or "") for r in ok)
        if "ИИ недоступен" in fb_all:
            print("ВНИМАНИЕ: ответ похож на fallback без ИИ")
    all_ok = all(r.get("success") for r in ok)
    print(f"Все success=true: {all_ok}")
    return 0 if all_ok and not over else (2 if not all_ok else 3)


if __name__ == "__main__":
    sys.exit(main())
