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
