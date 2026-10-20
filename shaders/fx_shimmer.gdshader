// Lane FX (H703): heat shimmer. A vertical card (QuadMesh, billboarded about
// Y) that bends what is behind it, with a faint warm wash at its foot so the
// cone still shows where the screen behind is flat. `strength` 0..1 per
// instance (INSTANCE_CUSTOM.x in a MultiMesh).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 warm : source_color = vec4(1.0, 0.45, 0.12, 1.0);

varying float vstr;

void vertex() {
	vstr = INSTANCE_CUSTOM.x;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = length(right) > 1e-4 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 sz = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 w = c + right * VERTEX.x * sz.x + vec3(0.0, (VERTEX.y + 0.5) * sz.y, 0.0);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float edge = (1.0 - smoothstep(0.3, 0.5, abs(uv.x - 0.5))) * smoothstep(0.0, 0.15, 1.0 - uv.y) * smoothstep(0.0, 0.1, uv.y);
	float w = sin(uv.y * 26.0 + TIME * 9.0 + uv.x * 7.0) * 0.5 + sin(uv.y * 41.0 - TIME * 13.0) * 0.5;
	vec2 off = vec2(w * 0.006, w * 0.003) * vstr * edge;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	float foot = uv.y * uv.y;                 // QuadMesh UV.y is 1 at the bottom
	ALBEDO = mix(behind, pow(warm.rgb, vec3(2.2)), foot * 0.22 * vstr);
	ALPHA = edge * clamp(vstr, 0.0, 1.0);
}
