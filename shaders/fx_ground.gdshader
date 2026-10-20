// Lane FX (H702): what a wind-up does to the ground under a telegraph, one
// flat hex (HHTileFX.hex_mesh, circumradius 1) per telegraph hex, drawn just
// above the danger tint. Patterns run in world space so they read as one
// sheet across the hexes, not a tile per hex.
//   progress  0..1 over the countdown (the wind-up)
//   commit    0..1 after contact (the landing flash, then the fade)
//   origin    xz: where the effect comes from (the source: fists, mouth, the
//             landing centre); z: the reach in metres; w: a seed
//   dir       xz: a unit direction (lanes, lines, cones); z: unused
// Modes (one material per mode, HHTelegraphFx.GROUND_MODE):
//   0 dust + crack   1 fire scorch   2 ice (wind swirl, then frost)
//   3 water ripples  4 thunder arcs  5 wind swirl  6 dark pool
//   7 light rings    8 shadow disc   9 lane arrows (charges)
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint2 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float progress : instance_index(0) = 0.0;
instance uniform float commit : instance_index(1) = 0.0;
instance uniform vec4 origin : instance_index(2) = vec4(0.0);
instance uniform vec4 dir : instance_index(3) = vec4(0.0, 1.0, 0.0, 0.0);

varying vec3 wp;
varying vec2 lp;

const float APOTHEM = 0.8660254;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return s;
}

float hexd(vec2 p) {
	p = abs(p);
	float a = max(p.x, dot(p, vec2(0.5, APOTHEM)));
	return max(a, abs(dot(p, vec2(-0.5, APOTHEM)))) / APOTHEM;
}

// Voronoi edge distance (frost crystals, cracked crust).
float vedge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 3.7));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

vec3 lin(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

void vertex() {
	lp = VERTEX.xz;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float p = clamp(progress, 0.0, 1.0);
	float k = clamp(commit, 0.0, 1.0);
	vec2 o = origin.xy;
	float reach = max(origin.z, 0.5);
	vec2 rel = wp.xz - o;
	float r = length(rel);
	float rn = r / reach;                    // 0 at the source, 1 at the far edge
	float edge = 1.0 - smoothstep(0.86, 0.99, hexd(lp));
	vec3 c = vec3(0.0);
	float a = 0.0;
	vec3 t1 = lin(tint.rgb);
	vec3 t2 = lin(tint2.rgb);

	if (mode == 0) {
		// dust + crack: the ground darkens and a crack line runs out from the source
		float n = fbm(wp.xz * 1.3 + origin.w * 7.0);
		float crackline = abs(fbm(wp.xz * 0.9 + origin.w * 3.0) - 0.5);
		float front = p * 1.25;
		float reveal = 1.0 - smoothstep(front - 0.15, front, rn);
		float crack = (1.0 - smoothstep(0.0, 0.022 + 0.01 * p, crackline)) * reveal;
		c = mix(t1 * 0.55, vec3(0.03, 0.02, 0.015), crack);
		a = (0.18 * p * (0.6 + 0.4 * n) + crack * 0.85) * edge;
		a += k * (1.0 - k) * 1.8 * edge * 0.6;              // landing puff of dust colour
		c = mix(c, t1, k * (1.0 - k) * 2.0);
		a *= 1.0 - smoothstep(0.55, 1.0, k);
	} else if (mode == 1) {
		// fire: a scorch glow spreading from the source, brightening, flickering;
		// embers prick through the crust
		float front = p * 1.2;
		float reveal = 1.0 - smoothstep(front - 0.35, front, rn);
		float n = fbm(wp.xz * 1.6 - vec2(0.0, t * 0.9));
		float crust = vedge(wp.xz * 1.6 + origin.w * 5.0);
		float glow = (0.45 + 0.55 * n) * reveal * (0.35 + 0.65 * p);
		float vein = (1.0 - smoothstep(0.0, 0.08, crust)) * reveal;
		vec3 dark = vec3(0.06, 0.02, 0.01);
		c = mix(dark, t1, clamp(glow * 1.3, 0.0, 1.0));
		c = mix(c, t2 * 1.6, vein * p);
		a = clamp(0.25 * reveal + glow * 0.75 + vein * p * 0.6, 0.0, 0.95) * edge;
		c = mix(c, t2 * 2.0, k * (1.0 - k) * 3.0);
		a *= 1.0 - smoothstep(0.4, 1.0, k);
	} else if (mode == 2) {
		// ice: first the wind (pale swirling streaks dusting the ground), then in
		// the last third frost crystallises outward from the source
		float ang = atan(rel.y, rel.x);
		float swirl = sin(ang * 5.0 + r * 1.6 - t * 5.0 + origin.w * 6.0);
		float streak = smoothstep(0.75, 1.0, swirl) * (0.4 + 0.6 * vn(wp.xz * 2.0 + t));
		float wind = (1.0 - smoothstep(0.62, 0.8, p)) * smoothstep(0.0, 0.25, p);
		float fp = smoothstep(0.62, 1.0, p);                 // the frost phase
		float front = fp * 1.15 + k * 0.4;
		float reveal = 1.0 - smoothstep(front - 0.18, front, rn + 0.12 * vn(wp.xz * 3.0));
		float cells = vedge(wp.xz * 2.6 + origin.w * 4.0);
		float fern = 1.0 - smoothstep(0.0, 0.06, cells);
		float fine = 1.0 - smoothstep(0.0, 0.035, vedge(wp.xz * 7.0));
		vec3 frost = mix(t1, vec3(1.0), 0.55 + 0.45 * fern);
		float fa = reveal * (0.38 + 0.5 * fern + 0.25 * fine);
		c = mix(vec3(0.92, 0.97, 1.0), frost, step(0.001, fa));
		a = max(streak * wind * 0.8, fa) * edge;
		c = mix(c, vec3(1.0), k * (1.0 - k) * 2.5);
		a *= 1.0 - smoothstep(0.55, 1.0, k);
	} else if (mode == 3) {
		// water: rings running out from the source (it surfaces there), faster as it nears
		float speed = 1.2 + 3.0 * p;
		float ring = sin(r * 4.2 - t * speed * 2.0);
		float rings = smoothstep(0.65, 0.95, ring) * (1.0 - smoothstep(0.7, 1.15, rn));
		float wet = 0.22 + 0.25 * p;
		float bulge = (1.0 - smoothstep(0.0, 0.9 + 0.8 * p, r)) * p;
		c = mix(t1, vec3(0.85, 0.95, 1.0), rings * 0.8 + bulge * 0.5);
		a = (wet + rings * (0.35 + 0.4 * p) + bulge * 0.4) * edge;
		c = mix(c, vec3(0.9, 0.97, 1.0), k * (1.0 - k) * 3.0);
		a *= 1.0 - smoothstep(0.5, 1.0, k);
	} else if (mode == 4) {
		// thunder: crackling arcs, denser and brighter toward contact, re-rolled 12x a second
		float step_t = floor(t * 12.0);
		float n = fbm(wp.xz * 1.8 + vec2(step_t * 1.37, step_t * 0.71));
		float arc = 1.0 - smoothstep(0.0, 0.025 + 0.02 * p, abs(n - 0.5));
		float on = step(h21(vec2(step_t, origin.w)), 0.35 + 0.6 * p);
		c = mix(t1, vec3(1.0, 0.95, 1.0), arc);
		a = (0.12 * p + arc * on * (0.4 + 0.6 * p)) * edge;
		c = mix(c, vec3(1.0), k * (1.0 - k) * 3.0);
		a = max(a, k * (1.0 - k) * 3.0 * edge * 0.8);
		a *= 1.0 - smoothstep(0.5, 1.0, k);
	} else if (mode == 5) {
		// wind: swirling bands drawn in round the source
		float ang = atan(rel.y, rel.x);
		float band = sin(ang * 3.0 + log(r + 0.5) * 6.0 + t * (3.0 + 5.0 * p));
		float s = smoothstep(0.7, 1.0, band);
		c = mix(t1, vec3(0.9, 1.0, 0.9), s);
		a = (0.1 + s * (0.25 + 0.4 * p)) * edge;
		a *= 1.0 - smoothstep(0.4, 1.0, k);
	} else if (mode == 6) {
		// dark: a pool creeping in from the hex rims, tendril-edged, violet lip
		float n = fbm(wp.xz * 1.4 + vec2(t * 0.15, -t * 0.1) + origin.w);
		float d = hexd(lp);
		float grow = p * 1.15;
		float m = (1.0 - d) * 0.6 + n * 0.8 - (1.0 - grow) * 0.9;
		float pool = smoothstep(0.0, 0.08, m);
		float lip = pool * (1.0 - smoothstep(0.08, 0.2, m));
		c = mix(vec3(0.02, 0.0, 0.05), t1, lip);
		a = (pool * (0.55 + 0.3 * p)) * edge;
		c = mix(c, t1 * 1.5, k * (1.0 - k) * 2.0);
		a *= 1.0 - smoothstep(0.5, 1.0, k);
	} else if (mode == 7) {
		// light: rings converging on each hex centre, the centre warming to gold
		float d = hexd(lp);
		float ring = smoothstep(0.75, 1.0, sin(d * 9.0 + t * (4.0 + 6.0 * p)));
		float core = (1.0 - smoothstep(0.0, 0.25 + 0.4 * p, d)) * p;
		c = mix(t1, vec3(1.0, 0.98, 0.85), core);
		a = (ring * 0.35 * (0.3 + 0.7 * p) + core * 0.7) * edge;
		c = mix(c, vec3(1.0), k * (1.0 - k) * 3.0);
		a = max(a, k * (1.0 - k) * 3.0 * edge * 0.7);
		a *= 1.0 - smoothstep(0.5, 1.0, k);
	} else if (mode == 8) {
		// shadow: a dark disc round the landing centre, growing and sharpening
		float rad = reach * (0.35 + 0.75 * p);
		float soft = mix(1.6, 0.25, p);
		float s = 1.0 - smoothstep(rad - soft, rad, r);
		c = vec3(0.0, 0.0, 0.02);
		a = s * (0.25 + 0.5 * p) * edge;
		a *= 1.0 - smoothstep(0.0, 0.35, k);
	} else {
		// lane: chevrons pointing down the lane, running forward, faster as the
		// charge nears; dirt scuffed along it
		vec2 d = normalize(dir.xy + vec2(1e-5));
		vec2 side = vec2(-d.y, d.x);
		float along = dot(rel, d);
		float across = dot(rel, side);
		float speed = 1.5 + 6.0 * p;
		float u = fract((along - t * speed) / 1.6);
		float chev = abs(u - 0.5 - abs(across) * 0.35);
		float arrow = (1.0 - smoothstep(0.1, 0.16, chev)) * (1.0 - smoothstep(1.2, 2.0, abs(across)));
		float ink = (1.0 - smoothstep(0.16, 0.22, chev)) * (1.0 - smoothstep(1.2, 2.0, abs(across))) - arrow;
		float scuff = fbm(vec2(along * 0.6, across * 3.0) + origin.w) * (1.0 - smoothstep(0.6, 2.0, abs(across)));
		c = mix(t2 * 0.6, t1 * 1.2, arrow);
		c = mix(c, vec3(0.04, 0.03, 0.02), clamp(ink, 0.0, 1.0));
		a = (0.25 * p + scuff * 0.35 * p + arrow * (0.6 + 0.4 * p) + ink * 0.7) * edge;
		a *= 1.0 - smoothstep(0.3, 1.0, k);
	}
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
