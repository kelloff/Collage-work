extends Node

func normalize_code(code: String) -> String:
	var cleaned = code.strip_edges().replace("\n", " ").replace("\t", " ")
	while cleaned.find("  ") != -1:
		cleaned = cleaned.replace("  ", " ")
	return cleaned

func _contains_all(code: String, keywords: Array) -> bool:
	for kw in keywords:
		if kw == "":
			continue
		if code.find(kw) == -1:
			return false
	return true

func _looks_like_direct_print(user_code: String, expected_output: String) -> bool:
	var code = normalize_code(user_code)
	if code.find("print") == -1:
		return false
	var literal := "\"%s\"" % expected_output
	if code.find(literal) != -1:
		return true
	if expected_output.is_valid_int():
		if code.find("print(" + expected_output + ")") != -1:
			return true
	return false

# --- сравнение вывода ---
func _compare_output(actual: String, expected: String) -> bool:
	var a = actual.strip_edges().replace("\r","").replace("\n","")
	var e = expected.strip_edges().replace("\r","").replace("\n","")
	return a == e

func _validate_by_type(check_type: String, user_code: String, expected_output: String, actual_output: String) -> bool:
	var code = normalize_code(user_code)
	match check_type:
		"stdout_exact":
			return _compare_output(actual_output, expected_output)

		"numeric_logic":
			var has_op := (code.find("+") != -1 or code.find("-") != -1 or code.find("*") != -1 or code.find("/") != -1 or code.find("%") != -1)
			return has_op and _compare_output(actual_output, expected_output)

		"condition_logic":
			var has_if := code.find("if") != -1
			var has_print := code.find("print") != -1
			return has_if and has_print and _compare_output(actual_output, expected_output)

		"loop_logic":
			var has_loop := (code.find("for") != -1 or code.find("while") != -1)
			var has_print := code.find("print") != -1
			var has_if := code.find("if") != -1
			if expected_output == "2\n4":
				# для задания "чётные числа" обязательно нужен if
				return has_loop and has_if and has_print and _compare_output(actual_output, expected_output)
			return has_loop and has_print and _compare_output(actual_output, expected_output)

		"list_logic":
			var has_list_ops := (
				code.find("sort") != -1 or
				code.find("sorted") != -1 or
				code.find("max") != -1 or
				code.find("min") != -1 or
				code.find("sum") != -1 or
				code.find("+=") != -1 or
				(code.find("for") != -1 and code.find("+") != -1)
			)
			return has_list_ops and _compare_output(actual_output, expected_output)

		"variable_print":
			var has_assign := code.find("=") != -1
			var has_print := code.find("print") != -1
			return has_assign and has_print and _compare_output(actual_output, expected_output)

		_:
			return _compare_output(actual_output, expected_output)

func check_user_solution(user_code: String, task: Dictionary, actual_output: String, output_label: RichTextLabel) -> bool:
	var normalized_code = normalize_code(user_code)
	var expected_output = task.get("expected_output", "").strip_edges()
	var required_keywords = task.get("required_keywords", "")
	var check_type = task.get("check_type", "stdout_exact")
	var allow_direct_print = int(task.get("allow_direct_print", 0))

	# 1) Проверка логики по типу
	var logic_ok := _validate_by_type(check_type, user_code, expected_output, actual_output)
	if not logic_ok:
		output_label.text = "❌ Логика решения не соответствует заданию или вывод неверный.\nОжидалось: %s\nПолучено: %s" % [expected_output, actual_output]
		return false

	# 2) Запрет прямого print ответа (но разрешаем если есть переменная/условие/цикл)
	if allow_direct_print == 0 and _looks_like_direct_print(user_code, expected_output):
		if not (user_code.find("=") != -1 or user_code.find("if") != -1 or user_code.find("for") != -1 or user_code.find("while") != -1):
			output_label.text = "❌ Нельзя просто выводить готовый ответ. Используй переменные, условия или циклы."
			return false

	# 3) Проверка ключевых слов
	if required_keywords != "":
		var keywords = required_keywords.split(";")
		if not _contains_all(normalized_code, keywords):
			output_label.text = "❌ В решении отсутствуют необходимые конструкции: %s" % required_keywords
			return false

	output_label.text = "✅ Задание выполнено правильно!"
	return true
