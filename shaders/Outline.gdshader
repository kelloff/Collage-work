shader_type canvas_item;

uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_size = 1.0;

uniform bool highlight = false;
uniform vec4 highlight_color : source_color = vec4(0.6, 0.6, 0.6, 0.3);

// ВАЖНО: порог альфы. Всё что ниже — считаем “пустотой”.
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec4 base_color = texture(TEXTURE, UV);

    // подсветка
    if (highlight) {
        base_color.rgb = mix(base_color.rgb, highlight_color.rgb, highlight_color.a);
    }

    vec4 out_color = base_color;

    if (enabled) {
        // если пиксель “прозрачный” (или почти) — ищем соседей
        if (base_color.a <= alpha_cutoff) {
            vec2 px = TEXTURE_PIXEL_SIZE * outline_size;

            float a = 0.0;
            a = max(a, texture(TEXTURE, UV + vec2( px.x, 0.0)).a);
            a = max(a, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
            a = max(a, texture(TEXTURE, UV + vec2(0.0,  px.y)).a);
            a = max(a, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);

            a = max(a, texture(TEXTURE, UV + vec2( px.x,  px.y)).a);
            a = max(a, texture(TEXTURE, UV + vec2(-px.x,  px.y)).a);
            a = max(a, texture(TEXTURE, UV + vec2( px.x, -px.y)).a);
            a = max(a, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);

            // если рядом есть “непрозрачный” пиксель — рисуем контур
            if (a > alpha_cutoff) {
                out_color = outline_color;
            }
        }
    }

    COLOR = out_color;
}