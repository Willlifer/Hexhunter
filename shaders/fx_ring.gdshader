// Lane FX (H706): a flat expanding ring on the ground (skill landings:
// Eruption, Arrowstorm, Flourish). A PlaneMesh of size 2 (radius 1 in UV
// space) scaled by the node; `k` 0..1 over the ring's life drives the
// radius, the band width and the fade; `col` the element glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float k : instance_index(0) = 0.0;
instance uniform vec4 col : instance_index(1) = vec4(1.0, 0.8, 0.4, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float rad = 0.15 + 0.85 * sqrt(k);
	float w = mix(0.22, 0.05, k);
	float band = 1.0 - smoothstep(0.0, w, abs(r - rad));
	float inner = (1.0 - smoothstep(0.0, rad, r)) * 0.25 * (1.0 - k);
	float a = (band + inner) * (1.0 - k) * (1.0 - smoothstep(0.97, 1.0, r));
	if (a < 0.003) {
		discard;
	}
	ALBEDO = pow(col.rgb, vec3(2.2)) * 1.6;
	ALPHA = clamp(a, 0.0, 1.0);
}
