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
	for n in [weapon_main, weapon_off, arrow]:
		if n != null:
			n.queue_free()
	weapon_main = null
	weapon_off = null
	arrow = null
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
	if clip != "":
		_prev_clip = clip
		_prev_time = time
		_prev_loop = loop
		_fade = FADE
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


## True while a one-shot is playing (held or not).
func busy() -> bool:
	return clip != "" and not loop and finished_clip == ""


# ------------------------------------------------------------------ update

func update(delta: float) -> void:
	if skeleton == null or clip == "":
		return
	_read_intent(delta)
	_read_motion(delta)
	# locomotion follows the ground speed; a loop with a stride plays at the
	# rate that keeps the stance foot planted
	var d := duration(clip)
	var rate := speed
	var stride := float(clips(weapon_id)[clip].get("stride", 0.0))
	if loop and stride > 0.0 and d > 0.0:
		rate = (speed_mps / stride) * d
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
		var w := smoothstep(0.0, 1.0, clampf(1.0 - _fade / FADE, 0.0, 1.0))
		cur = _mix(_sample_clip(_prev_clip, _prev_time), cur, w)
		if _fade <= 0.0:
			_prev_clip = ""
	_apply(cur)


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
	if loop and not _dead and clip != _loco_clip() and clip != "guard" and clip != "draw":
		play(_loco_clip())


func _loco_clip() -> String:
	if loco == "idle":
		return "wield_idle" if (wielded or _wield_timer > 0.0) and clips(weapon_id).has("wield_idle") else "idle"
	return loco


## Intent from the sim: a target turns the upper body; guard holds; the dead stay down.
func _read_intent(delta: float) -> void:
	var target_yaw := 0.0
	if sim != null and unit_id != "":
		var u := sim.unit(unit_id)
		if not u.is_empty():
			wielded = u.target != "" or not (u.windup as Dictionary).is_empty()
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
			var c := "strike" if kind == "basic" else skill_clip_for_windup(kind)
			if c != "" and clips(weapon_id).has(c):
				var ct := contact_time(c)
				var ticks := int(e.get("ticks", 0))
				# the anticipation spans the sim's wind-up exactly, then holds at contact
				var sp := (ct / (float(ticks) * HHSim.TICK)) if ct > 0.0 and ticks > 0 else 1.0
				play_held(c, clampf(sp, 0.5, 2.0))
		"strike", "pierce", "miss":
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
			var a := socket_pos("socket_weapon_r")
			var b := socket_pos("socket_offhand_l")
			var dir := (b - a)
			if dir.length_squared() > 1e-4:
				dir = dir.normalized()
				arrow.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), a + dir * 0.9)


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
