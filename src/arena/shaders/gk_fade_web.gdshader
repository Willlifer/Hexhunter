// Lane Z (H90): the web (gl_compatibility) variant of gk_fade.gdshader,
// identical but for its lighting: see shaders/gk_web_light.gdshaderinc.
// Lane ENV (H759): gk_surface with a camera-distance dither fade. Scenery
// that stands between the 30 m fight camera and the hunter (skirt trees,
// the cave's overhang, canopies) dissolves when it is nearer the camera than
// `fade_near` and is whole past `fade_far`, so the dressing can be tall at
// the horizon without ever hiding the player or a telegraph.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

#include "res://shaders/gk_surface.gdshaderinc"
#include "res://shaders/gk_web_light.gdshaderinc"

uniform float fade_near = 16.0;
uniform float fade_far = 26.0;

void vertex() {
	if (world) {
		P = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		N = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	} else {
		P = VERTEX;
		N = NORMAL;
	}
}

float bayer4(vec2 fc) {
	ivec2 p = ivec2(mod(fc, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	hh_web_dist = length(VERTEX);
	float t = smoothstep(fade_near, fade_far, length(VERTEX));
	if (t < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 c;
	float r;
	float m;
	float hgt;
	gk_surface(P, normalize(N), c, r, m, hgt);
	NORMAL = gk_bump(VERTEX, NORMAL, hgt);
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	SPECULAR = spec;
}
