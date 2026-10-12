shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

// Distant city block seen through fog. Flat-shaded box with randomly lit
// windows, so the horizon reads as "somewhere else, still awake" instead of
// an empty void. Cheap: one hash per fragment, no textures.

uniform vec3 base_color : source_color = vec3(0.045, 0.050, 0.065);
uniform vec3 window_color : source_color = vec3(1.0, 0.82, 0.52);
uniform vec3 dead_window_color : source_color = vec3(0.02, 0.025, 0.035);
uniform float columns = 6.0;
uniform float rows = 14.0;
uniform float lit_chance : hint_range(0.0, 1.0) = 0.32;
uniform float emission_strength = 3.0;
uniform float flicker_speed = 0.15;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Grid of windows across the box faces.
	vec2 grid = vec2(columns, rows);
	vec2 scaled = UV * grid;
	vec2 cell = floor(scaled);
	vec2 f = fract(scaled);

	// Window opening inside each cell.
	float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.22, f.y) * step(f.y, 0.78);

	// Which windows are lit. Slightly animated so a few switch over time.
	float r = hash(cell);
	float drift = hash(cell + floor(TIME * flicker_speed)) * 0.35;
	float lit = step(1.0 - lit_chance, r + drift);

	vec3 albedo = mix(dead_window_color, base_color, win);
	ALBEDO = albedo;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;

	EMISSION = window_color * lit * win * emission_strength;
}
