// Lane Z (H92): the web (gl_compatibility) stand-in for GKMaterials' additive
// light-pool sheets (role blend "add": torch pools, lava glow). On desktop the
// sheet adds linear light under the Filmic tonemap, so a strong pool bleaches
// toward warm white; on the web it is tonemapped and sRGB-encoded on its own
// and added afterwards, so it stays a saturated orange smear over a dark
// floor. This pulls the sheet's colour toward its own brightness by
// `whiten` and scales it by `gain` (HHTune web_glow_whiten / web_glow_gain).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float whiten = 0.5;
uniform float gain = 1.0;

void fragment() {
	vec3 c = albedo.rgb * COLOR.rgb;
	float lum = max(c.r, max(c.g, c.b));
	ALBEDO = mix(c, vec3(lum) * vec3(1.0, 0.94, 0.82), whiten) * gain;
	ALPHA = albedo.a * COLOR.a;
}
