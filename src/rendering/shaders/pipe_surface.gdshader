// Pipeline surface drawn from the simulation's deposit grid (visual only).
// deposit_map: one texel per cell (x = along the pipe, y = around it, from
// -180° to +180° clock, 0 = top), value = deposit thickness / 3 mm.
// Where the coating is intact the deposit is marine growth over paint; on the
// corroded section (top half) it is corrosion product over pitted bare steel,
// which shows once cleaned.
shader_type spatial;

uniform sampler2D deposit_map : filter_linear, repeat_disable;
uniform float pipe_start = -30.0;
uniform float pipe_length = 60.0;
uniform float axis_y = 0.0;
uniform float axis_z = -6.0;
uniform float corrosion_from = 8.5;
uniform float corrosion_to = 11.5;
uniform vec3 paint_color : source_color = vec3(0.20, 0.25, 0.22);
uniform vec3 growth_color : source_color = vec3(0.24, 0.27, 0.15);
uniform vec3 rust_color : source_color = vec3(0.50, 0.22, 0.07);
uniform vec3 steel_color : source_color = vec3(0.42, 0.43, 0.44);
uniform vec3 pit_color : source_color = vec3(0.14, 0.07, 0.03);

varying vec3 world_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float clock = atan(-(world_pos.z - axis_z), world_pos.y - axis_y);
	vec2 uv = vec2((world_pos.x - pipe_start) / pipe_length, (clock + PI) / TAU);
	float deposit = texture(deposit_map, uv).r;
	float in_zone = step(corrosion_from, world_pos.x) * step(world_pos.x, corrosion_to);
	float failed = in_zone * smoothstep(PI * 0.5 + 0.05, PI * 0.5 - 0.05, abs(clock));
	float n = fbm(world_pos * 3.0);
	float fine = noise(world_pos * 11.0);
	// Underlying surface: paint, or pitted bare steel where the coating failed.
	float pits = smoothstep(0.62, 0.75, fine) * failed;
	vec3 bare = mix(steel_color * (0.85 + 0.3 * n), pit_color, pits * 0.8);
	vec3 base = mix(paint_color, bare, failed);
	// Deposit layer on top.
	vec3 layer = mix(growth_color * (0.7 + 0.6 * n), rust_color * (0.7 + 0.3 * n + 0.3 * fine), failed);
	float cover = smoothstep(0.03, 0.3, deposit) * (0.8 + 0.2 * n);
	ALBEDO = mix(base, layer, cover);
	ROUGHNESS = mix(mix(0.55, 0.6, failed), 0.95, cover);
	METALLIC = mix(mix(0.35, 0.6, failed), 0.0, cover);
}
