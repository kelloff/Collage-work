shader_type canvas_item;

uniform vec2 player_pos;
uniform float radius = 200.0;
uniform float softness = 40.0;

void fragment() {
	vec2 screen_pos = SCREEN_UV * SCREEN_PIXEL_SIZE;
	float dist = distance(screen_pos, player_pos);

	float alpha = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(0.0, 0.0, 0.0, alpha * 0.7);
}
