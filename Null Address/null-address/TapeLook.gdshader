shader_type canvas_item;

// VHS Shader by "Vacation" - https://godotshaders.com/shader/vhs-shader/
// Verbatim. Do not edit the signal chain; tune via the material parameters on
// the TapeOverlay ColorRect instead (see hub/filming.gd).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms Signal_Distortion;
uniform float smearing : hint_range(0.0, 1.0) = 0.5;
uniform float color_offset : hint_range(-0.05, 0.05) = 0.005;
uniform float sharpening : hint_range(0.0, 1.0) = 0.4;
uniform float static_noise : hint_range(0.0, 1.0) = 0.08;

group_uniforms Glass_Crack;
uniform vec2 crack_center = vec2(0.15, 0.85);
uniform float crack_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float crack_size : hint_range(0.0, 1.0) = 0.35;

group_uniforms Tape_Artifacts;
uniform float vertical_jitter : hint_range(0.0, 0.1) = 0.002;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.1;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.3;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

// logic for the shattered glass displacement
vec2 get_crack_distortion(vec2 uv, vec2 center, float strength, float size) {
    vec2 dir = uv - center;
    float dist = length(dir);

    if (dist < size) {
        // create angular "shards"
        float angle = atan(dir.y, dir.x);
        float shard = floor(angle * 8.0); // 8 main crack directions

        // displacement based on shard id and distance
        float d = noise(vec2(shard, 1.0)) * strength * (1.0 - (dist / size));
        return dir * d;
    }
    return vec2(0.0);
}

vec3 rgb_to_yiq(vec3 c) {
	return vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(0.596, -0.274, -0.322)), dot(c, vec3(0.211, -0.523, 0.312)));
}

vec3 yiq_to_rgb(vec3 c) {
	return vec3(dot(c, vec3(1.0, 0.956, 0.621)), dot(c, vec3(1.0, -0.272, -0.647)), dot(c, vec3(1.0, -1.106, 1.703)));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;

	// 1. GLASS CRACK DISPLACEMENT
	vec2 glass_distort = get_crack_distortion(uv, crack_center, crack_intensity, crack_size);
	uv += glass_distort;

	// 2. ANALOG JITTER
	uv.y += (noise(vec2(t, 0.0)) - 0.5) * vertical_jitter;

	// 3. SMEARED CHROMA
	vec3 yiq_pure = rgb_to_yiq(texture(screen_texture, uv).rgb);
	float y = yiq_pure.x;
	float i_acc = 0.0;
	float q_acc = 0.0;

	int samples = 12;
	for(int n = 0; n < samples; n++) {
		float x_offset = (float(n) * (smearing * 0.01)) + color_offset;
		vec3 s = rgb_to_yiq(texture(screen_texture, uv - vec2(x_offset, 0.0)).rgb);
		i_acc += s.y;
		q_acc += s.z;
	}

	vec3 final_yiq = vec3(y, i_acc / float(samples), q_acc / float(samples));

	// 4. EDGE SHARPENING
	float neighbor = rgb_to_yiq(texture(screen_texture, uv + vec2(0.001, 0.0)).rgb).x;
	final_yiq.x += (y - neighbor) * sharpening;

	vec3 color = yiq_to_rgb(final_yiq);

	// 5. CRACK LINES
	//
	// This used to be a radial fan: `sin(atan(...) * 8.0)` draws 8 straight
	// spokes out of one point, which reads as a star or a spider, not as broken
	// glass - and at (0.15, 0.85) it sits in the lower-left of every frame the
	// player looks at. It is replaced with a single branching fracture.
	{
		vec2 p = SCREEN_UV - crack_center;
		float ang = atan(p.y, p.x);
		float r = length(p);

		// one main run, gently curving rather than straight
		float spine = ang - (0.35 * sin(r * 9.0)) - noise(vec2(r * 4.0, 0.0)) * 0.10;
		// wobble the spine so it reads as a fracture, not a radius
		float wob = abs(sin(r * 46.0 + noise(vec2(r * 12.0, 3.0)) * 5.0)) * 0.06;

		// width tapers with distance from the impact point
		float taper = 1.0 - smoothstep(0.0, crack_size, r);
		float main_line = 1.0 - smoothstep(0.0, 0.012 + wob, abs(spine) * r);
		float line = main_line * taper;

		// two branches, turning off the spine, thinner and shorter
		for (int i = 0; i < 2; i++) {
			float bi = float(i);
			float off = (bi == 0.0) ? 0.55 : -0.48;
			float bstart = 0.42 + bi * 0.16;          // where along the spine it leaves
			float bmask = smoothstep(bstart, bstart + 0.06, r);
			float bdir = ang - (0.35 * sin(r * 9.0)) - off;
			float bline = 1.0 - smoothstep(0.0, 0.010, abs(bdir) * r);
			line += bline * bmask * taper * 0.7;
		}

		color += clamp(line, 0.0, 1.0) * 0.45;
	}

	// 6. VHS ARTIFACTS
	color += (noise(uv + t) - 0.5) * static_noise;
	color -= sin(uv.y * 800.0) * scanline_opacity * y;
	color *= smoothstep(0.8, 0.8 - vignette_intensity, distance(SCREEN_UV, vec2(0.5)));

	COLOR = vec4(color, 1.0);
}
