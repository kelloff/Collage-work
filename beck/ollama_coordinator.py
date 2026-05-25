"""
Refill (:11434, большая модель) vs /check_task (:11435, малая модель).

Пока идёт проверка кода:
- refill на паузе;
- текущий HTTP-запрос к Ollama refill прерывается;
- после проверки — повтор последней попытки refill и фоновый worker.
"""
from __future__ import annotations

import os
import threading
import time
from typing import Callable, Optional

_refill_abort = threading.Event()
_refill_lock = threading.Lock()
_pending_refill: Optional[tuple[int, int]] = None  # level, count
_active_abort_event: Optional[threading.Event] = None
_schedule_refill_fn: Optional[Callable[[], None]] = None
_retry_pending_fn: Optional[Callable[[int, int], None]] = None


class RefillPaused(Exception):
    """Refill прерван из-за /check_task."""


def pause_pool_during_check_enabled() -> bool:
    return os.getenv("OLLAMA_PAUSE_POOL_DURING_CHECK", "1") != "0"


def set_refill_hooks(
    schedule_refill: Callable[[], None],
    retry_pending: Callable[[int, int], None],
) -> None:
    global _schedule_refill_fn, _retry_pending_fn
    _schedule_refill_fn = schedule_refill
    _retry_pending_fn = retry_pending


def is_refill_aborted() -> bool:
    return _refill_abort.is_set()


def get_refill_abort_event() -> threading.Event:
    return _refill_abort


def register_active_refill(abort_event: threading.Event) -> None:
    global _active_abort_event
    with _refill_lock:
        _active_abort_event = abort_event


def clear_active_refill(abort_event: threading.Event) -> None:
    global _active_abort_event
    with _refill_lock:
        if _active_abort_event is abort_event:
            _active_abort_event = None


def mark_refill_attempt(level: int, count: int) -> None:
    global _pending_refill
    with _refill_lock:
        _pending_refill = (int(level), max(1, int(count)))


def clear_refill_attempt() -> None:
    global _pending_refill
    with _refill_lock:
        _pending_refill = None


def take_pending_refill() -> Optional[tuple[int, int]]:
    global _pending_refill
    with _refill_lock:
        p = _pending_refill
        _pending_refill = None
        return p


def pause_refill_for_check() -> None:
    if not pause_pool_during_check_enabled():
        return
    _refill_abort.set()
    with _refill_lock:
        ev = _active_abort_event
    if ev is not None:
        ev.set()
    print("ollama_coordinator: refill paused (check_task)")


def resume_refill_after_check() -> None:
    if not pause_pool_during_check_enabled():
        return
    _refill_abort.clear()
    pending = take_pending_refill()
    if pending:
        lv, n = pending
        print(f"ollama_coordinator: retry pending refill lvl={lv} n={n}")
        if _retry_pending_fn:
            _retry_pending_fn(lv, n)
    if _schedule_refill_fn:
        _schedule_refill_fn()
    print("ollama_coordinator: refill resumed")


def wait_until_refill_allowed(*, poll_s: float = 0.2) -> None:
    """Ждёт, пока не идёт /check_task (перед новым запросом refill)."""
    if not pause_pool_during_check_enabled():
        return
    import task_pool

    while task_pool.is_check_active() or is_refill_aborted():
        time.sleep(poll_s)


def wait_if_check_active(*, poll_s: float = 0.25, max_wait_s: float = 600.0) -> None:
    """Совместимость: refill worker ждёт конца проверки."""
    if not pause_pool_during_check_enabled():
        return
    import task_pool

    deadline = time.monotonic() + max_wait_s
    while task_pool.is_check_active():
        if time.monotonic() >= deadline:
            print("ollama_coordinator: check still active after max_wait")
            break
        time.sleep(poll_s)
