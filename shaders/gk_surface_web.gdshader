// Lane Z (H90): the web (gl_compatibility) variant of gk_surface.gdshader,
// identical but for its lighting: see shaders/gk_web_light.gdshaderinc.
// Gauntlet Kit surfaces (GKMaterials), opaque: the patterns and the relief
// live in gk_surface.gdshaderinc (shared with gk_surface_clear.gdshader).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

#include "res://shaders/gk_surface.gdshaderinc"
#include "res://shaders/gk_web_light.gdshaderinc"

void vertex() {
	if (world) {
		P = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		N = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	} else {
		P = VERTEX;
		N = NORMAL;
	}
}

void fragment() {
	hh_web_dist = length(VERTEX);
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
