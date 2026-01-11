extends Node

func normalize_code(code: String) -> String:
	var cleaned = code.strip_edges().replace("\n", " ").replace("\t", " ")
	while cleaned.find("  ") != -1:
		cleaned = cleaned.replace("  ", " ")
	return cleaned

func check_user_solution(user_code: String, task: Dictionary, actual_output: String, output_label: RichTextLabel) -> bool:
	var normalized_code = normalize_code(user_code)
	var expected_output = task.get("expected_output", "").strip_edges()
	var result_message = ""

	# 1. Проверка вывода
	if actual_output.strip_edges() != expected_output:
		result_message = "❌ Вывод неверный. Ожидалось: %s, получено: %s" % [expected_output, actual_output]
		output_label.text = result_message
		return false

	# 2. Проверка обязательных паттернов
	var required_patterns = task.get("required_patterns", "")
	if required_patterns != "":
		var patterns = required_patterns.split(";")
		for p in patterns:
			var normalized_pattern = normalize_code(p)
			if normalized_code.find(normalized_pattern) == -1:
				result_message = "❌ В решении отсутствует обязательный элемент: %s" % p
				output_label.text = result_message
				return false

	# Всё прошло успешно
	result_message = "✅ Задание выполнено правильно!"
	output_label.text = result_message
	return true
