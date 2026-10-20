// Lane FX (H700): additive sprites (embers, streaks, sparks, glows).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/fx_particle.gdshaderinc"

void fragment() {
	float a = fxp_shape(vshape, q, TIME) * vcol.a;
	if (a < 0.003) {
		discard;
	}
	ALBEDO = vcol.rgb;
	ALPHA = a;
}
