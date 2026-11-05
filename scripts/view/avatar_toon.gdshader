shader_type spatial;
render_mode unshaded;
uniform vec4 body_color : source_color = vec4(1.0, 0.4, 0.3, 1.0);
void fragment() {
	ALBEDO = body_color.rgb;
}
