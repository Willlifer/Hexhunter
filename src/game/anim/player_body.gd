class_name HHPlayerBody
extends Node3D
## The player's body at run time (Lane B): instances art/characters/base_rig.glb
## (tools/blender/build_base_rig.py, never hand-edited), hangs the weapon glbs
## on the rig's sockets, and plays procedural clips: GDScript pose functions of
## time (one script per weapon, HHClipsLance / HHClipsDaggers / HHClipsBow,
## sharing HHClipsShared) that bend bones about model axes, plus two-bone IK
## for the feet (ground contacts) and the hands (the off hand on the lance
## shaft, the draw hand on the bowstring). Lane E's HHMonsterBody pattern.
##
##   var b := HHPlayerBody.new()
##   add_child(b)
##   b.build("lance")                   # rig + weapon(s)
##   b.bind(sim, "p1")                  # optional: speed, target, guard from the sim
##   b.on_event(e, sim)                 # every sim event about the player
##   b.update(delta)                    # every frame, after position / rotation.y are set
##
## HHFight sets `position = u.pos` and `rotation.y = u.facing` each frame and
## calls update(); locomotion (idle / walk / run) is chosen from the body's
## own position delta, so it also works unbound. Bound, the body reads the
## unit for intent: a target turns the upper body toward it, `guard` holds
## the guard clip, `windup` holds a wind-up at its contact pose.
##
## Model space: origin on the ground between the feet, +Y up, +Z forward, +X
## the character's left. Rest is an A-pose.
##
## POSE API for clip functions (offsets from rest, accumulate per sample):
##   rot(bone, Vector3(pitch, yaw, roll) degrees)  about the MODEL axes X, Y, Z
##       (right-hand rule) at the bone's head. A hanging limb (arm, leg)
##       swings its tip FORWARD with -pitch; the knee bends with +pitch on the
##       shin, the elbow with -pitch on the forearm; +roll lifts a hanging
##       tip to the character's left; +yaw turns a tip to the left.
##   move(bone, Vector3)                     model-metre translation
##   bend(chain, total, falloff)             spread a rotation along a chain
##   ik_foot(side, pos, pitch_deg, w)        plant the ankle at a model point, sole level (+pitch = toe down)
##   ik_hand(side, pos, anchor, w, aim)      reach the wrist to a point; `anchor` = a socket whose
##                                           posed frame `pos` is in ("" = model); `aim` = the hand's
##                                           global basis after the reach (identity = keep FK)
##   nock(true)                              show the arrow between the hands (bow draw)
##
## Clip tables: `clips(weapon)` is the CLIPS dictionary of that weapon's set
## ({ clip: { duration (s), contact_tick (30 Hz tick when damage lands, -1
## none), loop, key (preview time), stride (m per cycle for loco), note } }).

const RIG_PATH := "res://art/characters/base_rig.glb"
const RIG_JSON := "res://art/characters/rig.json"
const WEAPON_DIR := "res://art/weapons/"              ## Lane A's coloured set (L-13; bw_temp retired)
const WEAPON_JSON := WEAPON_DIR + "weapons.json"
## Weapon id (the sim's `weapon`, the clip set) -> Lane A's manifest row.
## The manifest keys rows by model (karambit); the arrow is a row of class
## "projectile" in the same table.
const WEAPON_ROWS := { "lance": "lance", "daggers": "karambit", "bow": "bow" }
## Per-role look for the weapon glbs (vertex COLOR carries the palette).
const WEAPON_ROUGHNESS := { "steel": 0.32, "wood": 0.75, "wrap": 0.85, "feather": 0.7, "gem": 0.2, "string": 0.6 }
const WEAPON_METALLIC := { "steel": 0.55, "gem": 0.1 }
const CLIP_SETS := {
	"lance": "res://src/game/anim/clips_lance.gd",
	"daggers": "res://src/game/anim/clips_daggers.gd",
	"bow": "res://src/game/anim/clips_bow.gd",
}
const FADE := 0.12                  ## cross-fade between clips (s)
const FADE_READY := 0.3             ## H60: a string that lapses eases out of its ready loop this slowly
const AIM_LAG := 0.12               ## upper-body turn toward the target (s)
const AIM_MAX_DEG := 55.0
const LOCO_SMOOTH := 0.08           ## speed smoothing (s)
const HURT_CAUSES_IGNORED := ["fire", "burn", "poison", "dark", "fire_cross"]
const LIMBS := {
	"foot_l": ["thigh_l", "shin_l", "foot_l"], "foot_r": ["thigh_r", "shin_r", "foot_r"],
	"hand_l": ["upper_arm_l", "forearm_l", "hand_l"], "hand_r": ["upper_arm_r", "forearm_r", "hand_r"],
}
const ROUGHNESS := { "skin": 0.75, "leather": 0.8, "cloak": 0.95, "boots": 0.7, "straps": 0.6 }

static var _rig_json := {}
static var _weapon_json := {}

var sim: HHSim = null
var unit_id := ""
var weapon_id := ""
var row := {}                       ## the weapon's manifest row
var model: Node3D
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var weapon_main: Node3D = null       ## on the main-hand socket (bow: the left hand)
var weapon_off: Node3D = null        ## the pair's second blade
var arrow: Node3D = null             ## nocked only while a draw clip asks for it
var _string: MeshInstance3D = null   ## the drawn bowstring (model space), while nocked
var _string_surfaces: Array = []     # [MeshInstance3D, surface] of the bow's straight string
var clip := ""
var time := 0.0
var loop := true
var speed := 1.0
var finished_clip := ""
var speed_mps := 0.0                ## smoothed ground speed from the position delta
var loco := "idle"                  ## the locomotion loop the body would be in
var aim_yaw := 0.0                  ## upper-body turn toward the target (rad)
var wielded := false                ## stance: weapon up (a target, or an attack within the last seconds)

var _set: GDScript
var _bones := {}                    # name -> index
var _rest := {}                     # index -> Basis (global rest, model space)
var _sockets := {}                  # name -> Node3D
var _sample := {}                   # index -> [Quaternion, Vector3]
var _ik := {}                       # "foot_l" ... -> { pos, pitch / anchor / aim, w }
var _nock := false
var _prev_clip := ""
var _prev_time := 0.0
var _prev_loop := true
var _fade := 0.0
var _resume := ""
var _hold_at := -1.0                # a wind-up holds here until released
var _held := false
var _last_pos := Vector3(INF, INF, INF)
var _wield_timer := 0.0
var _dead := false
var _land_clip := ""                # what the next `land` plays (set by `leap`)
var _fade_len := FADE               # this cross-fade's length (H60: longer out of a string's ready loop)
var charge_frac := 0.0              ## H60: the held charge, 0 (tap) .. 1 (full), for the brace's tremor
var _pending_clip := ""             # H60: a release that starts after a beat (the brace holds first)
var _pending_in := 0.0
var _pending_from := 0.0


# ------------------------------------------------------------------ manifests

static func rig_json() -> Dictionary:
	if _rig_json.is_empty():
		var txt := FileAccess.get_file_as_string(RIG_JSON)
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_rig_json = parsed if parsed is Dictionary else {}
	return _rig_json


static func weapon_json() -> Dictionary:
	if _weapon_json.is_empty():
		var txt := FileAccess.get_file_as_string(WEAPON_JSON)
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_weapon_json = parsed if parsed is Dictionary else {}
	return _weapon_json


static func weapon_row(weapon: String) -> Dictionary:
	var w: Dictionary = weapon_json().get("weapons", {})
	return w.get(WEAPON_ROWS.get(weapon, weapon), {})


## A projectile row (the arrow): Lane A keeps it in the weapons table as
## class "projectile"; an older manifest kept a "projectiles" table.
static func projectile_row(id: String) -> Dictionary:
	var w: Dictionary = weapon_json().get("weapons", {})
	if w.has(id):
		return w[id]
	var pr: Dictionary = weapon_json().get("projectiles", {})
	return pr.get(id, {})


static func clip_set(weapon: String) -> GDScript:
	var path: String = CLIP_SETS.get(weapon, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func clips(weapon: String) -> Dictionary:
	var s := clip_set(weapon)
	if s == null:
		return {}
	var c: Variant = s.get("CLIPS")
	return c if c is Dictionary else {}


static func clip_list(weapon: String) -> PackedStringArray:
	return PackedStringArray(clips(weapon).keys())


## The clip a skill key plays for a weapon (the set's SKILL_CLIPS).
static func skill_clip(weapon: String, key: String) -> String:
	var s := clip_set(weapon)
	if s == null:
		return ""
	var m: Variant = s.get("SKILL_CLIPS")
	return str((m as Dictionary).get(key, "")) if m is Dictionary else ""


# ------------------------------------------------------------------ build

## Instance the rig and hang the weapon. False (with an error) if missing.
func build(weapon: String) -> bool:
	if model == null:
		var scene := load(RIG_PATH) as PackedScene
		if scene == null:
			push_error("HHPlayerBody: cannot load %s (run --import?)" % RIG_PATH)
			return false
		model = scene.instantiate() as Node3D
		model.name = "model"
		add_child(model)
		var sk := model.find_children("*", "Skeleton3D", true, false)
		if sk.is_empty():
			push_error("HHPlayerBody: no Skeleton3D in %s" % RIG_PATH)
			return false
		skeleton = sk[0]
		for i in skeleton.get_bone_count():
			_bones[skeleton.get_bone_name(i)] = i
			_rest[i] = skeleton.get_bone_global_rest(i).basis
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mi)
			_apply_materials(mi)
		for n in model.find_children("socket_*", "Node3D", true, false):
			_sockets[str(n.name).trim_prefix("socket_")] = n
		for s in rig_json().get("sockets", {}):
			if not _sockets.has(str(s).trim_prefix("socket_")):
				push_warning("HHPlayerBody: socket %s missing from the rig" % s)
	return equip(weapon)


## Swap the weapon (and its clip set). The rig stays.
func equip(weapon: String) -> bool:
	for n in [weapon_main, weapon_off, arrow, _string]:
		if n != null:
			n.queue_free()
	weapon_main = null
	weapon_off = null
	arrow = null
	_string = null
	_string_surfaces = []
	weapon_id = weapon
	row = weapon_row(weapon)
	_set = clip_set(weapon)
	if _set == null:
		push_error("HHPlayerBody: no clip set for weapon '%s'" % weapon)
		return false
	if row.is_empty():
		push_warning("HHPlayerBody: no manifest row for weapon '%s' in %s" % [weapon, WEAPON_JSON])
	else:
		weapon_main = _attach(str(row.get("glb", "")), str(row.get("socket", "socket_weapon_r")), row.get("mount", {}), "weapon")
		var hands := str(row.get("hands", "one"))
		if hands == "pair" and row.get("offhand_socket") != null:
			weapon_off = _attach(str(row.get("offhand_glb", row.get("glb", ""))), str(row.offhand_socket), row.get("mount", {}), "weapon_off")
		if hands == "bow":
			var pr: Dictionary = projectile_row(str(row.get("projectile", "arrow")))
			if not pr.is_empty():
				arrow = _instance(str(pr.get("glb", "")), "arrow")
				if arrow != null:
					add_child(arrow)
					arrow.visible = false
	clip = ""
	_prev_clip = ""
	_resume = ""
	_hold_at = -1.0
	_held = false
	play(_loco_clip())
	return true


func _instance(path: String, node_name: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("HHPlayerBody: weapon glb %s missing" % path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var n := scene.instantiate() as Node3D
	n.name = node_name
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m3.mesh.get_surface_count():
			# the weapon glbs bake their palette into COLOR_0 (one surface per
			# role, named by role); swap in a lit vertex-colour material with
			# the role's roughness / metallic
			var src := m3.mesh.surface_get_material(i)
			var role := src.resource_name if src else ""
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.albedo_color = (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color.WHITE
			if m.albedo_color.get_luminance() < 0.05:
				m.albedo_color = Color.WHITE
			m.roughness = float(WEAPON_ROUGHNESS.get(role, 0.45))
			m.metallic = float(WEAPON_METALLIC.get(role, 0.0))
			if role == "gem":
				m.emission_enabled = true
				m.emission = Color(0.6, 0.2, 0.9)
				m.emission_energy_multiplier = 0.35
			if role == "feather" or role == "string":
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.resource_name = "hh_" + role
			m3.set_surface_override_material(i, m)
	return n


func _attach(path: String, socket_name: String, mount: Dictionary, node_name: String) -> Node3D:
	var s := socket(socket_name)
	if s == null:
		push_warning("HHPlayerBody: no socket %s for %s" % [socket_name, path])
		return null
	var n := _instance(path, node_name)
	if n == null:
		return null
	s.add_child(n)
	var p: Array = mount.get("position", [0, 0, 0])
	var r: Array = mount.get("rotation_deg", [0, 0, 0])
	n.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	n.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	n.scale = Vector3.ONE * float(row.get("scale", 1.0))
	return n


func _apply_materials(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i)
		var role := mat.resource_name if mat else ""
		if role == "" and mi.mesh is ArrayMesh:
			role = (mi.mesh as ArrayMesh).surface_get_name(i)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.roughness = float(ROUGHNESS.get(role, 0.8))
		if role == "cloak":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED       # the mantle is an open sheet
		m.resource_name = "hh_" + role
		mi.set_surface_override_material(i, m)


func bind(p_sim: HHSim, id: String) -> void:
	sim = p_sim
	unit_id = id


## R-U3: the ward. While the bound unit's `immune` ticks are above zero (H552)
## a pale gold ring and dome spin round the hunter; `ward_on` for tests.
var ward_on := false
var _ward: Node3D = null
var _ward_t := 0.0


func _draw_ward(delta: float) -> void:
	var on := sim != null and unit_id != "" and int(sim.unit(unit_id).get("immune", 0)) > 0
	ward_on = on
	if _ward == null:
		if not on:
			return
		_ward = Node3D.new()
		_ward.name = "ward"
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.95
		tm.outer_radius = 1.08
		tm.rings = 24
		tm.ring_segments = 8
		ring.mesh = tm
		ring.position.y = 0.12
		ring.material_override = _ward_material(Color(1.0, 0.86, 0.35, 0.9))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ward.add_child(ring)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.25
		sm.height = 2.5
		sm.radial_segments = 16
		sm.rings = 8
		dome.mesh = sm
		dome.position.y = 1.15
		dome.material_override = _ward_material(Color(1.0, 0.9, 0.5, 0.22))
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ward.add_child(dome)
		add_child(_ward)
	_ward.visible = on
	if on:
		_ward_t += delta
		_ward.rotation.y = _ward_t * 2.2
		_ward.scale = Vector3.ONE * (1.0 + 0.04 * sin(_ward_t * 9.0))


## H60 (Lane X): the swing trail. A string hit's CLIPS row may carry
## "trail": [from s, to s, strength, "main" | "off" | "both"]; between those
## clip times the blade's edge (manifest trail_base .. tip) is sampled every
## frame into a ribbon in the hunter's element glow that fades in
## TRAIL_LIFE x strength (the finisher's is the longest and brightest).
## World space (top_level), one ImmediateMesh per body, rebuilt only while
## it has points; it freezes with the body in a hit-stop (delta 0).
const TRAIL_LIFE := 0.1
const TRAIL_MAX := 64
const TRAIL_ARC_DEG := 12.0           ## H70: a spin's samples are filled in round the body at most this far apart
var trail_points := 0               ## live ribbon samples (tests, fx-perf)
var _trail: MeshInstance3D = null
var _trail_pts: Array = []          # [age, base, tip, strength] per blade, oldest first
var _trail_life := TRAIL_LIFE


func _draw_trail(delta: float) -> void:
	var row: Dictionary = clips(weapon_id).get(clip, {})
	var tr: Variant = row.get("trail")
	for blade in _trail_pts:
		for p in blade:
			p[0] = float(p[0]) + delta
	for blade in _trail_pts:
		while not (blade as Array).is_empty() and float(blade[0][0]) > _trail_life:
			(blade as Array).pop_front()
	if tr is Array and (tr as Array).size() >= 3 and time >= float(tr[0]) and time <= float(tr[1]) and delta > 0.0:
		var which := str(tr[3]) if (tr as Array).size() > 3 else "main"
		var nodes: Array = []
		if which != "off":
			nodes.append(weapon_main)
		if which != "main":
			nodes.append(weapon_off)
		var strength := float(tr[2])
		_trail_life = float(tr[4]) if (tr as Array).size() > 4 else TRAIL_LIFE * (0.6 + 0.6 * strength)
		while _trail_pts.size() < nodes.size():
			_trail_pts.append([])
		for i in nodes.size():
			var n: Node3D = nodes[i]
			if n == null or n.get_parent() == null:
				continue
			var xf := socket_xform(str(n.get_parent().name)) * n.transform
			var tip := _row_point("tip", Vector3(0, 1, 0))
			var base := _row_point("trail_base", Vector3.ZERO)
			base = tip.lerp(base, clampf(0.35 + 0.2 * strength, 0.0, 0.7))
			var world := global_transform if is_inside_tree() else transform
			var blade: Array = _trail_pts[i]
			var wb: Vector3 = world * (xf * base)
			var wt: Vector3 = world * (xf * tip)
			if not blade.is_empty():
				_fill_arc(blade, wb, wt, strength, world * bone_pos("hips"))
			blade.append([0.0, wb, wt, strength])
			while blade.size() > TRAIL_MAX:
				blade.pop_front()
	trail_points = 0
	for blade in _trail_pts:
		trail_points += (blade as Array).size()
	if trail_points == 0:
		if _trail != null:
			_trail.visible = false
		return
	if _trail == null:
		_trail = MeshInstance3D.new()
		_trail.name = "swing_trail"
		_trail.top_level = true
		_trail.mesh = ImmediateMesh.new()
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED        # mixed, not additive: an additive ribbon washes out to cream on a lit floor (review round 2)
		_trail.material_override = m
		add_child(_trail)
	_trail.visible = true
	if _trail.is_inside_tree():
		_trail.global_transform = Transform3D.IDENTITY
	var col := Color(1.0, 0.95, 0.85)
	if sim != null and unit_id != "":
		col = HHLook.glow_color(str(sim.unit(unit_id).get("element", "")))
	var im: ImmediateMesh = _trail.mesh
	im.clear_surfaces()
	for blade in _trail_pts:
		var pts: Array = blade
		if pts.size() < 2:
			continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for p in pts:
			var k := clampf(1.0 - float(p[0]) / _trail_life, 0.0, 1.0)
			var a := k * clampf(0.35 + 0.15 * float(p[3]), 0.0, 0.58)
			var c := col.lerp(Color.WHITE, 0.15 * k * k)
			im.surface_set_color(Color(c.r, c.g, c.b, a))
			im.surface_add_vertex(p[1])
			im.surface_set_color(Color(c.r, c.g, c.b, minf(1.0, a * 1.3)))
			im.surface_add_vertex(p[2])
		im.surface_end()


## H70: a spin moves the blade 40-60 degrees a frame, so straight ribbon
## segments drew polygons; between the last sample and this one the edge
## is swept round the body's vertical axis (angle, radius and height
## interpolated) in steps of at most TRAIL_ARC_DEG.
func _fill_arc(blade: Array, wb: Vector3, wt: Vector3, strength: float, pivot: Vector3) -> void:
	var last: Array = blade[-1]
	var pb: Vector3 = last[1]
	var pt: Vector3 = last[2]
	var a0 := atan2(pt.x - pivot.x, pt.z - pivot.z)
	var a1 := atan2(wt.x - pivot.x, wt.z - pivot.z)
	var da := wrapf(a1 - a0, -PI, PI)
	var n := int(ceil(absf(rad_to_deg(da)) / TRAIL_ARC_DEG))
	if n < 2:
		return
	for i in range(1, n):
		var u := float(i) / float(n)
		blade.append([0.0, _swept(pb, wb, pivot, u, da), _swept(pt, wt, pivot, u, da), strength])


static func _swept(p0: Vector3, p1: Vector3, pivot: Vector3, u: float, da: float) -> Vector3:
	var r0 := Vector2(p0.x - pivot.x, p0.z - pivot.z)
	var r1 := Vector2(p1.x - pivot.x, p1.z - pivot.z)
	var a := atan2(r0.x, r0.y) + da * u
	var r := lerpf(r0.length(), r1.length(), u)
	return Vector3(pivot.x + r * sin(a), lerpf(p0.y, p1.y, u), pivot.z + r * cos(a))


## A point from the weapon's manifest row (weapon local), or `fallback`.
func _row_point(key: String, fallback: Vector3) -> Vector3:
	var a: Variant = row.get(key)
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _ward_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


# ------------------------------------------------------------------ lookup

func bone(bone_name: String) -> int:
	return int(_bones.get(bone_name, -1))


func has_bone(bone_name: String) -> bool:
	return _bones.has(bone_name)


func bone_names() -> PackedStringArray:
	var out := PackedStringArray(_bones.keys())
	out.sort()
	return out


func socket(socket_name: String) -> Node3D:
	return _sockets.get(socket_name.trim_prefix("socket_"))


func socket_names() -> PackedStringArray:
	var out := PackedStringArray(_sockets.keys())
	out.sort()
	return out


## A socket's posed transform in model space (works outside the tree).
func socket_xform(socket_name: String) -> Transform3D:
	var s := socket(socket_name)
	if s == null or skeleton == null:
		return Transform3D.IDENTITY
	var att := s.get_parent() as BoneAttachment3D
	if att == null:
		return s.transform
	var b := skeleton.find_bone(att.bone_name)
	if b < 0:
		return s.transform
	return skeleton.transform * global_pose(b) * s.transform


func socket_pos(socket_name: String) -> Vector3:
	return socket_xform(socket_name).origin


func bone_pos(bone_name: String) -> Vector3:
	var b := bone(bone_name)
	if b < 0:
		return Vector3.ZERO
	return (skeleton.transform * global_pose(b)).origin


## A bone's global pose from the local poses (Skeleton3D only refreshes its
## own globals inside the tree; tools and tests pose headless).
func global_pose(i: int) -> Transform3D:
	var t := skeleton.get_bone_pose(i)
	var p := skeleton.get_bone_parent(i)
	while p >= 0:
		t = skeleton.get_bone_pose(p) * t
		p = skeleton.get_bone_parent(p)
	return t


func triangle_count() -> int:
	var n := 0
	for mi in meshes:
		for i in mi.mesh.get_surface_count():
			n += mi.mesh.surface_get_array_index_len(i) / 3
	return n


# ------------------------------------------------------------------ pose API

func rot(bone_name: String, euler_deg: Vector3) -> void:
	var i := bone(bone_name)
	if i < 0:
		return
	var r := Basis(Vector3.UP, deg_to_rad(euler_deg.y)) * Basis(Vector3.RIGHT, deg_to_rad(euler_deg.x)) * Basis(Vector3.BACK, deg_to_rad(euler_deg.z))
	var g: Basis = _rest[i]
	var local := g.inverse() * r * g
	var cur: Array = _sample.get(i, [Quaternion.IDENTITY, Vector3.ZERO])
	cur[0] = (cur[0] as Quaternion) * local.get_rotation_quaternion()
	_sample[i] = cur


func move(bone_name: String, offset: Vector3) -> void:
	var i := bone(bone_name)
	if i < 0:
		return
	var g: Basis = _rest[i]
	var cur: Array = _sample.get(i, [Quaternion.IDENTITY, Vector3.ZERO])
	cur[1] = (cur[1] as Vector3) + g.inverse() * offset
	_sample[i] = cur


func bend(chain: Array, total_deg: Vector3, falloff: float = 1.0) -> void:
	var n := chain.size()
	if n == 0:
		return
	var wsum := 0.0
	var ws: Array = []
	for k in n:
		var w := pow(float(k + 1) / float(n), falloff)
		ws.append(w)
		wsum += w
	for k in n:
		rot(str(chain[k]), total_deg * (float(ws[k]) / wsum))


## Plant the ankle of `side` ("l" / "r") at `pos` (model space), sole level
## (+pitch_deg = toes down). Solved after the FK pose is written.
func ik_foot(side: String, pos: Vector3, pitch_deg: float = 0.0, w: float = 1.0) -> void:
	_ik["foot_" + side] = { "pos": pos, "pitch": pitch_deg, "w": w, "anchor": "" }


## Reach the wrist of `side` to `pos`: in model space, or in the posed frame
## of `anchor` (a socket name) so the hand follows what the other hand holds.
## `aim` (not identity) sets the hand's global basis after the reach.
func ik_hand(side: String, pos: Vector3, anchor: String = "", w: float = 1.0, aim: Variant = null, pole: Variant = null, reach: bool = true) -> void:
	_ik["hand_" + side] = { "pos": pos, "anchor": anchor, "w": w, "aim": aim if aim is Basis else Basis.IDENTITY, "has_aim": aim is Basis, "pole": pole, "reach": reach }


func nock(on: bool) -> void:
	_nock = on


# ------------------------------------------------------------------ clips

func play(clip_name: String, p_loop: bool = true, p_speed: float = 1.0) -> bool:
	if _set == null or not clips(weapon_id).has(clip_name):
		push_warning("HHPlayerBody: %s has no clip '%s'" % [weapon_id, clip_name])
		return false
	if clip_name == clip and p_loop and loop:
		return true
	_pending_clip = ""
	if clip != "":
		_prev_clip = clip
		_prev_time = time
		_prev_loop = loop
		_fade_len = FADE_READY if _is_ready_clip(clip) else FADE
		_fade = _fade_len
		if loop:
			_resume = clip
	clip = clip_name
	time = 0.0
	loop = p_loop
	speed = p_speed
	finished_clip = ""
	_hold_at = -1.0
	_held = false
	return true


## Play a one-shot that HOLDS at its contact pose until release() (a wind-up).
func play_held(clip_name: String, p_speed: float = 1.0) -> bool:
	if not play(clip_name, false, p_speed):
		return false
	var ct := int(clips(weapon_id)[clip_name].get("contact_tick", -1))
	_hold_at = float(ct) * HHSim.TICK if ct >= 0 else -1.0
	return true


func release() -> void:
	_hold_at = -1.0
	_held = false
	_pending_clip = ""


## Co-op downed state (H53, H905): the death clip held at its kneel (knees
## gone, chest still up, before the fall onto the back) while an ally can
## revive; off brings the hunter back to its locomotion. Events are ignored
## while down, like after a death.
const DOWN_KNEEL_S := 0.4
var downed := false

func set_downed(on: bool) -> void:
	if on == downed:
		return
	downed = on
	if on:
		_dead = false                       # play() refuses nothing, but on_event must not override the hold
		play("death", false)
		_hold_at = DOWN_KNEEL_S
		_dead = true
		return
	_dead = false
	release()
	clip = ""                               # restart cleanly: no fade from the kneel's held frame
	play(_loco_clip())


## Freeze on one moment of a clip (tools, renders, tests): no fade, IK solved.
func pose_at(clip_name: String, t: float) -> bool:
	if _set == null or not clips(weapon_id).has(clip_name):
		return false
	clip = clip_name
	time = t
	loop = bool(clips(weapon_id)[clip_name].get("loop", false))
	_prev_clip = ""
	_fade = 0.0
	_hold_at = -1.0
	var s := _sample_clip(clip, time)
	_apply(s)
	return true


func duration(clip_name: String) -> float:
	return float(clips(weapon_id).get(clip_name, {}).get("duration", 0.0))


func contact_time(clip_name: String) -> float:
	var ct := int(clips(weapon_id).get(clip_name, {}).get("contact_tick", -1))
	return float(ct) * HHSim.TICK if ct >= 0 else -1.0


const RECOVERY_RATE := 0.3          ## H57: a one-shot plays this slow during the sim's recovery (the pose hold)


## H57: the bound unit is in its post-action recovery.
func recovering() -> bool:
	if sim == null or unit_id == "":
		return false
	return int(sim.unit(unit_id).get("recovery", 0)) > 0


## True while a one-shot is playing (held or not).
func busy() -> bool:
	return clip != "" and not loop and finished_clip == ""


# ------------------------------------------------------------------ update

func update(delta: float) -> void:
	if skeleton == null or clip == "":
		return
	_read_intent(delta)
	_read_motion(delta)
	if _pending_clip != "":
		_pending_in -= delta
		if _pending_in <= 0.0:
			_start_pending(false)
	# locomotion follows the ground speed; a loop with a stride plays at the
	# rate that keeps the stance foot planted
	var d := duration(clip)
	var rate := speed
	var row: Dictionary = clips(weapon_id)[clip]
	var stride := float(row.get("stride", 0.0))
	if loop and stride > 0.0 and d > 0.0:
		rate = (speed_mps / stride) * d
	elif not loop and recovering() and not bool(row.get("timed", false)):
		rate *= RECOVERY_RATE                       # H57: the follow-through holds while the sim's recovery roots the hunter (H60: a timed string hit keys its own)
	if _hold_at >= 0.0 and time + delta * rate >= _hold_at:
		time = _hold_at
		_held = true
	else:
		time += delta * rate
	if loop:
		if d > 0.0:
			time = fmod(time, d)
	elif time >= d:
		time = d
		if finished_clip == "":
			finished_clip = clip
			_on_finished()
			d = duration(clip)
	var cur := _sample_clip(clip, time)
	if _fade > 0.0 and _prev_clip != "":
		_fade -= delta
		_prev_time += delta * speed
		var pd := duration(_prev_clip)
		if _prev_loop and pd > 0.0:
			_prev_time = fmod(_prev_time, pd)
		elif pd > 0.0:
			_prev_time = minf(_prev_time, pd)
		var w := smoothstep(0.0, 1.0, clampf(1.0 - _fade / maxf(_fade_len, 1e-4), 0.0, 1.0))
		cur = _mix(_sample_clip(_prev_clip, _prev_time), cur, w)
		if _fade <= 0.0:
			_prev_clip = ""
	_apply(cur)
	_draw_ward(delta)
	_draw_trail(delta)


## Ground speed from the body's own position delta (HHFight moves the node).
func _read_motion(delta: float) -> void:
	var p := position
	if _last_pos.x != INF and delta > 0.0:
		var v := (p - _last_pos)
		v.y = 0.0
		var inst := v.length() / delta
		var k := clampf(delta / LOCO_SMOOTH, 0.0, 1.0)
		speed_mps = lerpf(speed_mps, inst, k)
	_last_pos = p
	var walk := HHTune.value("walk_mps")
	var run := HHTune.value("run_mps")
	var next := loco
	if speed_mps < walk * 0.2:
		next = "idle"
	elif speed_mps > (walk + run) * 0.5:
		next = "run"
	else:
		next = "walk"
	loco = next
	if _wield_timer > 0.0:
		_wield_timer -= delta
	# a loop follows the locomotion; one-shots run their course first
	if loop and not _dead and clip != _loco_clip() and clip != "guard" and clip != "draw" and not _bracing():
		play(_loco_clip())


## H60: a looping charge clip (the lance's brace) holds while the sim's
## charge does, and through the beat before its release clip starts.
func _bracing() -> bool:
	if clip == "" or clip != charge_clip():
		return false
	if _pending_clip != "":
		return true
	if sim == null or unit_id == "":
		return true
	var ch: Variant = sim.unit(unit_id).get("charging", {})
	return ch is Dictionary and not (ch as Dictionary).is_empty()


func _loco_clip() -> String:
	if loco == "idle":
		var r := ready_clip()
		if r != "":
			return r
		return "wield_idle" if (wielded or _wield_timer > 0.0) and clips(weapon_id).has("wield_idle") else "idle"
	return loco


## H60: the loop a live string holds between hits (the set's READY_CLIPS by
## the bound unit's combo step), "" when no string is open: the window
## lapsed, the string ended or reset, or the body is unbound.
func ready_clip() -> String:
	if sim == null or unit_id == "" or _set == null:
		return ""
	var u := sim.unit(unit_id)
	var cb: Variant = u.get("combo", {})
	if not (cb is Dictionary) or (cb as Dictionary).is_empty():
		return ""
	var until := int((cb as Dictionary).get("until", -1))
	if until < 0 or sim.tick > until:
		return ""
	var m: Variant = _set.get("READY_CLIPS")
	if not (m is Dictionary):
		return ""
	var c := str((m as Dictionary).get(int((cb as Dictionary).get("step", 0)), ""))
	return c if clips(weapon_id).has(c) else ""


func _is_ready_clip(c: String) -> bool:
	var m: Variant = _set.get("READY_CLIPS") if _set != null else null
	return m is Dictionary and c in (m as Dictionary).values()


## Intent from the sim: a target turns the upper body; guard holds; the dead stay down.
func _read_intent(delta: float) -> void:
	var target_yaw := 0.0
	if sim != null and unit_id != "":
		var u := sim.unit(unit_id)
		if not u.is_empty():
			wielded = u.target != "" or not (u.windup as Dictionary).is_empty()
			var ch: Variant = u.get("charging", {})
			var full := maxf(HHTune.value("charge_l3_s") / HHSim.TICK, 1.0)
			charge_frac = clampf(float((ch as Dictionary).get("ticks", 0)) / full, 0.0, 1.0) if ch is Dictionary else 0.0
			if u.target != "" and sim.units.has(u.target):
				var t: Dictionary = sim.units[u.target]
				var d: Vector3 = (t.pos as Vector3) - (u.pos as Vector3)
				if Vector2(d.x, d.z).length_squared() > 1e-4:
					target_yaw = clampf(wrapf(atan2(d.x, d.z) - float(u.facing), -PI, PI), -deg_to_rad(AIM_MAX_DEG), deg_to_rad(AIM_MAX_DEG))
			if clip == "guard" and int(u.guard) <= 0:
				_leave_guard()
	var k := clampf(delta / AIM_LAG, 0.0, 1.0)
	aim_yaw = lerp_angle(aim_yaw, target_yaw, k)


func _on_finished() -> void:
	if _dead:
		return
	if _resume != "" and _resume != clip:
		_resume = ""
	play(_loco_clip())


func _leave_guard() -> void:
	if clip == "guard":
		loop = false
		finished_clip = ""
		time = duration("guard")      # runs the fade out through _on_finished
		_on_finished()


# ------------------------------------------------------------------ events

## Map a sim event about this unit to a clip (see the header table).
func on_event(e: Dictionary, p_sim: HHSim) -> void:
	if sim == null and p_sim != null:
		sim = p_sim
	if unit_id == "":
		unit_id = str(e.get("id", ""))
	if _set == null or _dead:
		return
	var skill_key := str(e.get("skill", ""))
	match str(e.get("type", "")):
		"windup":
			_wield_timer = 3.0
			var kind := str(e.get("kind", "basic"))
			var c := combo_clip(int(e.get("step", 1))) if kind == "basic" else skill_clip_for_windup(kind)
			if c != "" and clips(weapon_id).has(c):
				if c == clip and (_held or _hold_at >= 0.0):
					return                              # H56: the charge pose flows straight into the release
				var ct := contact_time(c)
				var ticks := int(e.get("ticks", 0))
				var from := charge_from(c) if clip == charge_clip() else -1.0
				if from > 0.0 and from < ct:
					# H60: out of the brace: hold it, then run the clip from its
					# coil so the contact lands on the sim's (no slow-motion lunge)
					_pending_clip = c
					_pending_from = from
					_pending_in = maxf(float(ticks) * HHSim.TICK - (ct - from), 0.0)
					return
				# the anticipation spans the sim's wind-up exactly, then holds at contact
				var sp := (ct / (float(ticks) * HHSim.TICK)) if ct > 0.0 and ticks > 0 else 1.0
				play_held(c, clampf(sp, 0.5, 2.0))
		"charge_start":                             # H56: hold the charge pose until the release
			_wield_timer = 3.0
			var cc := charge_clip()
			if cc == "" or not clips(weapon_id).has(cc):
				return
			if bool(clips(weapon_id)[cc].get("loop", false)):
				play(cc, true)
			else:
				play_held(cc, 0.6)
		"charge_cancel":
			release()
			if clip == charge_clip() and loop:
				play(_loco_clip())
		"interrupted":                              # H58: the action is gone; flinch
			release()
			play("hit_react", false)
		"dash":
			var dt := maxf(float(int(e.get("ticks", 6))) * HHSim.TICK, HHSim.TICK)
			if clips(weapon_id).has("dash"):
				release()
				play("dash", false, clampf(0.2 / dt, 0.6, 2.0))
		"strike", "pierce", "miss", "energized_shot", "flourish":
			if _pending_clip != "":
				_start_pending(true)                    # H60: the release beat the brace's count: straight to contact
			if _held or (_hold_at >= 0.0):
				release()
				speed = 1.0
			elif str(e.get("type", "")) == "strike" and clip != "strike" and not busy():
				play("strike", false)
				time = maxf(contact_time("strike") - 0.05, 0.0)
		"windup_broken":
			release()
		"cast":
			_wield_timer = 3.0
			var c := skill_clip(weapon_id, skill_key)
			if c == "" or c == clip or not clips(weapon_id).has(c):
				return
			if c == "guard" or c == "draw":
				play(c, true)
			elif c in ["jump", "arrowstorm_leap", "jump_attack"]:
				pass                               # the leap event starts it, timed to the air
			elif contact_time(c) > 0.0 and str(e.get("type", "")) == "cast" and skill_key == "q" and weapon_id == "lance":
				pass                               # the windup event carries Pierce (plant is held)
			else:
				play(c, false)
		"leap":
			var ticks := int(e.get("ticks", 26))
			var c := skill_clip(weapon_id, "r")
			if c == "" or not clips(weapon_id).has(c):
				c = "jump"
			_land_clip = _landing_for(c)
			var d := duration(c)
			var air := maxf(float(ticks) * HHSim.TICK, HHSim.TICK)
			play(c, false, (d / air) if d > 0.0 else 1.0)
		"land":
			var c := _land_clip if _land_clip != "" else "jump_attack"
			_land_clip = ""
			if clips(weapon_id).has(c):
				play(c, false)
		"eruption":
			pass                                   # the land clip is already the slam
		"stagger":
			var ticks := int(e.get("ticks", 15))
			var d := duration("stagger")
			var want := maxf(float(ticks) * HHSim.TICK, 0.2)
			play("stagger", false, clampf(d / want, 0.4, 2.5) if d > 0.0 else 1.0)
		"hurt":
			if str(e.get("cause", "")) in HURT_CAUSES_IGNORED:
				return
			if clip == "guard" or clip == "stagger" or clip == "death":
				return
			if loop or clip == "hit_react":
				play("hit_react", false)
		"death":
			_dead = true
			_resume = ""
			play("death", false)
		"swap":
			if not busy():
				play("swap", false)
		"guard":
			play("guard", true)


## The wind-up kinds Lane P's weapons emit: "basic" is the strike; "pierce"
## is the lance plant; other kinds map through the set's WINDUP_CLIPS.
## H57: the clip of basic-string hit `step` (the set's COMBO_CLIPS; the bow
## has none: every basic is "strike").
func combo_clip(step: int) -> String:
	var m: Variant = _set.get("COMBO_CLIPS") if _set != null else null
	if m is Dictionary and (m as Dictionary).has(step):
		return str((m as Dictionary)[step])
	return "strike"


## H56: the pose a held charge holds (the set's CHARGE_CLIP).
func charge_clip() -> String:
	var c: Variant = _set.get("CHARGE_CLIP") if _set != null else null
	return str(c) if c != null else ""


## H60: where a release clip starts when it follows the charge clip (the
## set's CHARGE_FROM, seconds: its coil), -1 = from the top.
func charge_from(c: String) -> float:
	var m: Variant = _set.get("CHARGE_FROM") if _set != null else null
	return float((m as Dictionary).get(c, -1.0)) if m is Dictionary else -1.0


func _start_pending(at_contact: bool) -> void:
	var c := _pending_clip
	var from := _pending_from
	_pending_clip = ""
	if c == "" or not clips(weapon_id).has(c):
		return
	play_held(c)
	time = contact_time(c) if at_contact else from


func skill_clip_for_windup(kind: String) -> String:
	var m: Variant = _set.get("WINDUP_CLIPS") if _set != null else null
	if m is Dictionary and (m as Dictionary).has(kind):
		return str((m as Dictionary)[kind])
	return ""


func _landing_for(leap_clip: String) -> String:
	var m: Variant = _set.get("LANDING_CLIPS") if _set != null else null
	if m is Dictionary and (m as Dictionary).has(leap_clip):
		return str((m as Dictionary)[leap_clip])
	return "jump_attack" if clips(weapon_id).has("jump_attack") else ""


# ------------------------------------------------------------------ sampling

func _sample_clip(clip_name: String, t: float) -> Dictionary:
	_sample = {}
	_ik = {}
	_nock = false
	_set.call("pose", clip_name, t, self)
	var out := { "bones": _sample, "ik": _ik, "nock": _nock }
	_sample = {}
	_ik = {}
	return out


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var ab: Dictionary = a.bones
	var bb: Dictionary = b.bones
	var out := {}
	for i in ab:
		out[i] = ab[i]
	for i in bb:
		if out.has(i):
			var pa: Array = out[i]
			var pb: Array = bb[i]
			out[i] = [(pa[0] as Quaternion).slerp(pb[0], w), (pa[1] as Vector3).lerp(pb[1], w)]
		else:
			var pb2: Array = bb[i]
			out[i] = [Quaternion.IDENTITY.slerp(pb2[0], w), (Vector3.ZERO).lerp(pb2[1], w)]
	for i in ab:
		if not bb.has(i):
			var pa2: Array = ab[i]
			out[i] = [(pa2[0] as Quaternion).slerp(Quaternion.IDENTITY, w), (pa2[1] as Vector3).lerp(Vector3.ZERO, w)]
	var ik := {}
	var ai: Dictionary = a.ik
	var bi: Dictionary = b.ik
	for k in ai:
		if bi.has(k) and str(ai[k].anchor) == str(bi[k].anchor):
			var m: Dictionary = (bi[k] as Dictionary).duplicate()
			m.pos = (ai[k].pos as Vector3).lerp(bi[k].pos, w)
			m.w = lerpf(float(ai[k].w), float(bi[k].w), w)
			if m.has("pitch"):
				m.pitch = lerpf(float(ai[k].pitch), float(bi[k].pitch), w)
			ik[k] = m
		else:
			var m2: Dictionary = (ai[k] as Dictionary).duplicate()
			m2.w = float(ai[k].w) * (1.0 - w)
			ik[k] = m2
	for k in bi:
		if not ai.has(k):
			var m3: Dictionary = (bi[k] as Dictionary).duplicate()
			m3.w = float(bi[k].w) * w
			ik[k] = m3
		elif str(ai[k].anchor) != str(bi[k].anchor):
			if w >= 0.5:
				var m4: Dictionary = (bi[k] as Dictionary).duplicate()
				m4.w = float(bi[k].w) * w
				ik[k] = m4
	return { "bones": out, "ik": ik, "nock": bool(b.nock) if w >= 0.5 else bool(a.nock) }


## Write a sample: FK bones, the aim layer, then IK, then the arrow.
func _apply(s: Dictionary) -> void:
	var bones: Dictionary = s.bones
	if absf(aim_yaw) > 1e-3:
		_sample = bones
		var deg := rad_to_deg(aim_yaw)
		rot("spine", Vector3(0.0, deg * 0.3, 0.0))
		rot("chest", Vector3(0.0, deg * 0.4, 0.0))
		rot("head", Vector3(0.0, deg * 0.3, 0.0))
		bones = _sample
		_sample = {}
	_write(bones)
	var ik: Dictionary = s.ik
	for key in ik:
		var k := str(key)
		var r: Dictionary = ik[key]
		if float(r.w) <= 0.0:
			continue
		if k.begins_with("foot_"):
			_solve_limb(k, r.pos, Vector3(0, 0, 1), float(r.w))
			_level_foot(k, float(r.get("pitch", 0.0)), float(r.w))
		else:
			var target: Vector3 = r.pos
			if str(r.anchor) != "":
				target = socket_xform(str(r.anchor)) * (r.pos as Vector3)
			var side := k.trim_prefix("hand_")
			var pole := Vector3(0.6 if side == "l" else -0.6, -0.5, -0.45)    # elbows out, down and back
			if r.get("pole") is Vector3:
				pole = r.pole
			if bool(r.get("reach", true)):
				_solve_limb(k, target, pole, float(r.w))
			if bool(r.get("has_aim", false)):
				_aim_hand(k, r.aim, float(r.w))
	if arrow != null:
		arrow.visible = bool(s.nock)
		if arrow.visible:
			# the arrow's nock sits in the draw hand, its head toward the bow
			# hand; Lane A's arrow has its origin at the shaft's middle with +Y
			# to the head (manifest trail_base = the nock), so the origin is
			# pushed up the shaft by the nock's distance
			var a := socket_pos("socket_weapon_r")
			var b := socket_pos("socket_offhand_l")
			var dir := (b - a)
			if dir.length_squared() > 1e-4:
				dir = dir.normalized()
				var pr := projectile_row(str(row.get("projectile", "arrow")))
				var nock_y := -0.42
				if pr.has("trail_base"):
					var tb: Array = pr.trail_base
					nock_y = float(tb[1])
				var basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)   # +Y along dir
				arrow.transform = Transform3D(basis, a - dir * nock_y)
	_draw_string(bool(s.nock))


## The bowstring: the bow's own straight "string" surface is hidden while an
## arrow is nocked and a drawn string is drawn from the string's two ends
## (manifest `string`, bow-local) to the draw hand.
func _draw_string(nocked: bool) -> void:
	if weapon_main == null or not row.has("string"):
		return
	if _string == null:
		_string = MeshInstance3D.new()
		_string.name = "drawn_string"
		_string.mesh = ImmediateMesh.new()
		_string.material_override = HHLook.flat(Color(0.92, 0.9, 0.82))
		_string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_string)
		for mi in weapon_main.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			for i in m3.mesh.get_surface_count():
				var src := m3.mesh.surface_get_material(i)
				if src != null and src.resource_name == "string":
					_string_surfaces.append([m3, i])
	for sf in _string_surfaces:
		var mat := (sf[0] as MeshInstance3D).get_surface_override_material(int(sf[1])) as StandardMaterial3D
		if mat != null:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if nocked else BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 0.0 if nocked else 1.0
	_string.visible = nocked
	if not nocked:
		return
	var im: ImmediateMesh = _string.mesh
	im.clear_surfaces()
	var bow_xf := socket_xform(str(row.get("socket", "socket_offhand_l"))) * weapon_main.transform
	var hand := socket_pos("socket_weapon_r")
	var ends: Array = row.string
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_add_vertex(bow_xf * Vector3(float(ends[0][0]), float(ends[0][1]), float(ends[0][2])))
	im.surface_add_vertex(hand)
	im.surface_add_vertex(bow_xf * Vector3(float(ends[1][0]), float(ends[1][1]), float(ends[1][2])))
	im.surface_end()


func _write(sample: Dictionary) -> void:
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		if sample.has(i):
			var s: Array = sample[i]
			var q: Quaternion = s[0]
			var p: Vector3 = s[1]
			skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion() * q)
			skeleton.set_bone_pose_position(i, rest.origin + rest.basis * p)
		else:
			skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_position(i, rest.origin)


func reset_pose() -> void:
	if skeleton:
		_write({})


# ------------------------------------------------------------------ IK

## Two-bone IK on LIMBS[key] toward `target` (model space): the mid joint
## bends toward `pole`. `w` blends from the FK pose.
func _solve_limb(key: String, target: Vector3, pole: Vector3, w: float) -> void:
	var names: Array = LIMBS[key]
	var a := bone(names[0])
	var b := bone(names[1])
	var c := bone(names[2])
	if a < 0 or b < 0 or c < 0:
		return
	var inv := skeleton.transform.affine_inverse()
	var T: Vector3 = inv * target
	var A := global_pose(a).origin
	var B := global_pose(b).origin
	var C := global_pose(c).origin
	var l1 := A.distance_to(B)
	var l2 := B.distance_to(C)
	var to := T - A
	var dist := clampf(to.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	if to.length_squared() < 1e-8:
		return
	var u := to.normalized()
	var n := pole - u * pole.dot(u)
	if n.length_squared() < 1e-6:
		n = Vector3.UP - u * Vector3.UP.dot(u)
		if n.length_squared() < 1e-6:
			n = Vector3.FORWARD
	n = n.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var Bn := A + (u * cos_a + n * sin_a) * l1
	var Tn := A + u * dist
	_rotate_toward(a, B - A, Bn - A, w)
	B = global_pose(b).origin
	C = global_pose(c).origin
	_rotate_toward(b, C - B, Tn - B, w)


## Turn bone `i` (globally, about its head) so direction `from` becomes `to`.
func _rotate_toward(i: int, from: Vector3, to: Vector3, w: float) -> void:
	if from.length_squared() < 1e-8 or to.length_squared() < 1e-8:
		return
	var f := from.normalized()
	var t := to.normalized()
	var d := clampf(f.dot(t), -1.0, 1.0)
	var axis := f.cross(t)
	var q := Quaternion.IDENTITY
	if axis.length_squared() < 1e-8:
		if d < 0.0:
			var any := Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
			q = Quaternion(any.cross(f).normalized(), PI)
	else:
		q = Quaternion(axis.normalized(), acos(d))
	var g := global_pose(i)
	var parent := skeleton.get_bone_parent(i)
	var pg := global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var new_global := Basis(q) * g.basis
	var local := (pg.inverse() * new_global).get_rotation_quaternion()
	var cur := skeleton.get_bone_pose_rotation(i)
	skeleton.set_bone_pose_rotation(i, cur.slerp(local, w))


## The foot keeps its rest orientation in model space (sole level), pitched.
func _level_foot(key: String, pitch_deg: float, w: float) -> void:
	var names: Array = LIMBS[key]
	var c := bone(names[2])
	if c < 0:
		return
	var parent := skeleton.get_bone_parent(c)
	var pg := global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var want: Basis = Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * (_rest[c] as Basis)
	var local := (pg.inverse() * want).get_rotation_quaternion()
	var cur := skeleton.get_bone_pose_rotation(c)
	skeleton.set_bone_pose_rotation(c, cur.slerp(local, w))


func _aim_hand(key: String, aim: Basis, w: float) -> void:
	var names: Array = LIMBS[key]
	var c := bone(names[2])
	if c < 0:
		return
	var parent := skeleton.get_bone_parent(c)
	var pg := global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var want: Basis = aim * (_rest[c] as Basis)
	var local := (pg.inverse() * want).get_rotation_quaternion()
	var cur := skeleton.get_bone_pose_rotation(c)
	skeleton.set_bone_pose_rotation(c, cur.slerp(local, w))
