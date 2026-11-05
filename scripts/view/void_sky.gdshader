shader_type sky;
uniform vec4 zenith : source_color = vec4(0.025, 0.045, 0.11, 1.0);
uniform vec4 horizon : source_color = vec4(0.09, 0.24, 0.29, 1.0);
uniform vec4 abyss : source_color = vec4(0.008, 0.018, 0.045, 1.0);
void sky() {
	float y = EYEDIR.y;
	float haze = exp(-abs(y + 0.06) * 4.0);
	vec3 color = mix(abyss.rgb, zenith.rgb, smoothstep(-0.9, 0.6, y));
	color = mix(color, horizon.rgb, haze * 0.68);
	float bands = sin(EYEDIR.x * 18.0 + EYEDIR.z * 11.0 + sin(EYEDIR.z * 24.0) * 0.8);
	float clouds = smoothstep(0.2, 0.95, bands) * exp(-abs(y + 0.38) * 7.0);
	color += vec3(0.014, 0.04, 0.055) * clouds;
	vec2 cell = floor(EYEDIR.xz * 500.0);
	float star = step(0.9992, fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453));
	color += vec3(0.25, 0.4, 0.5) * star * smoothstep(0.05, 0.5, y);
	COLOR = color;
}
