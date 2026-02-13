extends CanvasLayer

@onready var panel: Control = $Panel
@onready var tabs: OptionButton = $Panel/VBoxContainer/Tabs
@onready var text: RichTextLabel = $Panel/VBoxContainer/Text
@onready var close_btn: Button = $Panel/VBoxContainer/Close

var _open := false

var base_pages := {
	"Руководство": "res://docs/guide.txt",
	"Python: база": "res://docs/python_basics.txt",
	"Записки": ""
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)

	panel.visible = false

	close_btn.pressed.connect(hide_journal)
	tabs.item_selected.connect(_on_tab_selected)

	_reload_tabs()
	_on_tab_selected(0)

func toggle() -> void:
	if _open:
		hide_journal()
	else:
		show_journal()

func show_journal() -> void:
	_open = true
	panel.visible = true
	get_tree().paused = true

func hide_journal() -> void:
	_open = false
	panel.visible = false
	get_tree().paused = false

func _reload_tabs() -> void:
	tabs.clear()
	for k in base_pages.keys():
		tabs.add_item(k)

func _on_tab_selected(index: int) -> void:
	var key := tabs.get_item_text(index)

	if key == "Записки":
		_show_notes()
		return

	var path: String = str(base_pages.get(key, ""))
	text.text = _load_text(path)

func _show_notes() -> void:
	var notes := JournalData.get_notes()
	if notes.size() == 0:
		text.text = "Записок пока нет."
		return

	var out := ""
	for id in notes.keys():
		out += "=== " + id + " ===\n"
		out += notes[id] + "\n\n"
	text.text = out

func _load_text(path: String) -> String:
	if path == "":
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Файл не найден:\n" + path
	return f.get_as_text()
	

func is_open() -> bool:
	return _open

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		toggle()
		get_viewport().set_input_as_handled()
