// Lane Z (H90): the Compatibility (web) renderer's lighting for GK surfaces.
// In gl_compatibility a shadowed DirectionalLight3D is drawn in a second,
// additive pass, and each pass is tonemapped and converted to sRGB on its
// own before they are summed. sRGB(ambient) + sRGB(sun) is far brighter and
// greener than sRGB(ambient + sun), so a sunlit floor over sky ambient blows
// out to near-white (Godot docs: "lights with shadows are rendered in sRGB
// space"). These variants switch the engine's ambient off and add the
// ambient themselves inside the sun's light() call instead, so ambient and
// sun are summed in linear space in ONE pass, tonemapped once, as Forward+
// does. Distance fog has the same problem (it is mixed in the first pass),
// so it moves here too. HHWebLook sets the hh_web_* globals from the sky.
// Only the gl_compatibility build uses these shaders (GKMaterials.web()).

global uniform vec3 hh_web_amb_up;      // sky irradiance on an up-facing surface (linear)
global uniform vec3 hh_web_amb_side;    // ... on a wall
global uniform vec3 hh_web_amb_down;    // ... on an overhang (ground bounce)
global uniform vec3 hh_web_refl;        // the sky a glossy surface mirrors
global uniform vec4 hh_web_fog;         // rgb = fog colour (linear), a = density (the engine's fog is off on the web)

varying float hh_web_dist;              // camera distance, written by fragment() (light() has no VERTEX)

vec3 hh_web_ambient(vec3 n_world) {
	float y = clamp(n_world.y, -1.0, 1.0);
	return y >= 0.0 ? mix(hh_web_amb_side, hh_web_amb_up, y) : mix(hh_web_amb_side, hh_web_amb_down, -y);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += ndl * ATTENUATION * lc;
	// GGX specular, the engine's shape near enough
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float d = a * a / (PI * pow(ndh * ndh * (a * a - 1.0) + 1.0, 2.0));
	float k = a * 0.5;
	float vis = 0.25 / ((ndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	vec3 f0 = mix(vec3(0.16 * spec * spec), ALBEDO, METALLIC);
	vec3 f = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += ndl * ATTENUATION * lc * d * vis * f * PI * SPECULAR_AMOUNT;
	if (LIGHT_IS_DIRECTIONAL) {
		// the engine's ambient and fog, moved into the sun's pass (see the header)
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 fr = f0 + (max(vec3(1.0 - ROUGHNESS), f0) - f0) * pow(1.0 - ndv, 5.0);
		float fog = 1.0 - exp(-hh_web_dist * hh_web_fog.a);
		DIFFUSE_LIGHT = (DIFFUSE_LIGHT + hh_web_ambient(nw)) * (1.0 - fog);
		SPECULAR_LIGHT = (SPECULAR_LIGHT + hh_web_refl * fr) * (1.0 - fog) + hh_web_fog.rgb * fog;
	}
}
