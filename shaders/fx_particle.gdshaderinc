// Lane FX (H700): one sprite per MultiMesh instance (HHFxParticles).
// The instance transform carries the centre and the size (basis scale);
// INSTANCE_CUSTOM.xyz is a world-space streak vector (0 = a round sprite,
// else the sprite is stretched along it, centred on the instance, so
// wind streaks and embers read as motion); INSTANCE_CUSTOM.w the shape:
//   0 soft dot   1 streak   2 puff (smoke / dust / haze, noisy edge)
//   3 shard (sharp diamond)   4 flake (crisp mote)   5 ring (thin annulus)
//   6 spark (hot core, short cross)
// COLOR is the instance colour, already linear (the script converts).
// Camera-facing, built in view space (skip_vertex_transform).

varying vec4 vcol;
varying vec2 q;            // -1..1 across the sprite (x along the streak)
varying float vshape;
varying float vseed;

float fxp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fxp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fxp_hash(i), fxp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fxp_hash(i + vec2(0.0, 1.0)), fxp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cv = (VIEW_MATRIX * vec4(c, 1.0)).xyz;
	vec3 st = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 corner = UV * 2.0 - 1.0;
	float L = length(st.xy);
	vec3 off;
	if (L > s * 0.25) {
		vec2 dir = st.xy / L;
		vec2 side = vec2(-dir.y, dir.x);
		off = vec3(dir * corner.x * (L * 0.5 + s) + side * corner.y * s, 0.0);
	} else {
		off = vec3(corner * s, 0.0);
	}
	VERTEX = cv + off;
	NORMAL = vec3(0.0, 0.0, 1.0);
	q = corner;
	vcol = COLOR;
	vshape = INSTANCE_CUSTOM.w;
	vseed = fract(c.x * 3.17 + c.z * 1.31);
}

// Coverage 0..1 of the shape at q.
float fxp_shape(float shape, vec2 p, float t) {
	float r = length(p);
	if (shape < 0.5) {                     // soft dot
		return pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
	} else if (shape < 1.5) {              // streak: soft across, tapered at the ends
		float across = 1.0 - smoothstep(0.15, 1.0, abs(p.y));
		float along = 1.0 - smoothstep(0.35, 1.0, abs(p.x));
		return across * along;
	} else if (shape < 2.5) {              // puff
		float n = fxp_noise(p * 2.2 + vec2(vseed * 17.0, t * 0.35 + vseed * 9.0));
		float edge = 1.0 - smoothstep(0.35 + 0.35 * n, 1.0, r);
		return edge * (0.65 + 0.35 * n);
	} else if (shape < 3.5) {              // shard
		float d = abs(p.x) * 1.0 + abs(p.y) * 2.2;
		return 1.0 - smoothstep(0.85, 1.0, d);
	} else if (shape < 4.5) {              // flake
		return 1.0 - smoothstep(0.45, 0.75, r);
	} else if (shape < 5.5) {              // ring
		return 1.0 - smoothstep(0.0, 0.14, abs(r - 0.82));
	}
	// spark: hot core and a short cross
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	float cross = (1.0 - smoothstep(0.0, 0.08, abs(p.x))) * (1.0 - smoothstep(0.3, 1.0, abs(p.y)))
		+ (1.0 - smoothstep(0.0, 0.08, abs(p.y))) * (1.0 - smoothstep(0.3, 1.0, abs(p.x)));
	return clamp(core + cross * 0.7, 0.0, 1.0);
}
