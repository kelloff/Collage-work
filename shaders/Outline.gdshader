shader_type canvas_item;

uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_size = 1.0;

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);

	if (!enabled) {
		COLOR = base_color;
		return;
	}

	float alpha = base_color.a;

	// если пиксель прозрачный — проверяем соседей
	if (alpha == 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_size;

		alpha += texture(TEXTURE, UV + vec2(px.x, 0)).a;
		alpha += texture(TEXTURE, UV + vec2(-px.x, 0)).a;
		alpha += texture(TEXTURE, UV + vec2(0, px.y)).a;
		alpha += texture(TEXTURE, UV + vec2(0, -px.y)).a;

		if (alpha > 0.0) {
			COLOR = outline_color;
			return;
		}
	}

	COLOR = base_color;
}
