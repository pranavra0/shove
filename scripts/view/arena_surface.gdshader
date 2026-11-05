shader_type spatial;
render_mode diffuse_burley, specular_disabled, ambient_light_disabled;
uniform vec4 base_color : source_color = vec4(0.90, 0.90, 0.90, 1.0);
uniform vec4 line_color : source_color = vec4(0.78, 0.78, 0.78, 1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 grid_position = world_position.xz * 0.5;
	vec2 cell = abs(fract(grid_position + 0.5) - 0.5);
	float distance_to_line = min(cell.x, cell.y);
	float aa = max(fwidth(distance_to_line), 0.0001);
	float grid = 1.0 - smoothstep(0.012 - aa, 0.012 + aa, distance_to_line);
	ALBEDO = mix(base_color.rgb, line_color.rgb, grid * 0.65);
	ROUGHNESS = 0.92;
}
void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 bounded_light = min(LIGHT_COLOR.rgb, vec3(0.65));
	DIFFUSE_LIGHT += ALBEDO * bounded_light * ndotl * ATTENUATION;
}
