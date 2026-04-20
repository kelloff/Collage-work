from typing import List, Optional, Tuple
import contextlib
import io
import json
import os
import re
import traceback

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
) -> Tuple[bool, str]:
    system_msg = (
        "Ты проверяешь решение студента по заданию на Python. "
        "Ты НЕ изменяешь код. Ты оцениваешь корректность по входным данным ниже. "
        "Верни строго JSON без markdown вида: {\"success\": true/false, \"feedback\": \"...\"}."
    )
    user_msg = (
        f"Задание: {description}\n"
        f"Ожидаемый вывод: {expected_output or '<нет>'}\n"
        f"required_patterns: {required_patterns or '<пусто>'}\n"
        f"stdout: {stdout or '<пусто>'}\n"
        f"stderr: {stderr or '<пусто>'}\n"
        f"Код студента:\n{user_code}\n"
        "Правила:\n"
        "- Если stderr непустой: success=false.\n"
        "- Если expected_output непустой: сравни stdout (нормализуй пробелы и переводы строк), чтобы совпасть со значением.\n"
        "- required_patterns: если какие-то фрагменты разделенные ';' не входят в user_code, то success=false.\n"
        "- feedback должен кратко объяснить что поправить. Не пиши готовое решение.\n"
    )
    ai_timeout_s = int(os.getenv("CHECK_TASK_AI_TIMEOUT", "20"))
    raw = ollama_chat(
        ollama_base_url=ollama_base_url,
        ollama_model=ollama_model,
        ollama_num_predict=ollama_num_predict,
        system_msg=system_msg,
        user_msg=user_msg,
        timeout_s=ai_timeout_s,
    )
    arr_match = re.search(r"\{[\s\S]*\}", raw)
    json_str = arr_match.group(0) if arr_match else raw
    data = json.loads(json_str)
    success = bool(data.get("success", False))
    feedback = str(data.get("feedback", ""))
    return success, feedback


def check_task_logic(
    req: CheckTaskRequest,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
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
    force_ai_after_det_ok: bool = level >= 2

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

    if det_success and not force_ai_after_det_ok:
        return CheckTaskResponse(
            success=True,
            feedback=det_feedback,
            stdout=stdout,
            stderr=stderr,
        )

    ai_success: bool = False
    ai_feedback: str = det_feedback
    ai_call_failed: bool = False
    env_ai: bool = os.getenv("CHECK_TASK_USE_AI", "0") != "0"
    want_ai: bool = env_ai or force_ai_after_det_ok
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
            )
        except Exception:
            ai_call_failed = True
            ai_success = False
            if force_ai_after_det_ok and det_success:
                ai_feedback = (
                    "На уровне 2+ нужна проверка ИИ, но сервис недоступен "
                    "(Ollama/сеть/таймаут). Повтори позже."
                )
            else:
                ai_feedback = det_feedback

    if stderr:
        ai_success = False

    # Уровень 2+: при падении вызова ИИ не держать игрока — принять дет. результат (как уровень 1).
    # Отключить: CHECK_TASK_AI_UNAVAILABLE_FALLBACK_DET=0
    fallback_det: bool = os.getenv("CHECK_TASK_AI_UNAVAILABLE_FALLBACK_DET", "1") != "0"
    if (
        fallback_det
        and force_ai_after_det_ok
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
