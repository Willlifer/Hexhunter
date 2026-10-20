class_name HHArenaStage
extends RefCounted
## Scene-side helpers shared by the bench and the preview tools: a sun and
## sky from a GKAsset's `lights`, and the hex-underlay overlay (one outline
## per HHArena cell, coloured by kind). Nothing here is used by the game.

const OVERLAY_LIFT := 0.08
const KIND_COLOR := {
	"floor": Color(0.95, 0.9, 0.5, 0.9),
	"water": Color(0.35, 0.7, 1.0, 0.9),
	"deep": Color(0.25, 0.2, 0.8, 0.95),
	"pad": Color(0.4, 1.0, 0.4, 0.95),
	"cover": Color(1.0, 0.5, 0.1, 1.0),
	"edge": Color(1.0, 0.25, 0.25, 0.9),
	"rock": Color(0.7, 0.7, 0.7, 0.9),
	"pillar": Color(0.55, 0.55, 0.6, 0.95),
	"vent": Color(1.0, 0.55, 0.1, 0.95),
	"lava": Color(1.0, 0.15, 0.1, 1.0),
	"sun": Color(1.0, 0.98, 0.7, 1.0),
	"shade": Color(0.2, 0.85, 0.8, 0.95),
	"tree": Color(0.1, 0.4, 0.15, 0.95),
}


static func sun(lights: Dictionary) -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.name = "Sun"
	var dir: Array = lights.get("sun_dir_deg", [-52.0, 35.0])
	s.rotation_degrees = Vector3(float(dir[0]), float(dir[1]), 0.0)
	s.light_energy = float(lights.get("sun_energy", 1.3))
	s.light_color = Color(str(lights.get("sun_color", "#ffffff")))
	s.shadow_enabled = true
	s.directional_shadow_max_distance = 120.0
	return s


static func sky(lights: Dictionary) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sk := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(str(lights.get("sky_top", "#5a8ce6")))
	mat.sky_horizon_color = Color(str(lights.get("sky_horizon", "#c7d9ea")))
	mat.ground_bottom_color = Color(str(lights.get("ground_bottom", "#333833")))
	mat.ground_horizon_color = Color(str(lights.get("ground_horizon", "#999e94")))
	mat.sun_angle_max = 20.0
	mat.sky_curve = float(lights.get("sky_curve", 0.15))
	mat.ground_curve = float(lights.get("ground_curve", 0.02))
	sk.sky_material = mat
	env.sky = sk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(lights.get("ambient", 0.8))
	if lights.has("ambient_color"):                 # H753: a biome's own fill (the cave's warm bounce)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(str(lights.ambient_color))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(lights.get("exposure", 1.0))
	env.glow_enabled = lights.has("glow")             # H753: lava and torches bloom a little
	if env.glow_enabled:
		env.glow_intensity = float(lights.glow)
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	if lights.has("fog"):
		var fog: Dictionary = lights.fog
		env.fog_enabled = true
		env.fog_light_color = Color(str(fog.get("color", "#c0c0c0")))
		env.fog_density = float(fog.get("density", 0.01))
		env.fog_sky_affect = float(fog.get("sky_affect", 0.4))
		env.fog_aerial_perspective = float(fog.get("aerial", 0.0))
		if fog.has("height"):                     # low-lying haze (the caldera's cloud deck, the glade's mist)
			env.fog_height = float(fog.height)
			env.fog_height_density = float(fog.get("height_density", 0.1))
	var we := WorldEnvironment.new()
	we.name = "Sky"
	we.environment = env
	return we


## Point lights from an asset's markers: a marker "torch_3" takes its colour,
## energy and range from `lights.points.torch` (the prefix before the last
## "_N"); markers without a `points` entry make no light.
static func point_lights(asset: GKAsset) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	var points: Dictionary = asset.lights.get("points", {})
	if points.is_empty():
		return out
	var names := asset.markers.keys()
	names.sort()
	for n in names:
		var name := str(n)
		var cut := name.rfind("_")
		if cut <= 0:
			continue
		var prefix := name.substr(0, cut)
		if not points.has(prefix):
			continue
		var spec: Dictionary = points[prefix]
		var l := OmniLight3D.new()
		l.name = name
		l.transform = asset.markers[n]
		l.light_color = Color(str(spec.get("color", "#ffffff")))
		l.light_energy = float(spec.get("energy", 2.0))
		l.omni_range = float(spec.get("range", 10.0))
		l.omni_attenuation = float(spec.get("attenuation", 1.4))
		l.shadow_enabled = bool(spec.get("shadow", false))
		out.append(l)
	return out


## The kind an overlay colours a cell by: deep water and cover pads get their own.
static func overlay_kind(c: Dictionary) -> String:
	var k := str(c.get("kind", "floor"))
	if k == "water" and not bool(c.get("walkable", true)):
		return "deep"
	if k == "pad" and bool(c.get("cover", false)):
		return "cover"
	return k


## Every cell as a hex outline, floating over the water where the bed is below it.
static func overlay(a: HHArena, water_level: float = 0.0) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var keys := a.cells.keys()
	keys.sort()
	for key in keys:
		var h: Vector2i = key
		var c: Dictionary = a.cells[h]
		var col: Color = KIND_COLOR.get(overlay_kind(c), Color.MAGENTA)
		var w := HHHex.to_world(h, HHArena.HEX)
		var corners := HHHex.corners(Vector3(w.x, 0.0, w.y), HHArena.HEX * 0.9)
		for i in 6:
			var p0 := corners[i]
			var p1 := corners[(i + 1) % 6]
			p0.y = maxf(a.height_at(p0.x, p0.z), water_level) + OVERLAY_LIFT
			p1.y = maxf(a.height_at(p1.x, p1.z), water_level) + OVERLAY_LIFT
			im.surface_set_color(col)
			im.surface_add_vertex(p0)
			im.surface_set_color(col)
			im.surface_add_vertex(p1)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "HexOverlay"
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Save the root viewport's last drawn frame to `path` (absolute or res://).
static func save_frame(vp: Viewport, path: String) -> bool:
	var img := vp.get_texture().get_image()
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var err := img.save_png(abs)
	print("render: %s (%s)" % [abs, "ok" if err == OK else error_string(err)])
	return err == OK
