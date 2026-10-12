shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

// Grime decal. Slap this on a thin quad against a wall to fake years of damp,
// mould and dirt creeping up from the skirting. Fully procedural, so it needs
// no textures and can be tiled anywhere.

uniform vec3 stain_color : source_color = vec3(0.045, 0.038, 0.030);
uniform vec3 mould_color : source_color = vec3(0.055, 0.070, 0.045);
uniform float density : hint_range(0.0, 1.0) = 0.75;
uniform float scale = 5.0;
uniform float fade_height : hint_range(0.0, 1.0) = 0.55;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * scale;

	// Two octave stacks: one broad stain, one finer mould speckle.
	float broad = fbm(uv * 0.5);
	float fine = fbm(uv * 3.0 + 11.0);

	// Grime is heaviest at the bottom of the quad and fades upward.
	float height_fade = smoothstep(fade_height, 0.0, UV.y);
	float mask = (broad * 0.7 + fine * 0.3) * height_fade * density;

	// Patchy mould where the fine noise peaks.
	float mould = smoothstep(0.62, 0.82, fine) * height_fade * density;

	vec3 col = mix(stain_color, mould_color, step(0.5, fine));
	float alpha = clamp(mask, 0.0, 1.0) * opacity;
	alpha = max(alpha, mould * 0.7 * opacity);

	if (alpha < 0.02) {
		discard;
	}

	ALBEDO = col;
	ALPHA = alpha;
}
