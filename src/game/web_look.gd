class_name HHWebLook
extends RefCounted
## Lane Z (H90-H92): what the browser build (the Compatibility renderer) needs
## to look like the desktop build (Forward+).
##
## The cause: gl_compatibility draws a shadow-casting DirectionalLight3D in a
## second, additive pass, and tonemaps + sRGB-encodes each pass before the two
## are summed. sRGB(ambient) + sRGB(sun) is much brighter and greener than
## sRGB(ambient + sun), so a sunlit floor over sky ambient blows out to near-
## white and dark colours (the pond's water) go pale. The fix: on the web the
## GK surfaces (arena ground, props, water, scenery) use the *_web shader
## variants, which switch the engine's ambient off and add an ambient of their
## own inside the sun's light() call, so both are summed in linear space and
## tonemapped once, as on desktop. This class turns an Environment's sky into
## that ambient (the hh_web_* shader globals). Nothing here runs on desktop.

## Fitted against Forward+ renders of the four arenas (design/web, H91):
## the sky-gradient estimate below reads ~1.4x the engine's sky irradiance,
## and a flat colour ambient (the cave) reads a little dim.
const SKY_FIT := 0.72
const COLOR_FIT := 1.3
const GLOBALS :=["hh_web_amb_up", "hh_web_amb_side", "hh_web_amb_down", "hh_web_refl"]


## True when the running renderer is the Compatibility one (the web export,
## or a desktop run with --rendering-method gl_compatibility).
static func active() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Declare the shader globals the *_web shaders read (idempotent). Must run
## before the first *_web shader compiles: GKMaterials calls it.
static func ensure_globals() -> void:
	if _declared:                 # (global_shader_parameter_get_list is editor-only)
		return
	_declared = true
	for g in GLOBALS:
		RenderingServer.global_shader_parameter_add(g, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	RenderingServer.global_shader_parameter_add("hh_web_fog", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)


static var _declared := false


## Set the web ambient from `env` (the arena's or the map's WorldEnvironment):
## a sky ambient becomes three irradiance colours (up, side, down) from the
## procedural sky's gradient; a colour ambient is used as it is. No-op on desktop.
static func apply_env(env: Environment) -> void:
	if env == null or not active():
		return
	ensure_globals()
	var amb_k := HHTune.value("web_ambient")
	var up := Vector3.ZERO
	var side := Vector3.ZERO
	var down := Vector3.ZERO
	var refl := Vector3.ZERO
	var mat: ProceduralSkyMaterial = null
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		mat = env.sky.sky_material
	if mat != null:
		var top := _lin(mat.sky_top_color) * mat.sky_energy_multiplier
		var hor := _lin(mat.sky_horizon_color) * mat.sky_energy_multiplier
		var gh := _lin(mat.ground_horizon_color) * mat.ground_energy_multiplier
		var gb := _lin(mat.ground_bottom_color) * mat.ground_energy_multiplier
		var sky_avg := top * 0.55 + hor * 0.45
		var ground_avg := gh * 0.6 + gb * 0.4
		up = top * 0.6 + hor * 0.4
		side = sky_avg * 0.5 + ground_avg * 0.5
		down = ground_avg
		refl = sky_avg
	match env.ambient_light_source:
		Environment.AMBIENT_SOURCE_COLOR:
			var c := _lin(env.ambient_light_color) * env.ambient_light_energy * COLOR_FIT
			up = c
			side = c
			down = c
		Environment.AMBIENT_SOURCE_DISABLED:
			up = Vector3.ZERO
			side = Vector3.ZERO
			down = Vector3.ZERO
		_:
			# sky (or "background" = sky here): the engine mixes in the flat
			# colour as the sky contribution drops
			var k := env.ambient_light_sky_contribution
			var c := _lin(env.ambient_light_color) * env.ambient_light_energy * (1.0 - k)
			up = up * k * SKY_FIT + c
			side = side * k * SKY_FIT + c
			down = down * k * SKY_FIT + c
	RenderingServer.global_shader_parameter_set("hh_web_amb_up", up * amb_k)
	RenderingServer.global_shader_parameter_set("hh_web_amb_side", side * amb_k)
	RenderingServer.global_shader_parameter_set("hh_web_amb_down", down * amb_k)
	RenderingServer.global_shader_parameter_set("hh_web_refl", refl * HHTune.value("web_reflection"))
	# distance fog: drawn by the *_web shaders in the sun's pass; the engine's
	# own fog (first pass) would add on top in sRGB as a pale veil, so it goes off
	var fog := Vector4.ZERO
	if env.fog_enabled:
		var fc := _lin(env.fog_light_color) * env.fog_light_energy
		fc = fc.lerp(refl, clampf(env.fog_aerial_perspective, 0.0, 1.0))   # aerial perspective takes the sky's colour
		fog = Vector4(fc.x, fc.y, fc.z, env.fog_density * HHTune.value("web_fog"))
		env.fog_enabled = false
		env.set_meta("hh_web_fog", fog)             # a second apply_env (the F1 panel) still knows it
	elif env.has_meta("hh_web_fog"):
		fog = env.get_meta("hh_web_fog")
	RenderingServer.global_shader_parameter_set("hh_web_fog", fog)


static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)
