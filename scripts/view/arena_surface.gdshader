shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.06,0.19,0.23,1.0);
uniform vec4 line_color : source_color = vec4(0.2,0.6,0.65,1.0);
uniform float emission_strength = 0.12;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
 vec2 cell = abs(fract(local_position.xz * 0.5 + 0.5) - 0.5);
 float grid = 1.0 - smoothstep(0.012, 0.035, min(cell.x, cell.y));
 ALBEDO = mix(base_color.rgb, line_color.rgb, grid * 0.28);
 ROUGHNESS = 0.82;
 EMISSION = line_color.rgb * grid * emission_strength;
}
