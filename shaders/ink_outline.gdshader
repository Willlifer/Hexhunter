shader_type spatial;
// H84 (Lane Y): the comic ink line. An inverted hull: HHInk draws a copy of
// a body (smoothed normals, the same skin) with this material; front faces
// are culled, the back faces are pushed out along the normal so a dark rim
// shows round the silhouette. The push is a constant number of PIXELS (scaled
// to a 1080-line screen), so the line reads the same at the gameplay camera
// and never fattens up close; `max_world` caps it in metres for very far or
// very small screens, `min_world` keeps a hairline on huge close-ups.
// The width is a fraction of the screen height, so it holds at any resolution.
// Works in Forward+ and Compatibility (no instance uniforms, no screen reads).
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 ink_color : source_color = vec4(0.045, 0.035, 0.05, 1.0);
uniform float width_px = 2.2;     // line width in pixels at 1080 lines
uniform float max_world = 0.03;   // metres
uniform float min_world = 0.0015; // metres
uniform float push_back = 0.6;    // fraction of the width moved away from the camera (cleaner inner lines)

void vertex() {
	vec4 vpos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// one 1080th of the screen height in metres at this depth, measured by
	// projecting a 1 m step (works for any projection; VIEWPORT_SIZE is not
	// usable in vertex())
	vec4 c0 = PROJECTION_MATRIX * vpos;
	vec4 c1 = PROJECTION_MATRIX * (vpos + vec4(0.0, 1.0, 0.0, 0.0));
	float ndc_per_m = abs(c1.y / c1.w - c0.y / c0.w);
	float px_world = (2.0 / 1080.0) / max(ndc_per_m, 1e-5);
	float w = clamp(width_px * px_world, min_world, max_world);
	vpos.xyz += vn * w;
	vpos.z -= w * push_back;
	POSITION = PROJECTION_MATRIX * vpos;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
