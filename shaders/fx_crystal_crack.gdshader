shader_type spatial;
// Lane IC (H471): glowing crack lines over a crystal's ice shell. One jagged
// vertical crack per face, side branches as `k` grows; additive, unshaded.
// k 0 = none, 1 = fully cracked (primed and full). col = the glow colour.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

instance uniform vec4 col = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float k = 0.0;

varying vec3 lp;
varying float side;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	lp = VERTEX;                       // the mesh is 1 m tall, centred: y in -0.5..0.5
	side = 1.0 - step(0.9, abs(NORMAL.y));
}

void fragment() {
	float faces = 6.0;
	float ang = atan(lp.z, lp.x) / 6.2831853 + 0.5;
	float f = floor(ang * faces);
	float x = fract(ang * faces);
	float y = 0.5 - lp.y;              // 0 at the top, 1 at the base
	// main crack: a zigzag down the face, offset per face
	float zig = 0.5 + 0.18 * sin(y * 17.0 + f * 2.3) + 0.08 * sin(y * 41.0 + f * 5.1);
	float w = 0.06 + 0.03 * k;
	float line = smoothstep(w, 0.0, abs(x - zig));
	// only as far up the face as k reaches (cracks run up from the base)
	line *= step(1.0 - y, 0.25 + 0.75 * k);
	// branches: short diagonal splits at a few heights
	float br = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float hy = 0.2 + 0.25 * fi + 0.08 * hash(f * 7.0 + fi);
		float dir = hash(f * 3.0 + fi * 11.0) > 0.5 ? 1.0 : -1.0;
		float t = (x - zig) * dir;
		float on = step(0.0, t) * step(t, 0.28);
		float d = abs((y - hy) - t * 0.9);
		br += on * smoothstep(0.05, 0.0, d) * step(0.35 + 0.25 * fi, k);
	}
	float a = clamp(line + br, 0.0, 1.0) * clamp(k * 1.6, 0.0, 1.0) * side;
	ALBEDO = col.rgb * a * 3.0;
	ALPHA = a;
}
