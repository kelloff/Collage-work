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

	_style_ui()
	_reload_tabs()
	_on_tab_selected(0)

func _style_ui() -> void:
	GameUiTheme.apply_horror_panel(panel as Panel)
	var title: Label = $Panel/VBoxContainer/Title
	if title:
		title.label_settings = GameUiTheme.make_horror_title_settings(26)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.scroll_active = true
	text.fit_content = false
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.size_flags_stretch_ratio = 1.0

func toggle() -> void:
	if _open:
		hide_journal()
	else:
		show_journal()

func show_journal() -> void:
	_open = true
	panel.visible = true
	if GameState.has_method("push_gameplay_freeze"):
		GameState.push_gameplay_freeze()
	else:
		get_tree().paused = true
	TutorialManager.notify_journal_opened()

func hide_journal() -> void:
	_open = false
	panel.visible = false
	if GameState.has_method("pop_gameplay_freeze"):
		GameState.pop_gameplay_freeze()
	else:
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
	text.text = JournalData.read_project_text(path)

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

func is_open() -> bool:
	return _open

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		toggle()
		get_viewport().set_input_as_handled()
