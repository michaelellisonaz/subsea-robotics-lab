// Underside of the sea surface. A slow procedural shimmer driven by the
// simulation clock (`sim_time`), so it stops when the simulation is paused.
// Visual only - no wave model. The surface is drawn as a bright (HDR) emitter
// because, seen from below, it is the source of all daylight; this keeps it
// readable through the fog as it would be in the water.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 surface_color : source_color = vec3(0.55, 0.82, 0.86);
uniform float brightness = 1.0;
uniform float intensity = 3.0;
uniform float sim_time = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float w = sin(p.x * 0.35 + sim_time * 0.9) * sin(p.y * 0.27 - sim_time * 0.7);
	w += 0.5 * sin((p.x + p.y) * 0.9 + sim_time * 1.7);
	ALBEDO = surface_color * brightness * intensity * (0.85 + 0.1 * w);
}
