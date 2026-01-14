extends Node

var default_tasks = [
	# --- Level 0 ---
	{
		"level":0,"category":"easy",
		"description":"Выведи строку \"Hello, World!\"",
		"expected_output":"Hello, World!",
		"check_type":"stdout_exact",
		"required_keywords":"print",
		"allow_direct_print":1
	},
	{
		"level":0,"category":"easy",
		"description":"Создай переменную и выведи её (например name = \"Python\")",
		"expected_output":"Python",
		"check_type":"variable_print",
		"required_keywords":"print;=",
		"allow_direct_print":0
	},
	{
		"level":0,"category":"easy",
		"description":"Создай переменную и выведи её (например age = 20)",
		"expected_output":"20",
		"check_type":"variable_print",
		"required_keywords":"print;=",
		"allow_direct_print":0
	},
	{
		"level":0,"category":"easy",
		"description":"Сложи числа 2 и 3 и выведи результат",
		"expected_output":"5",
		"check_type":"numeric_logic",
		"required_keywords":"print;+",
		"allow_direct_print":0
	},
	{
		"level":0,"category":"easy",
		"description":"Выведи результат выражения 7*8",
		"expected_output":"56",
		"check_type":"numeric_logic",
		"required_keywords":"print;*",
		"allow_direct_print":0
	},

	# --- Level 1 ---
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = 12. Если x больше 10, выведи \"Большое\", иначе \"Маленькое\"",
		"expected_output":"Большое",
		"check_type":"condition_logic",
		"required_keywords":"if;print",
		"allow_direct_print":0
	},
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = 7. Если число чётное — выведи \"Even\", иначе \"Odd\"",
		"expected_output":"Odd",
		"check_type":"condition_logic",
		"required_keywords":"if;print",
		"allow_direct_print":0
	},
	{
		"level":1,"category":"medium",
		"description":"Создай строку s = \"Python\". Если строка равна \"Python\", выведи \"Да\", иначе \"Нет\"",
		"expected_output":"Да",
		"check_type":"condition_logic",
		"required_keywords":"if;print",
		"allow_direct_print":0
	},
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = -5. Если число отрицательное — выведи \"Минус\", иначе \"Плюс\"",
		"expected_output":"Минус",
		"check_type":"condition_logic",
		"required_keywords":"if;print",
		"allow_direct_print":0
	},
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = 9. Если число делится на 3 — выведи \"Div3\", иначе \"No\"",
		"expected_output":"Div3",
		"check_type":"condition_logic",
		"required_keywords":"if;print",
		"allow_direct_print":0
	},

	# --- Level 2 ---
	{
		"level":2,"category":"medium",
		"description":"Пройди по списку чисел [1,2,3] и выведи каждое",
		"expected_output":"1\n2\n3",
		"check_type":"loop_logic",
		"required_keywords":"for;print",
		"allow_direct_print":0
	},
	{
		"level":2,"category":"medium",
		"description":"Посчитай сумму чисел от 1 до 5 с помощью цикла",
		"expected_output":"15",
		"check_type":"loop_logic",
		"required_keywords":"for;print;+",
		"allow_direct_print":0
	},
	{
		"level":2,"category":"medium",
		"description":"Выведи квадраты чисел от 1 до 3",
		"expected_output":"1\n4\n9",
		"check_type":"loop_logic",
		"required_keywords":"for;print;*",
		"allow_direct_print":0
	},
	{
		"level":2,"category":"medium",
		"description":"Выведи все элементы списка ['a','b','c']",
		"expected_output":"a\nb\nc",
		"check_type":"loop_logic",
		"required_keywords":"for;print",
		"allow_direct_print":0
	},
	{
		"level":2,"category":"medium",
		"description":"Посчитай количество элементов в списке [10,20,30]",
		"expected_output":"3",
		"check_type":"list_logic",
		"required_keywords":"len;print",
		"allow_direct_print":0
	},

	# --- Level 3 ---
	{
		"level":3,"category":"hard",
		"description":"Отсортируй список [5,2,9,1] и выведи результат",
		"expected_output":"[1, 2, 5, 9]",
		"check_type":"list_logic",
		"required_keywords":"sort;print",
		"allow_direct_print":0
	},
	{
		"level":3,"category":"hard",
		"description":"Выведи только чётные числа из списка [1,2,3,4,5]",
		"expected_output":"2\n4",
		"check_type":"loop_logic",
		"required_keywords":"for;if;print",
		"allow_direct_print":0
	},
	{
		"level":3,"category":"hard",
		"description":"Найди максимальное число в списке [3,7,2]",
		"expected_output":"7",
		"check_type":"list_logic",
		"required_keywords":"max;print",
		"allow_direct_print":0
	},
	{
		"level":3,"category":"hard",
		"description":"Найди минимальное число в списке [3,7,2]",
		"expected_output":"2",
		"check_type":"list_logic",
		"required_keywords":"min;print",
		"allow_direct_print":0
	},
	{
		"level":3,"category":"hard",
		"description":"Посчитай сумму элементов списка [1,2,3,4]",
		"expected_output":"10",
		"check_type":"list_logic",
		"required_keywords":"sum;print",
		"allow_direct_print":0
	}
]
