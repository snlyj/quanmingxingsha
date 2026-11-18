shader_type canvas_item;
render_mode unshaded;

uniform vec2 frame_size = vec2(1.0);
uniform float radius = 28.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 half_size = frame_size * 0.5;
	float corner = min(radius, min(half_size.x, half_size.y));
	vec2 edge = abs(local_position - half_size) - (half_size - corner);
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - corner;
	float pixel_width = max(fwidth(distance_to_edge), 0.001);
	COLOR.a *= 1.0 - smoothstep(-pixel_width, 0.0, distance_to_edge);
}
