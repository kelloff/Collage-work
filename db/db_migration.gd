# res://scripts/db/db_migration.gd
extends Node
class_name DbMigration

func run_migration() -> void:
	var template_path := "res://tasks.db"
	var user_path := "user://tasks.db"
	if not FileAccess.file_exists(user_path):
		if FileAccess.file_exists(template_path):
			var src := FileAccess.open(template_path, FileAccess.READ)
			var dst := FileAccess.open(user_path, FileAccess.WRITE)
			dst.store_buffer(src.get_buffer(src.get_length()))
			src.close()
			dst.close()
			print("DbMigration: copied DB template to user://tasks.db")
		else:
			print("DbMigration: no template DB found; will create empty DB on open")
