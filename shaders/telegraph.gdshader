// A danger hex: the monster's telegraph (kickoff: "highlighting the exact
// target hexes before impact"). Flat hex of circumradius 1 on XZ. `progress`
// 0..1 fills the hex from the rim inward as the hit nears; the rim pulses.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://shaders/tile_fx.gdshaderinc"

uniform vec4 glow : source_color = vec4(1.0, 0.25, 0.12, 1.0);
instance uniform float progress : instance_index(8) = 0.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float d = hexd(lp);
	float t = TIME;
	vec4 acc = vec4(0.0);
	// faint fill so the shape reads at once
	over(acc, glow.rgb, 0.18 * (1.0 - smoothstep(0.9, 0.98, d)));
	// the fill closing in from the rim: at progress 1 the whole hex is lit
	float inner = 1.0 - progress;
	float fill = smoothstep(inner - 0.04, inner + 0.04, d) * (1.0 - smoothstep(0.92, 0.98, d));
	over(acc, glow.rgb, fill * (0.45 + 0.25 * progress));
	// rim, pulsing faster as the hit nears
	float pulse = 0.6 + 0.4 * sin(t * (6.0 + 10.0 * progress));
	float rim = 1.0 - smoothstep(0.0, 0.05, abs(d - 0.93));
	over(acc, mix(glow.rgb, vec3(1.0), 0.5), rim * pulse);
	vec3 col;
	float alpha;
	fx_out(acc, d, col, alpha);
	ALBEDO = col;
	ALPHA = alpha;
}
