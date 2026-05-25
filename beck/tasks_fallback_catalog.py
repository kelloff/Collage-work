"""
Канонический набор из 20 учебных заданий (4 уровня × 5).

Используется:
- generate_service.fallback_generate_tasks (сервер source=fallback)
- beck/sync_task_data_gd.py → db/task_data.gd (локальный fallback Godot)
- docs/EDUCATION.md, docs/notes/note_01–03

Без заданий про дату/время/datetime — только print, if, циклы, списки.
"""
from __future__ import annotations

from typing import Any

FALLBACK_TASKS_BY_LEVEL: dict[int, list[dict[str, Any]]] = {
    0: [
        {
            "category": "easy",
            "description": 'Выведи строку "Hello, World!"',
            "expected_output": "Hello, World!",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 1,
        },
        {
            "category": "easy",
            "description": 'Создай переменную со значением "Python" и выведи её',
            "expected_output": "Python",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 1,
        },
        {
            "category": "easy",
            "description": "Создай переменную со значением 20 и выведи её",
            "expected_output": "20",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 1,
        },
        {
            "category": "easy",
            "description": "Сложи числа 2 и 3 и выведи результат",
            "expected_output": "5",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 1,
        },
        {
            "category": "easy",
            "description": "Выведи результат выражения 7*8",
            "expected_output": "56",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 1,
        },
    ],
    1: [
        {
            "category": "medium",
            "description": 'Создай переменную x = 12. Если x больше 10, выведи "Большое", иначе "Маленькое"',
            "expected_output": "Большое",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": 'Создай переменную x = 7. Если число чётное — выведи "Even", иначе "Odd"',
            "expected_output": "Odd",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": 'Создай строку s = "Python". Если строка равна "Python", выведи "Да", иначе "Нет"',
            "expected_output": "Да",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": 'Создай переменную x = -5. Если число отрицательное — выведи "Минус", иначе "Плюс"',
            "expected_output": "Минус",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": 'Создай переменную x = 9. Если число делится на 3 — выведи "Div3", иначе "No"',
            "expected_output": "Div3",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
    ],
    2: [
        {
            "category": "medium",
            "description": "Пройди по списку чисел [1,2,3] и выведи каждое",
            "expected_output": "1\n2\n3",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": "Посчитай сумму чисел от 1 до 5 с помощью цикла",
            "expected_output": "15",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": "Выведи квадраты чисел от 1 до 3",
            "expected_output": "1\n4\n9",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": "Выведи все элементы списка ['a','b','c']",
            "expected_output": "a\nb\nc",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "medium",
            "description": "Посчитай количество элементов в списке [10,20,30]",
            "expected_output": "3",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
    ],
    3: [
        {
            "category": "hard",
            "description": "Отсортируй список [5,2,9,1] и выведи результат",
            "expected_output": "[1, 2, 5, 9]",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "hard",
            "description": "Выведи только чётные числа из списка [1,2,3,4,5]",
            "expected_output": "2\n4",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "hard",
            "description": "Найди максимальное число в списке [3,7,2]",
            "expected_output": "7",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "hard",
            "description": "Найди минимальное число в списке [3,7,2]",
            "expected_output": "2",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
        {
            "category": "hard",
            "description": "Посчитай сумму элементов списка [1,2,3,4]",
            "expected_output": "10",
            "required_patterns": "",
            "check_type": "stdout_exact",
            "required_keywords": "",
            "allow_direct_print": 0,
        },
    ],
}


def catalog_tasks_for_level(level: int, count: int) -> list[dict[str, Any]]:
    lst = FALLBACK_TASKS_BY_LEVEL.get(level, [])
    return [dict(x) for x in lst[: max(0, count)]]
