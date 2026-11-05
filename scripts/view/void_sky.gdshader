shader_type sky;
uniform vec4 upper_tone : source_color = vec4(0.78, 0.78, 0.78, 1.0);
uniform vec4 lower_tone : source_color = vec4(0.68, 0.68, 0.68, 1.0);
void sky() {
	COLOR = EYEDIR.y >= -0.035 ? upper_tone.rgb : lower_tone.rgb;
}
