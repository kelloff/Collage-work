extends RefCounted
class_name TaskClientFilter
## Строгая фильтрация заданий на клиенте (зеркало beck/task_filters.py для игрока).

const _DATE_KEYWORDS: PackedStringArray = [
	"текущ", "сегодня", "нынешн", "datetime", "strftime", "календар",
	"дату", "дата", "дате", "даты", "now()", "import time",
	"from datetime", "import datetime", "сейчас", "число месяца", "день недели",
]

const _META_DESC: PackedStringArray = [
	"фонов", "пул игр", "пул игры", "json", "tasks:[", "объектов", "ровно n",
	"учебные задания python", "верни только", "формат:", "без markdown",
	"уровня сложности", "напиши программу", "создай задание", "пример:",
	"с уровнем", "для пула", "фоновый",
]

const _FORBIDDEN_ADVANCED: PackedStringArray = [
	"while ", "while(", "def ", "input(", "import ", "class ", "lambda ",
	"try:", "except", "open(", "with open",
]


static func filter_playable_tasks(tasks: Array, max_per_level: int = -1) -> Array:
	var out: Array = []
	var per_level: Dictionary = {}
	for raw in tasks:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = raw
		if not is_playable_task(t):
			continue
		var lv: int = int(t.get("level", 0))
		if max_per_level > 0:
			var n: int = int(per_level.get(lv, 0))
			if n >= max_per_level:
				continue
			per_level[lv] = n + 1
		if _is_duplicate_in_batch(t, out):
			continue
		out.append(t)
	return out


static func count_by_level(tasks: Array) -> Dictionary:
	var c: Dictionary = {}
	for t in tasks:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var lv: int = int(t.get("level", 0))
		c[lv] = int(c.get(lv, 0)) + 1
	return c


static func missing_per_level(tasks: Array, levels: Array, per_level: int) -> Dictionary:
	var have := count_by_level(tasks)
	var need: Dictionary = {}
	for lv_raw in levels:
		var lv: int = int(lv_raw)
		var gap: int = per_level - int(have.get(lv, 0))
		if gap > 0:
			need[lv] = gap
	return need


static func is_playable_task(task: Dictionary) -> bool:
	if task.is_empty():
		return false
	if _is_date_related(task):
		return false
	if _is_prompt_echo(task):
		return false
	var lv: int = int(task.get("level", 0))
	if _uses_forbidden_advanced(task, lv):
		return false
	var desc: String = str(task.get("description", "")).strip_edges()
	var out: String = str(task.get("expected_output", "")).strip_edges()
	if desc.length() < 8:
		return false
	if _is_vague_description(desc):
		return false
	if _is_invalid_output(out):
		return false
	if not _description_output_coherent(desc, out, lv):
		return false
	return true


static func _parts(task: Dictionary) -> Array:
	return [
		str(task.get("description", "")).strip_edges(),
		str(task.get("expected_output", "")).strip_edges(),
		str(task.get("required_patterns", "")).strip_edges(),
	]


static func _is_date_related(task: Dictionary) -> bool:
	var p: Array = _parts(task)
	for part in p:
		var t: String = str(part).to_lower()
		for kw in _DATE_KEYWORDS:
			if kw in t:
				return true
	return false


static func _is_invalid_output(out: String) -> bool:
	var o: String = out.strip_edges()
	if o.is_empty():
		return true
	var low: String = o.to_lower()
	if low in ["...", "…", "....", "-", "?", "???", "n/a", "none", "null", "todo"]:
		return true
	if o.length() <= 2 and not _has_digit(o) and o not in ["Да", "Нет", "Odd", "Even"]:
		if o in ["..", "…", "?"]:
			return true
	if o.contains("\n"):
		return true
	if o.begins_with("[") and o.ends_with("]"):
		if "'" in o or "\"" in o:
			return true
		if _regex_search("^\\[[\\d,\\s\\-]+\\]$", o):
			return false
		return true
	if o.contains("\n"):
		var lines: PackedStringArray = []
		for ln in o.split("\n"):
			var s: String = ln.strip_edges()
			if not s.is_empty():
				lines.append(s)
		if lines.is_empty():
			return true
		var all_digits := true
		var all_letters := true
		for ln in lines:
			if not _regex_search("^\\d+$", ln):
				all_digits = false
			if not _regex_search("^[a-zA-Z]$", ln):
				all_letters = false
			if _regex_search("^-\\s", ln):
				return true
		if all_digits or all_letters:
			return false
		if lines.size() > 10:
			return true
		return false
	return false


static func _is_vague_description(desc: String) -> bool:
	var d: String = desc.strip_edges().to_lower()
	if d.is_empty():
		return true
	const ACTIONS: PackedStringArray = [
		"выведи", "посчитай", "сложи", "умнож", "раздел", "вычти", "найди",
		"создай", "напиши", "определи", "провер", "сравни", "отсортиру", "print",
	]
	var has_action := false
	for a in ACTIONS:
		if a in d:
			has_action = true
			break
	if not has_action:
		return true
	if _regex_search("(?i)^(сделай|сделайте|создай|создайте)\\s+\\d+\\s+задач", d):
		return true
	if _regex_search("(?i)^\\d+\\s+(прост|задач)", d):
		return true
	if "массив tasks" in d or "массиве tasks" in d:
		return true
	if _regex_search("(?i)\\blevel=\\d+", d) and "задач" in d:
		return true
	return false


static func _has_digit(s: String) -> bool:
	for i in s.length():
		if s[i].is_valid_int():
			return true
	return false


static func _regex_escape(text: String) -> String:
	var out := ""
	const SPECIAL := "\\.*?+[]{}()|^$-"
	for i in text.length():
		var c: String = text[i]
		if c in SPECIAL:
			out += "\\" + c
		else:
			out += c
	return out


static func _regex_search(pattern: String, text: String) -> RegExMatch:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return null
	return re.search(text)


static func _is_prompt_echo(task: Dictionary) -> bool:
	var desc: String = str(task.get("description", "")).strip_edges()
	var out: String = str(task.get("expected_output", "")).strip_edges()
	if desc.is_empty():
		return true
	var d: String = desc.to_lower()
	if _regex_search("(?i)^сгенерируй(?:те)?\\s+(?:ровно\\s+)?\\d*\\s*задач", d):
		return true
	if _regex_search("(?i)^сгенерируй(?:те)?\\s+.*\\b(json|пул|массив tasks)\\b", d):
		return true
	if _regex_search("(?i)^(сделай|сделайте|создай|создайте)\\s+\\d+\\s+задач", d):
		return true
	if "массив tasks" in d or "массиве tasks" in d:
		return true
	if _regex_search("(?i)\\blevel=\\d+", d) and "задач" in d:
		return true
	for m in _META_DESC:
		if m in d:
			return true
	if "задач" in d and ("пул" in d or "фонов" in d):
		return true
	if _regex_search("уровн[ьяе]\\s*[0-3]?\\s*$", d) and d.length() < 80:
		return true
	return false


static func _uses_forbidden_advanced(task: Dictionary, level: int) -> bool:
	var desc: String = str(task.get("description", ""))
	var pat: String = str(task.get("required_patterns", ""))
	var blob: String = (desc + " " + pat).to_lower()
	for k in _FORBIDDEN_ADVANCED:
		if k in blob:
			return true
	if level <= 1 and (_regex_search("\\bfor\\b", blob) or "range(" in blob or "[" in desc):
		return true
	if level <= 0 and (_regex_search("\\bif\\b", blob) or _regex_search("\\belse\\b", blob)):
		return true
	return false


static func _ints_in_description(desc: String) -> Array:
	var nums: Array = []
	var re := RegEx.new()
	if re.compile("\\b(\\d+)\\b") != OK:
		return nums
	for m in re.search_all(desc):
		if m.get_group_count() >= 1:
			nums.append(int(m.get_string(1)))
	return nums


static func _description_output_coherent(desc: String, out: String, level: int) -> bool:
	var o: String = out.strip_edges()
	if desc.is_empty() or o.is_empty():
		return false
	var d: String = desc.to_lower()
	var lv: int = int(level)

	if lv <= 0 and ("сложен" in d or "сложи" in d or "сумм" in d) and "списк" not in d:
		if _ints_in_description(desc).size() < 2:
			return false

	var add_m: RegExMatch = _regex_search("слож\\S*\\s+(?:числ\\w*\\s+)?(\\d+)\\s+и\\s+(\\d+)", d)
	if add_m:
		return o == str(int(add_m.get_string(1)) + int(add_m.get_string(2)))

	var mul_m: RegExMatch = _regex_search("(\\d+)\\s*[*×]\\s*(\\d+)", desc)
	if mul_m:
		return o == str(int(mul_m.get_string(1)) * int(mul_m.get_string(2)))

	if "сумм" in d or "sum(" in d:
		var bm: RegExMatch = _regex_search("\\[([^\\]]+)\\]", desc)
		if bm:
			var parts: PackedStringArray = bm.get_string(1).split(",")
			var sum_n: int = 0
			var any_num := false
			for p in parts:
				var ps: String = p.strip_edges()
				if ps.is_valid_int() or (ps.begins_with("-") and ps.substr(1).is_valid_int()):
					sum_n += int(ps)
					any_num = true
			if any_num and o.is_valid_int():
				return o == str(sum_n)

	if lv <= 0 and _regex_search("^-?\\d+$", o):
		var nums: Array = _ints_in_description(desc)
		if not nums.is_empty():
			var found := false
			for n in nums:
				if str(n) == o:
					found = true
					break
			if not found and not _regex_search("\\b" + _regex_escape(o) + "\\b", desc):
				if add_m and str(int(add_m.get_string(1)) + int(add_m.get_string(2))) == o:
					return true
				if mul_m and str(int(mul_m.get_string(1)) * int(mul_m.get_string(2))) == o:
					return true
				return false
	return true


static func _norm_out(out: String) -> String:
	return out.strip_edges().to_lower().replace("  ", " ")


static func _is_duplicate_in_batch(candidate: Dictionary, accepted: Array) -> bool:
	var lv: int = int(candidate.get("level", 0))
	var out_k: String = _norm_out(str(candidate.get("expected_output", "")))
	var desc: String = str(candidate.get("description", "")).strip_edges().to_lower()
	for ex in accepted:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		if int(ex.get("level", 0)) != lv:
			continue
		if _norm_out(str(ex.get("expected_output", ""))) == out_k:
			return true
		var ex_desc: String = str(ex.get("description", "")).strip_edges().to_lower()
		if ex_desc == desc:
			return true
	return false


static func pick_local_for_level(
	local_tasks: Array,
	level: int,
	already: Array,
	limit: int,
) -> Array:
	var picked: Array = []
	var buf: Array = already.duplicate(true)
	for raw in local_tasks:
		if picked.size() >= limit:
			break
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = raw.duplicate(true)
		t["level"] = int(level)
		if not is_playable_task(t):
			continue
		if _is_duplicate_in_batch(t, buf):
			continue
		picked.append(t)
		buf.append(t)
	return picked
