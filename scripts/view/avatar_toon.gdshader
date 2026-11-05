shader_type spatial;
render_mode specular_disabled;
uniform vec4 body_color : source_color = vec4(1.0,0.4,0.3,1.0);
uniform float rim_strength = 0.65;
void fragment() {
 ALBEDO = body_color.rgb;
 ROUGHNESS = 0.9;
 float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)),0.0), 3.0);
 EMISSION = mix(body_color.rgb, vec3(0.55,0.95,1.0),0.5) * rim * rim_strength;
}
void light() {
 float shade = dot(NORMAL,LIGHT);
 float band = smoothstep(-0.08,0.08,shade) * 0.55 + smoothstep(0.55,0.65,shade) * 0.3 + 0.15;
 DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * ATTENUATION;
}
