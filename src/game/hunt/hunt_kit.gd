class_name HHHuntKit
extends RefCounted
## Shared helpers for the hunt screens (Lane H): the hunt's feel numbers
## (TUNE, registered under "hunt_" like the weapons), the arena loader (a
## copy of boot.gd's `_load_arena`, since Lane H may not edit boot), bodies
## by duck type, the per-biome disturbance palette, and the pulse ring /
## mote emitter both the map and the ambush use.

const TUNE := {
	"run_mps": 8.0,            # the hunter's pace on the map (the fight's run)
	"approach_m": 4.0,         # within this of the disturbance, the ambush starts
	"map_span_m": 200.0,       # the region, edge to edge
	"map_site_r": 50.0,        # sites sit this far from the centre
	"map_cam_dist": 170.0,     # world metres (the rig runs under a x5 parent, H502): all four sites in frame
	"map_cam_pitch": 64.0,
	"pulse_period": 1.6,       # one disturbance ring per this many seconds
	"pulse_radius_m": 7.0,     # the ring's full size on the map
	"ambush_seconds": 3.8,     # the whole cutscene
	"ambush_burst_at": 0.9,    # when the monster erupts
	"ambush_burst_s": 0.7,     # how long the eruption takes
	"ambush_name_at": 1.7,     # when the name slams in
	"ambush_cam_dist": 20.0,
}
static var _registered := false


static func t(key: String) -> float:
	if not _registered:
		_registered = true
		HHTune.register("hunt", TUNE)
	return HHTune.value("hunt_" + key)


## How each biome's disturbance looks: the ring colour, the motes, the verb.
const DISTURBANCE := {
	"pond":    { "ring": Color(0.95, 0.98, 1.0, 0.95), "mote": Color(0.85, 0.95, 1.0), "verb": "ripples", "rise": 0.6, "name": "ripple" },   # near-white: light blue vanished on the water
	"cave":    { "ring": Color(0.95, 0.85, 0.65, 0.9), "mote": Color(0.7, 0.6, 0.45), "verb": "rumbles", "rise": 1.2, "name": "dust" },     # pale: it sits on dark rock
	"glade":   { "ring": Color(1.0, 0.9, 0.4, 0.85), "mote": Color(1.0, 0.85, 0.3), "verb": "shivers", "rise": 1.6, "name": "pollen" },
	"caldera": { "ring": Color(1.0, 0.45, 0.15, 0.9), "mote": Color(1.0, 0.55, 0.15), "verb": "smoulders", "rise": 2.2, "name": "ember" },
}

## Each monster's threat clip for the ambush (its roar / tell), by name.
const ROAR := { "swampfang": "frill_roar", "colambros": "rattle_roar", "rimeslithe": "roar", "spirewalker": "pollen_shake" }


static func disturbance(biome: String) -> Dictionary:
	return DISTURBANCE.get(biome, DISTURBANCE.pond)


## { arena: HHArena, asset: GKAsset | null }: boot.gd's loader, copied (H500).
static func load_arena(id: String, seed: int) -> Dictionary:
	var path := "res://arenas/%s.json" % id
	if id != "round" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			if d.has("gen"):
				var gen: Dictionary = d.gen
				var gp := "res://src/arena/gen/%s_gen.gd" % str(gen.get("id", id))
				if ResourceLoader.exists(gp):
					var s: GDScript = load(gp)
					var both: Dictionary = s.build_both(gen.get("params", {}))
					var ar: HHArena = both.arena
					if ar.authored.is_empty():
						ar.authored = Array(d.get("authored", ar.spawns.get("authored", [])))
					return { "arena": ar, "asset": both.asset }
			return { "arena": HHArena.from_dict(d), "asset": null }
		push_warning("hunt: arena '%s' failed to parse, using round" % id)
	return { "arena": HHArena.round_flat(seed), "asset": null }


## The hunter: Lane B's rigged body when it exists, else a capsule with a nose.
static func hunter_body(weapon: String) -> Node3D:
	if ResourceLoader.exists("res://src/game/anim/player_body.gd"):
		var s: GDScript = load("res://src/game/anim/player_body.gd")
		var body: Node3D = s.new()
		if body.has_method("build") and body.build(weapon):
			return body
		body.free()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = HHLook.RIG_HEIGHT
	mi.mesh = cm
	mi.position.y = HHLook.RIG_HEIGHT * 0.5
	mi.material_override = HHLook.flat(Color(0.92, 0.92, 0.9))
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.5)
	nose.mesh = bm
	nose.position = Vector3(0, 0.6, 0.5)
	nose.material_override = HHLook.flat(Color(0.9, 0.5, 0.2))
	mi.add_child(nose)
	root.add_child(mi)
	return root


## A monster: Lane E's body when it exists and builds, else a dark lozenge.
static func monster_body(id: String) -> Node3D:
	if ResourceLoader.exists("res://src/monster/monster_body.gd"):
		var s: GDScript = load("res://src/monster/monster_body.gd")
		var body: Node3D = s.new()
		if body.has_method("build") and body.build(id):
			return body
		body.free()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	mi.scale = Vector3(2.6, 1.6, 3.4)
	mi.position.y = 1.6
	mi.material_override = HHLook.flat(Color(0.3, 0.35, 0.6))
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	root.add_child(mi)
	return root


## A flat ring (annulus) in the XZ plane, radius 1, unshaded, for pulses.
static func ring(color: Color, width: float = 0.18, sides: int = 40) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in sides + 1:
		var a := TAU * float(i) / float(sides)
		var c := cos(a)
		var s := sin(a)
		im.surface_add_vertex(Vector3(c * (1.0 - width), 0.0, s * (1.0 - width)))
		im.surface_add_vertex(Vector3(c, 0.0, s))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := HHLook.flat(color, true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 10                       # after the water's alpha surface
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Rising motes (dust, pollen, embers, spray) in a biome's colour.
static func motes(biome: String, amount: int = 40, radius: float = 2.5) -> CPUParticles3D:
	var d := disturbance(biome)
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, float(d.rise), 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.2
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	p.color = d.mote
	var m := HHLook.flat(Color.WHITE)
	m.vertex_color_use_as_albedo = true           # the particle colour, not the material's
	p.material_override = m
	return p


## A big outlined label for the HUD layers (names, verdicts).
static func label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## The point on a heightfield under a screen position: the camera ray marched
## onto `height.call(x, z)`; NO_POS when the ray misses the ground.
static func ground_under(rig: HHCameraRig, screen_pos: Vector2, height: Callable) -> Vector3:
	if rig == null or rig.cam == null:
		return HHSim.NO_POS
	var r := rig.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-4:
		return HHSim.NO_POS
	var p := o + d * (-o.y / d.y)
	for i in 6:
		var h: float = height.call(p.x, p.z)
		var tt := (h - o.y) / d.y
		if tt <= 0.0:
			break
		p = o + d * tt
	return p
