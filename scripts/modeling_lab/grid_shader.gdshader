shader_type spatial;
render_mode unshaded, cull_back;

/** Faint translucent ground tint. */
uniform vec4 base_color : source_color = vec4(0.06, 0.075, 0.095, 0.55);
/** Color of the minor grid lines. */
uniform vec4 line_color : source_color = vec4(0.5, 0.56, 0.64, 1.0);
/** Color of the major grid lines (every grid_major units). */
uniform vec4 major_line_color : source_color = vec4(0.78, 0.82, 0.88, 1.0);
/** Color of the world-space X axis through the origin (Godot editor red). */
uniform vec4 axis_color_x : source_color = vec4(0.9, 0.28, 0.28, 1.0);
/** Color of the world-space Z axis through the origin (Godot editor blue). */
uniform vec4 axis_color_z : source_color = vec4(0.3, 0.45, 0.95, 1.0);
uniform float grid_minor : hint_range(0.05, 10.0) = 1.0;
uniform float grid_major : hint_range(1.0, 50.0) = 5.0;
/** Half-width of a grid line, in world units. */
uniform float line_width = 0.045;
/** Lines farther than fade_start begin to fade toward the horizon. */
uniform float fade_start = 6.0;
uniform float fade_end = 22.0;

varying vec3 world_pos;

float _coverage(float dist_to_line, float half_width) {
	return 1.0 - smoothstep(0.0, half_width, abs(dist_to_line));
}

/* Distance from a coordinate to its nearest line at the given spacing. */
float _nearest_line(float coord, float spacing) {
	return mod(abs(coord) + spacing * 0.5, spacing) - spacing * 0.5;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = world_pos.x;
	float z = world_pos.z;
	float half_w = line_width * 0.5;

	float minor_both = max(
		_coverage(_nearest_line(x, grid_minor), half_w),
		_coverage(_nearest_line(z, grid_minor), half_w));
	float major_both = max(
		_coverage(_nearest_line(x, grid_major), half_w),
		_coverage(_nearest_line(z, grid_major), half_w));
	float x_axis = _coverage(x, half_w * 1.5);
	float z_axis = _coverage(z, half_w * 1.5);

	float fader = 1.0 - smoothstep(fade_start, fade_end, distance(world_pos, CAMERA_POSITION_WORLD));

	vec3 col = base_color.rgb;
	col = mix(col, line_color.rgb, minor_both * fader);
	col = mix(col, major_line_color.rgb, major_both * fader);
	col = mix(col, axis_color_x.rgb, x_axis * fader);
	col = mix(col, axis_color_z.rgb, z_axis * fader);

	float alpha = base_color.a * fader;
	alpha = mix(alpha, max(alpha, 0.85), max(minor_both, max(major_both, max(x_axis, z_axis))) * fader);

	ALBEDO = col;
	ALPHA = alpha;
}