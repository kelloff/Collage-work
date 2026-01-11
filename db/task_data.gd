extends Node

var default_tasks = [
	# --- Level 0 ---
	{
		"level":0,"category":"easy",
		"description":"Выведи строку \"Hello, World!\"",
		"expected_code":"print(\"Hello, World!\")",
		"expected_output":"Hello, World!",
		"required_patterns":"print(\"Hello, World!\")"
	},
	{
		"level":0,"category":"easy",
		"description":"Создай переменную name = \"Python\" и выведи её",
		"expected_code":"name = \"Python\"\nprint(name)",
		"expected_output":"Python",
		"required_patterns":"name = \"Python\";print(name)"
	},
	{
		"level":0,"category":"easy",
		"description":"Создай переменную age = 20 и выведи её",
		"expected_code":"age = 20\nprint(age)",
		"expected_output":"20",
		"required_patterns":"age = 20;print(age)"
	},
	{
		"level":0,"category":"easy",
		"description":"Сложи числа 2 и 3 и выведи результат",
		"expected_code":"a = 2\nb = 3\nprint(a + b)",
		"expected_output":"5",
		"required_patterns":"a = 2;b = 3;print(a + b)"
	},
	{
		"level":0,"category":"easy",
		"description":"Выведи результат выражения 7*8",
		"expected_code":"print(7*8)",
		"expected_output":"56",
		"required_patterns":"print(7*8)"
	},

	# --- Level 1 ---
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = 12. Если x больше 10, выведи \"Большое\", иначе \"Маленькое\"",
		"expected_code":"x = 12\nif x > 10:\n    print(\"Большое\")\nelse:\n    print(\"Маленькое\")",
		"expected_output":"Большое",
		"required_patterns":"x = 12;if x > 10;print(\"Большое\")"
	},
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = 7. Если число чётное — выведи \"Even\", иначе \"Odd\"",
		"expected_code":"x = 7\nif x % 2 == 0:\n    print(\"Even\")\nelse:\n    print(\"Odd\")",
		"expected_output":"Odd",
		"required_patterns":"x = 7;if x % 2 == 0;print(\"Odd\")"
	},
	{
		"level":1,"category":"medium",
		"description":"Создай строку s = \"Python\". Если строка равна \"Python\", выведи \"Да\", иначе \"Нет\"",
		"expected_code":"s = \"Python\"\nif s == \"Python\":\n    print(\"Да\")\nelse:\n    print(\"Нет\")",
		"expected_output":"Да",
		"required_patterns":"s = \"Python\";if s == \"Python\";print(\"Да\")"
	},
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = -5. Если число отрицательное — выведи \"Минус\", иначе \"Плюс\"",
		"expected_code":"x = -5\nif x < 0:\n    print(\"Минус\")\nelse:\n    print(\"Плюс\")",
		"expected_output":"Минус",
		"required_patterns":"x = -5;if x < 0;print(\"Минус\")"
	},
	{
		"level":1,"category":"medium",
		"description":"Создай переменную x = 9. Если число делится на 3 — выведи \"Div3\", иначе \"No\"",
		"expected_code":"x = 9\nif x % 3 == 0:\n    print(\"Div3\")\nelse:\n    print(\"No\")",
		"expected_output":"Div3",
		"required_patterns":"x = 9;if x % 3 == 0;print(\"Div3\")"
	},

	# --- Level 2 ---
	{
		"level":2,"category":"medium",
		"description":"Пройди по списку чисел [1,2,3] и выведи каждое",
		"expected_code":"nums = [1,2,3]\nfor n in nums:\n    print(n)",
		"expected_output":"1\n2\n3",
		"required_patterns":"nums = [1,2,3];for n in nums;print(n)"
	},
	{
		"level":2,"category":"medium",
		"description":"Посчитай сумму чисел от 1 до 5 с помощью цикла",
		"expected_code":"s = 0\nfor i in range(1,6):\n    s += i\nprint(s)",
		"expected_output":"15",
		"required_patterns":"for i in range(1,6);s += i;print(s)"
	},
	{
		"level":2,"category":"medium",
		"description":"Выведи квадраты чисел от 1 до 3",
		"expected_code":"for i in range(1,4):\n    print(i*i)",
		"expected_output":"1\n4\n9",
		"required_patterns":"for i in range(1,4);print(i*i)"
	},
	{
		"level":2,"category":"medium",
		"description":"Выведи все элементы списка ['a','b','c']",
		"expected_code":"lst = ['a','b','c']\nfor x in lst:\n    print(x)",
		"expected_output":"a\nb\nc",
		"required_patterns":"lst = ['a','b','c'];for x in lst;print(x)"
	},
	{
		"level":2,"category":"medium",
		"description":"Посчитай количество элементов в списке [10,20,30]",
		"expected_code":"lst = [10,20,30]\nprint(len(lst))",
		"expected_output":"3",
		"required_patterns":"lst = [10,20,30];print(len(lst))"
	},

	# --- Level 3 ---
	{
		"level":3,"category":"hard",
		"description":"Отсортируй список [5,2,9,1] и выведи результат",
		"expected_code":"nums = [5,2,9,1]\nnums.sort()\nprint(nums)",
		"expected_output":"[1, 2, 5, 9]",
		"required_patterns":"nums = [5,2,9,1];nums.sort();print(nums)"
	},
	{
		"level":3,"category":"hard",
		"description":"Выведи только чётные числа из списка [1,2,3,4,5]",
		"expected_code":"nums = [1,2,3,4,5]\nfor n in nums:\n    if n % 2 == 0:\n        print(n)",
		"expected_output":"2\n4",
		"required_patterns":"nums = [1,2,3,4,5];if n % 2 == 0;print(n)"
	},
	{
		"level":3,"category":"hard",
		"description":"Найди максимальное число в списке [3,7,2]",
		"expected_code":"nums = [3,7,2]\nprint(max(nums))",
		"expected_output":"7",
		"required_patterns":"nums = [3,7,2];print(max(nums))"
	},
	{
		"level":3,"category":"hard",
		"description":"Найди минимальное число в списке [3,7,2]",
		"expected_code":"nums = [3,7,2]\nprint(min(nums))",
		"expected_output":"2",
		"required_patterns":"nums = [3,7,2];print(min(nums))"
	},
	{
		"level":3,"category":"hard",
		"description":"Посчитай сумму элементов списка [1,2,3,4]",
		"expected_code":"nums = [1,2,3,4]\nprint(sum(nums))",
		"expected_output":"10",
		"required_patterns":"nums = [1,2,3,4];print(sum(nums))"
	}
]
