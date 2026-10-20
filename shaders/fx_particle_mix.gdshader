// Lane FX (H700): alpha-blended sprites (smoke, dust, snow, haze): these
// must read on bright ground too, where additive vanishes.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/fx_particle.gdshaderinc"

void fragment() {
	float a = fxp_shape(vshape, q, TIME) * vcol.a;
	if (a < 0.003) {
		discard;
	}
	ALBEDO = vcol.rgb;
	ALPHA = a;
}
