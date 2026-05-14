extends Node
## Алиас для кода, который ожидает имя SaveMeneger.
## Реальная логика в save_manager.gd — автозагрузка **Savemeneger** (см. project.godot).


func has_save() -> bool:
	return Savemeneger.has_save()


func continue_game() -> void:
	Savemeneger.continue_game()


func reset_save() -> void:
	Savemeneger.reset_save()


func reset_run_after_death() -> void:
	Savemeneger.reset_run_after_death()


func save_now() -> void:
	Savemeneger.save_now()


func load_game() -> void:
	Savemeneger.load_game()
