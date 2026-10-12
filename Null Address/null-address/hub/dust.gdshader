shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// Floating dust. One quad per mote, always facing the camera, lit only where
// it drifts through a light. This is the single cheapest thing that makes a
// still room feel alive and dusty.

uniform vec3 mote_color : source_color = vec3(1.0, 0.93, 0.80);
uniform float brightness : hint_range(0.0, 4.0) = 1.2;

void vertex() {
	// Billboard: build a camera-facing basis.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// Soft round falloff so each mote is a dot, not a square.
	vec2 c = UV - vec2(0.5);
	float d = length(c);
	float a = smoothstep(0.5, 0.06, d);
	if (a < 0.01) {
		discard;
	}
	ALBEDO = mote_color * brightness;
	ALPHA = a;
}
