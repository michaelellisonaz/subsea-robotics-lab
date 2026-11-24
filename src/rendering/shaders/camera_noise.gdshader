// Image noise overlay for the pilot camera's low-light gain (visual
// approximation of sensor noise; amount = 0 disables it).
shader_type canvas_item;

uniform float amount = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float n = hash(cell + vec2(fract(TIME * 7.13) * 917.0, fract(TIME * 3.71) * 613.0));
	COLOR = vec4(vec3(n), amount * (0.4 + 0.6 * n));
}
