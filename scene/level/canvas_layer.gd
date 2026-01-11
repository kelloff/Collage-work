extends CanvasLayer

@onready var rect := $ColorRect
@onready var mat: ShaderMaterial = rect.material as ShaderMaterial

func _process(_delta):
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return

	var viewport := get_viewport()
	var screen_pos: Vector2 = viewport.get_screen_transform() * player.global_position

	mat.set_shader_parameter("player_pos", screen_pos)
