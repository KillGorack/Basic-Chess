shader_type spatial;
render_mode unshaded, cull_disabled, blend_add; // all optional

uniform float fade_start_y = -0.15f; // fully opaque at/below this local Y
uniform float fade_end_y = 0.15f; // fully transparent at/above this local Y
uniform float fade_curve : hint_range(0.1, 5.0) = 1.0; // >1 holds opacity near the bottom longer before dropping off
uniform vec3 boundry_color: source_color = vec3(1.0);

uniform sampler2D noise_texture;
uniform float noise_scale = 2.0;
uniform float noise_scroll_speed = 0.15;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.5;

varying float y_position;
varying vec2 noise_uv;
varying float wall_mask;

void vertex() {
	y_position = VERTEX.y;
	// World-space XZ so the noise holds still relative to the board instead
	// of swimming with the mesh's own (per-face) UVs on a cube.
	noise_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * noise_scale;
	// Cube's top/bottom caps have a normal pointing straight along Y — zero
	// those out so only the 4 vertical walls render.
	wall_mask = 1.0 - step(0.5, abs(NORMAL.y));
}

void fragment() {
	vec2 scroll = vec2(TIME * noise_scroll_speed, TIME * noise_scroll_speed * 0.6);
	float n = texture(noise_texture, noise_uv + scroll).r;
	float t = clamp((y_position - fade_start_y) / (fade_end_y - fade_start_y), 0.0f, 1.0f);
	float fade = pow(1.0f - t, fade_curve);
	ALBEDO = boundry_color;
	ALPHA = fade * mix(1.0, n, noise_strength) * wall_mask;
}