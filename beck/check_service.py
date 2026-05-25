from typing import List, Optional, Tuple
import contextlib
import io
import json
import os
import re
import traceback

import requests

from models import CheckTaskRequest, CheckTaskResponse
from ollama_client import ollama_chat


def _normalize_out(text: str) -> str:
    return (text or "").replace("\r", "").strip()


def _normalize_for_lenient_compare(text: str) -> str:
    t = (text or "").replace("\r", "").strip()
    lines = [ln.strip() for ln in t.split("\n")]
    t = "\n".join(lines).strip()
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r"\s*([,;:!?])\s*", r"\1", t)
    return t.strip()


def _normalize_code_for_rules(code: str) -> str:
    cleaned = (code or "").strip().replace("\n", " ").replace("\t", " ")
    while "  " in cleaned:
        cleaned = cleaned.replace("  ", " ")
    return cleaned


def _looks_like_direct_print(user_code: str, expected_output: str) -> bool:
    code = _normalize_code_for_rules(user_code)
    if "print" not in code:
        return False
    exp = (expected_output or "").strip()
    if not exp:
        return False
    if f"\"{exp}\"" in code or f"'{exp}'" in code:
        return True
    if exp.isdigit() and f"print({exp})" in code.replace(" ", ""):
        return True
    return False


def _build_mismatch_feedback(expected: str, actual: str) -> str:
    exp_lines = _normalize_out(expected).split("\n") if _normalize_out(expected) else []
    act_lines = _normalize_out(actual).split("\n") if _normalize_out(actual) else []
    exp_preview = _normalize_out(expected)[:180] or "<пусто>"
    act_preview = _normalize_out(actual)[:180] or "<пусто>"
    if len(exp_lines) != len(act_lines):
        return (
            "Вывод не совпадает: разное количество строк.\n"
            f"Ожидалось строк: {len(exp_lines)}, получено: {len(act_lines)}.\n"
            f"Ожидалось: {exp_preview}\n"
            f"Получено: {act_preview}"
        )
    return (
        "Вывод не совпадает с ожидаемым (проверь пробелы, запятые и переносы строк).\n"
        f"Ожидалось: {exp_preview}\n"
        f"Получено: {act_preview}"
    )


def _looks_like_variable_greeting_task(description: str) -> bool:
    d = (description or "").lower()
    return (
        ("заменив слово" in d and "переменную" in d)
        or ("выведи строку" in d and "переменн" in d and "привет" in d)
        or ("переменную name" in d and "привет" in d)
    )


def _run_user_code_safely(code: str) -> Tuple[str, str]:
    safe_builtins = {
        "print": print,
        "range": range,
        "len": len,
        "int": int,
        "float": float,
        "str": str,
        "bool": bool,
        "list": list,
        "dict": dict,
        "set": set,
        "tuple": tuple,
        "min": min,
        "max": max,
        "sum": sum,
        "abs": abs,
        "enumerate": enumerate,
    }
    globals_env = {"__builtins__": safe_builtins}
    locals_env = {}

    out_buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(out_buf):
            exec(code, globals_env, locals_env)
        return out_buf.getvalue(), ""
    except Exception:
        return out_buf.getvalue(), traceback.format_exc(limit=1)


def _ai_check_solution_via_ollama(
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    description: str,
    expected_output: str,
    required_patterns: str,
    user_code: str,
    stdout: str,
    stderr: str,
    *,
    check_base_url: Optional[str] = None,
    check_model: Optional[str] = None,
    check_num_predict: Optional[int] = None,
    check_timeout_s: Optional[int] = None,
    check_extra_options: Optional[dict] = None,
) -> Tuple[bool, str]:
    base_url = (check_base_url or ollama_base_url).strip()
    model = (check_model or ollama_model).strip()
    num_predict = int(check_num_predict or min(128, ollama_num_predict))
    desc_short = (description or "")[:400]
    code_short = (user_code or "")[:1200]
    stdout_short = (stdout or "")[:200]
    system_msg = (
        "Проверка Python-решения. Не меняй код. "
        'JSON: {"success":bool,"feedback":"..."}'
    )
    user_msg = (
        f"Задание: {desc_short}\n"
        f"Ожидаемый вывод: {expected_output or '-'}\n"
        f"patterns: {required_patterns or '-'}\n"
        f"stdout: {stdout_short or '-'}\n"
        f"stderr: {(stderr or '')[:120] or '-'}\n"
        f"Код:\n{code_short}\n"
        "stderr→success false. Сравни stdout с ожидаемым. "
        "patterns через ';' должны быть в коде. Краткий feedback без готового решения."
    )
    ai_timeout_s = min(
        10,
        int(check_timeout_s or os.getenv("CHECK_TASK_AI_TIMEOUT", "10")),
    )
    retry = os.getenv("CHECK_TASK_AI_RETRY", "0") != "0"
    budgets = [ai_timeout_s]
    if retry and ai_timeout_s >= 7:
        budgets = [max(5, ai_timeout_s - 3), 3]

    raw = ""
    last_err: Optional[Exception] = None
    for tmo in budgets:
        try:
            raw = ollama_chat(
                ollama_base_url=base_url,
                ollama_model=model,
                ollama_num_predict=num_predict,
                system_msg=system_msg,
                user_msg=user_msg,
                timeout_s=tmo,
                force_json=True,
                extra_options=check_extra_options,
            )
            last_err = None
            break
        except Exception as e:
            last_err = e
    if last_err is not None:
        raise last_err
    arr_match = re.search(r"\{[\s\S]*\}", raw)
    json_str = arr_match.group(0) if arr_match else raw
    data = json.loads(json_str)
    success = bool(data.get("success", False))
    feedback = str(data.get("feedback", ""))
    return success, feedback


def _ollama_check_reachable(base_url: str, timeout_s: float = 2.0) -> bool:
    url = f"{(base_url or '').rstrip('/')}/api/tags"
    if not url.startswith("http"):
        return False
    try:
        r = requests.get(url, timeout=timeout_s)
        return r.status_code == 200
    except Exception:
        return False


def _det_fail_is_stdout_mismatch(feedback: str) -> bool:
    fb = (feedback or "").lower()
    return "не совпадает" in fb or "разное количество строк" in fb


def _check_ollama_extra_options(num_ctx: int) -> dict:
    d: dict = {}
    if num_ctx > 0:
        d["num_ctx"] = num_ctx
    return d


def check_task_logic(
    req: CheckTaskRequest,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    *,
    ollama_check_base_url: str = "",
    ollama_check_model: str = "",
    ollama_check_num_predict: int = 128,
    ollama_check_timeout: int = 25,
    ollama_check_num_ctx: int = 2048,
) -> CheckTaskResponse:
    desc = req.description.strip()
    expected = (req.expected_output or "").strip()
    code = req.user_code.strip()
    patterns_raw = (req.required_patterns or "").strip()
    allow_direct_print = int(getattr(req, "allow_direct_print", 0))

    if not code:
        return CheckTaskResponse(
            success=False,
            feedback="Код пустой. Напиши решение для задания.",
            stdout="",
            stderr="",
        )

    stdout, stderr = _run_user_code_safely(code)
    det_success: bool = False
    det_feedback: str = ""
    level: int = int(getattr(req, "level", 1) or 1)
    # Уровень 2+: ИИ только если дет. проверка не прошла (см. CHECK_TASK_FAST_DET_OK).
    want_ai_for_level: bool = level >= 2
    fast_det_ok: bool = os.getenv("CHECK_TASK_FAST_DET_OK", "1") != "0"

    if stderr:
        det_success = False
        err_line = (stderr or "").strip().splitlines()
        short_err = err_line[-1] if err_line else "Неизвестная ошибка"
        det_feedback = f"Ошибка выполнения: {short_err}"
    else:
        if expected:
            if _looks_like_variable_greeting_task(desc):
                actual_norm = _normalize_for_lenient_compare(stdout)
                if re.match(r"^Привет,\S+!?$", actual_norm) or re.match(
                    r"^Привет,\s*\S+!?$", stdout.strip()
                ):
                    det_success = True
                    det_feedback = "Решение корректное."
                else:
                    det_success = False
                    det_feedback = "Ожидался вывод вида: Привет, <имя>!"
            elif _normalize_for_lenient_compare(stdout) != _normalize_for_lenient_compare(
                expected
            ):
                det_success = False
                det_feedback = _build_mismatch_feedback(expected, stdout)
            else:
                det_success = True
                det_feedback = "Решение корректное."
                if allow_direct_print == 0 and _looks_like_direct_print(code, expected):
                    has_logic = any(x in code for x in ["=", "if", "for", "while"])
                    if not has_logic:
                        det_success = False
                        det_feedback = (
                            "Нельзя просто печатать готовый ответ. "
                            "Используй переменные/условия/циклы."
                        )
                if not det_success and det_feedback.startswith("Нельзя просто печатать"):
                    pass
                elif det_success:
                    missing: List[str] = []
                    if patterns_raw:
                        for p in patterns_raw.split(";"):
                            p = p.strip()
                            if not p:
                                continue
                            if p not in code:
                                missing.append(p)
                    if missing:
                        det_success = False
                        det_feedback = (
                            "В коде не хватает обязательных фрагментов:\n"
                            + "\n".join(f"- {m}" for m in missing)
                        )
                    else:
                        det_success = True
                        det_feedback = "Решение корректное."
        else:
            det_success = True
            det_feedback = "Решение принято (ошибок выполнения нет)."

    env_ai: bool = os.getenv("CHECK_TASK_USE_AI", "0") != "0"
    ai_mode = os.getenv("CHECK_TASK_AI_MODE", "fail_only").strip().lower()
    always_ai_l2 = ai_mode in ("always", "all", "1", "yes")
    skip_ai_det_ok: bool = (
        fast_det_ok
        and det_success
        and want_ai_for_level
        and not env_ai
        and not always_ai_l2
    )
    if det_success and (not want_ai_for_level or skip_ai_det_ok):
        return CheckTaskResponse(
            success=True,
            feedback=det_feedback,
            stdout=stdout,
            stderr=stderr,
        )

    ai_success: bool = False
    ai_feedback: str = det_feedback
    ai_call_failed: bool = False
    want_ai: bool = env_ai or (want_ai_for_level and not skip_ai_det_ok)
    skip_on_det_fail: bool = os.getenv("CHECK_TASK_SKIP_AI_ON_DET_FAIL", "1") != "0"
    skip_on_stdout_only: bool = (
        os.getenv("CHECK_TASK_SKIP_AI_ON_STDOUT_MISMATCH", "1") != "0"
        and _det_fail_is_stdout_mismatch(det_feedback)
    )
    if want_ai and not env_ai and not always_ai_l2:
        if skip_on_det_fail and not det_success and det_feedback:
            want_ai = False
        elif skip_on_stdout_only and not det_success and not stderr:
            want_ai = False
    check_base = (ollama_check_base_url or ollama_base_url).strip()
    if want_ai and check_base and not _ollama_check_reachable(check_base):
        ai_call_failed = True
        want_ai = False
    if want_ai:
        try:
            ai_success, ai_feedback = _ai_check_solution_via_ollama(
                ollama_base_url=ollama_base_url,
                ollama_model=ollama_model,
                ollama_num_predict=ollama_num_predict,
                description=desc,
                expected_output=expected,
                required_patterns=patterns_raw,
                user_code=code,
                stdout=stdout,
                stderr=stderr,
                check_base_url=ollama_check_base_url or None,
                check_model=ollama_check_model or None,
                check_num_predict=ollama_check_num_predict,
                check_timeout_s=ollama_check_timeout,
                check_extra_options=_check_ollama_extra_options(ollama_check_num_ctx),
            )
        except Exception:
            ai_call_failed = True
            ai_success = False
            if want_ai_for_level and det_success:
                ai_feedback = (
                    "На уровне 2+ нужна проверка ИИ, но сервис недоступен "
                    "(Ollama/сеть/таймаут). Повтори позже."
                )
            else:
                ai_feedback = det_feedback

    if stderr:
        ai_success = False

    # При падении ИИ: если дет. уже ОК — засчитать (не ждать повторов).
    # Отключить: CHECK_TASK_AI_UNAVAILABLE_FALLBACK_DET=0
    fallback_det: bool = os.getenv("CHECK_TASK_AI_UNAVAILABLE_FALLBACK_DET", "1") != "0"
    if (
        fallback_det
        and want_ai_for_level
        and det_success
        and want_ai
        and not ai_success
        and ai_call_failed
    ):
        note = " (ИИ недоступен — засчитано по правилам задания.)"
        return CheckTaskResponse(
            success=True,
            feedback=(det_feedback or "Решение корректное.") + note,
            stdout=stdout,
            stderr=stderr,
        )

    final_success: bool = (ai_success if want_ai else det_success)
    final_feedback: str = (ai_feedback if want_ai else det_feedback) or det_feedback
    return CheckTaskResponse(
        success=final_success,
        feedback=final_feedback,
        stdout=stdout,
        stderr=stderr,
    )
