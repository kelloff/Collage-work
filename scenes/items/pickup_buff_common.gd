class_name PickupBuffCommon
extends RefCounted

const ICON_SIZE_PX := 16.0

static func setup_sprite(sprite: Sprite2D) -> ShaderMaterial:
	if sprite == null:
		push_warning("PickupBuffCommon: Sprite2D is null")
		return null

	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite.texture:
		var sz := sprite.texture.get_size()
		if sz.x > 0.0 and sz.y > 0.0:
			sprite.scale = Vector2(ICON_SIZE_PX / sz.x, ICON_SIZE_PX / sz.y)

	return InteractHighlight.bind_canvas_item(sprite, 0.01)
