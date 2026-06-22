extends Node

# собранные записки: note_id -> text
var unlocked_notes: Dictionary = {}

func add_note(note_id: String, text: String) -> void:
	if note_id == "":
		return
	if unlocked_notes.has(note_id):
		return
	unlocked_notes[note_id] = text

func has_note(note_id: String) -> bool:
	return unlocked_notes.has(note_id)

func get_notes() -> Dictionary:
	return unlocked_notes


static func read_project_text(path: String) -> String:
	if path.strip_edges() == "":
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		return f.get_as_text()
	var abs := ProjectSettings.globalize_path(path)
	if abs != "" and FileAccess.file_exists(abs):
		f = FileAccess.open(abs, FileAccess.READ)
		if f != null:
			return f.get_as_text()
	push_warning("JournalData: text file not found: %s" % path)
	return "Файл не найден:\n" + path
