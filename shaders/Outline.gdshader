shader_type canvas_item;

uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_size = 1.0;

uniform bool highlight = false;
uniform vec4 highlight_color : source_color = vec4(0.6, 0.6, 0.6, 0.3); // полупрозрачный серый

void fragment() {
    vec4 base_color = texture(TEXTURE, UV);

    // мягкая подсветка — просто осветляем и слегка смешиваем с серым
    if (highlight) {
        base_color.rgb = mix(base_color.rgb, highlight_color.rgb, highlight_color.a);
    }

    vec4 out_color = base_color;

    if (enabled) {
        float alpha = base_color.a;

        if (alpha == 0.0) {
            vec2 px = TEXTURE_PIXEL_SIZE * outline_size;

            // проверяем соседей по 8 направлениям
            alpha += texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
            alpha += texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
            alpha += texture(TEXTURE, UV + vec2(0.0, px.y)).a;
            alpha += texture(TEXTURE, UV + vec2(0.0, -px.y)).a;

            alpha += texture(TEXTURE, UV + vec2(px.x, px.y)).a;
            alpha += texture(TEXTURE, UV + vec2(-px.x, px.y)).a;
            alpha += texture(TEXTURE, UV + vec2(px.x, -px.y)).a;
            alpha += texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;

            if (alpha > 0.0) {
                out_color = outline_color;
            }
        }
    }

    COLOR = out_color;
}