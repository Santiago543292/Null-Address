shader_type canvas_item;

// Opaque CRT / VHS background plate for the front-end.
// No screen texture needed -> cheap, and it will not fight the player's own
// VHS shader (which is a screen-space overlay on the gameplay layer).

uniform vec3  base_color      : source_color = vec3(0.030, 0.033, 0.038);
uniform float noise_amount    : hint_range(0.0, 1.0) = 0.10;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.90;
uniform float band_amount     : hint_range(0.0, 1.0) = 0.05;
uniform float flicker_amount  : hint_range(0.0, 1.0) = 0.05;
uniform float grain_scale = 900.0;
uniform float band_speed  = 0.07;

float rand(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	vec3 col = base_color;

	// Fine tape grain
	float n = rand(uv * grain_scale + vec2(TIME * 37.0, TIME * 53.0));
	col += (n - 0.5) * noise_amount;

	// Slow rolling tracking band
	float band = fract(uv.y + TIME * band_speed);
	col += smoothstep(0.982, 1.0, band) * band_amount * 3.0;

	// Lens / tube vignette
	vec2 c = uv - 0.5;
	float v = 1.0 - dot(c, c) * 2.6 * vignette_amount;
	col *= clamp(v, 0.0, 1.0);

	// Exposure flicker
	col *= 1.0 - flicker_amount * rand(vec2(TIME * 0.7, 0.0));

	COLOR = vec4(col, 1.0);
}
