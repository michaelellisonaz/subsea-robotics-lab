// Seabed surface: procedural sediment colour plus a world-space reference grid.
// Grid lines are computed from world X/Z, so they follow the terrain exactly
// and stay anti-aliased at any distance (fwidth-based), with no extra geometry.
//   minor lines  every `minor_spacing` metres (default 1 m)
//   major lines  every `major_spacing` metres (default 10 m)
//   X axis (z = 0) in red, Z axis (x = 0) in blue
shader_type spatial;

uniform vec3 sediment_light : source_color = vec3(0.37, 0.38, 0.32);
uniform vec3 sediment_dark : source_color = vec3(0.20, 0.22, 0.19);
uniform bool grid_enabled = true;
uniform float minor_spacing = 1.0;
uniform float major_spacing = 10.0;
uniform vec3 minor_color : source_color = vec3(0.30, 0.62, 0.68);
uniform vec3 major_color : source_color = vec3(0.45, 0.88, 0.98);
uniform vec3 axis_x_color : source_color = vec3(0.95, 0.38, 0.32);
uniform vec3 axis_z_color : source_color = vec3(0.35, 0.60, 1.00);
uniform float minor_strength = 0.30;
uniform float major_strength = 0.75;
uniform float line_emission = 0.35;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// 1.0 on a grid line, 0.0 elsewhere. Lines are ~width_px pixels wide and fade
// out once the cells become too small on screen to avoid moire.
float grid_mask(vec2 coord, float spacing, float width_px) {
	vec2 c = coord / spacing;
	vec2 fw = max(fwidth(c), vec2(1e-5));
	vec2 g = abs(fract(c - 0.5) - 0.5) / fw;
	float line = min(g.x, g.y);
	float mask = 1.0 - smoothstep(width_px * 0.5, width_px * 0.5 + 1.0, line);
	float fade = 1.0 - smoothstep(0.12, 0.35, max(fw.x, fw.y));
	return mask * fade;
}

// Line along coord = 0 with a minimum physical width (metres).
float axis_mask(float coord, float min_width) {
	float fw = max(fwidth(coord), 1e-5);
	float w = max(min_width, fw * 1.2);
	return 1.0 - smoothstep(w, w + fw, abs(coord));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = fbm(p * 0.12) * 0.7 + fbm(p * 1.3) * 0.3;
	vec3 albedo = mix(sediment_dark, sediment_light, n);
	vec3 emission = vec3(0.0);
	if (grid_enabled) {
		float minor = grid_mask(p, minor_spacing, 1.0) * minor_strength;
		float major = grid_mask(p, major_spacing, 1.6) * major_strength;
		float ax = axis_mask(p.y, 0.05);
		float az = axis_mask(p.x, 0.05);
		albedo = mix(albedo, minor_color, minor);
		albedo = mix(albedo, major_color, major);
		albedo = mix(albedo, axis_x_color, ax);
		albedo = mix(albedo, axis_z_color, az);
		emission = (minor_color * minor + major_color * major
				+ axis_x_color * ax + axis_z_color * az) * line_emission;
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	EMISSION = emission;
}
