class_name InteractHighlight
extends RefCounted

## Единый хоррор-стиль подсветки интерактивных объектов.
const SHADER_PATH := "res://shaders/outline.gdshader"
const SHADER_PATH_FALLBACK := "res://shaders/Outline.gdshader"
const OUTLINE_COLOR := Color(0.9, 0.32, 0.26, 0.96)
const HIGHLIGHT_COLOR := Color(0.48, 0.06, 0.09, 0.4)
const OUTLINE_SIZE := 1.0
const ALPHA_CUTOFF := 0.5

static var _shader: Shader

static func get_shader() -> Shader:
	if _shader != null:
		return _shader
	for path in [SHADER_PATH, SHADER_PATH_FALLBACK]:
		if ResourceLoader.exists(path):
			_shader = load(path) as Shader
			if _shader != null:
				return _shader
	push_error("InteractHighlight: shader not found at %s" % SHADER_PATH)
	return null

static func create_material(alpha_cutoff: float = ALPHA_CUTOFF) -> ShaderMaterial:
	var shader := get_shader()
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	apply(mat, alpha_cutoff)
	return mat

static func apply(mat: ShaderMaterial, alpha_cutoff: float = ALPHA_CUTOFF) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("outline_color", OUTLINE_COLOR)
	mat.set_shader_parameter("highlight_color", HIGHLIGHT_COLOR)
	mat.set_shader_parameter("outline_size", OUTLINE_SIZE)
	mat.set_shader_parameter("alpha_cutoff", alpha_cutoff)

static func bind_canvas_item(sprite: CanvasItem, alpha_cutoff: float = ALPHA_CUTOFF) -> ShaderMaterial:
	if sprite == null:
		return null
	var mat := create_material(alpha_cutoff)
	if mat == null:
		return null
	sprite.material = mat
	return mat

static func set_enabled(mat: ShaderMaterial, outline_on: bool, highlight_on: bool) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("enabled", outline_on)
	mat.set_shader_parameter("highlight", highlight_on)
