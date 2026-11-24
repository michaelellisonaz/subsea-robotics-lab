// Draws an imaging-sonar ping as a polar fan. The data texture holds
// intensities with x = beam (across the field of view) and y = range bin
// (0 at the transducer). The fan apex is at the bottom centre of the rect;
// the rect height equals the maximum range.
shader_type canvas_item;

uniform sampler2D data : filter_linear, repeat_disable;
uniform float half_fov = 1.0472;
uniform float aspect = 1.73;
uniform vec3 low_color : source_color = vec3(0.02, 0.05, 0.07);
uniform vec3 high_color : source_color = vec3(1.0, 0.8, 0.3);

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect, 1.0 - UV.y);
	float r = length(p);
	float a = atan(p.x, p.y);
	if (r > 1.0 || abs(a) > half_fov) {
		COLOR = vec4(0.0);
	} else {
		float v = texture(data, vec2(a / (2.0 * half_fov) + 0.5, r)).r;
		COLOR = vec4(mix(low_color, high_color, clamp(v * 1.4, 0.0, 1.0)), 1.0);
	}
}
