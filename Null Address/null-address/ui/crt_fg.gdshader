shader_type canvas_item;

// Transparent scanline / vignette pass drawn ON TOP of the front-end.
// Black-only overlay so it darkens without washing out the UI text.

uniform float scanline_amount : hint_range(0.0, 1.0) = 0.34;
uniform float scanline_count = 540.0;
uniform float noise_amount    : hint_range(0.0, 1.0) = 0.035;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.50;
uniform float wobble_amount   : hint_range(0.0, 0.02) = 0.0012;
uniform float max_alpha       : hint_range(0.0, 1.0) = 0.85;

float rand(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Gentle horizontal tape wobble so scanlines are not perfectly straight
	uv.x += sin(uv.y * 30.0 + TIME * 2.0) * wobble_amount;

	// Scanlines
	float s = sin(uv.y * scanline_count * 3.14159265);
	float a = scanline_amount * (0.5 + 0.5 * s) * 0.5;

	// Static
	a += noise_amount * rand(uv * 1400.0 + vec2(TIME * 41.0, TIME * 67.0));

	// Vignette
	vec2 c = uv - 0.5;
	a += clamp(dot(c, c) * 2.4 * vignette_amount, 0.0, 1.0);

	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, max_alpha));
}
